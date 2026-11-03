import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image/image.dart' as im;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pool/pool.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/is_this_a_test.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:screenshot/screenshot.dart';

abstract class EditorExporter {
  /// Most* strokes can be drawn to the PDF canvas as vector graphics.
  /// This function returns true if [stroke] is one of those strokes.
  ///
  /// Strokes that can't be drawn as vector graphics include:
  /// - Highlighter strokes, because PDFs don't support transparency
  /// - Pencil strokes, which need a special shader to look correct
  static bool shouldRasterizeStroke(Stroke stroke) {
    return stroke.toolId == .highlighter || stroke.toolId == .pencil;
  }

  static Future<pw.Document> generatePdf(
    EditorCoreInfo coreInfo,
    BuildContext context,
  ) async {
    if (coreInfo.pages.isNotEmpty && coreInfo.pages.last.isEmpty) {
      // don't export the empty last page
      coreInfo = coreInfo.copyWith(
        pages: coreInfo.pages.toList()..removeLast(),
      );
    }

    final pdf = pw.Document();

    // screenshot each page
    final pool = Pool((Platform.numberOfProcessors ~/ 2).clamp(1, 4));
    final pageScreenshots = await Future.wait(
      List.generate(
        coreInfo.pages.length,
        (pageIndex) => pool.withResource(() async {
          final uiImage = await screenshotPage(
            coreInfo: coreInfo,
            pageIndex: pageIndex,
          );
          final byteData = await uiImage.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          assert(
            byteData != null,
            'Judging by the code, this should never be null.',
          );
          final imImage = im.Image.fromBytes(
            width: uiImage.width,
            height: uiImage.height,
            bytes: byteData!.buffer,
            order: im.ChannelOrder.rgba,
          );
          uiImage.dispose();
          return imImage;
        }),
      ),
    );

    for (int pageIndex = 0; pageIndex < pageScreenshots.length; ++pageIndex) {
      final page = coreInfo.pages[pageIndex];
      final pageSize = page.size;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pageSize.width, pageSize.height),
          build: (pw.Context context) {
            final content = pw.SizedBox(
              width: pageSize.width,
              height: pageSize.height,
              child: pw.CustomPaint(
                foregroundPainter: (PdfGraphics pdfGraphics, PdfPoint size) {
                  final backgroundColor = PdfColor.fromInt(
                    coreInfo.backgroundColor?.toARGB32() ??
                        InnerCanvas.defaultBackgroundColor.toARGB32(),
                  ).flatten();

                  final strokes = page.strokes.where(
                    (stroke) => !shouldRasterizeStroke(stroke),
                  );
                  for (final stroke in strokes) {
                    final strokeColor = PdfColor.fromInt(
                      stroke.color.toARGB32(),
                    ).flatten(background: backgroundColor);
                    final fillColor = stroke.fillColor == null
                        ? null
                        : PdfColor.fromInt(stroke.fillColor!.toARGB32())
                              .flatten(background: backgroundColor);
                    final pageHeight = pageSize.height;

                    void outline() {
                      pdfGraphics.setStrokeColor(strokeColor);
                      pdfGraphics.setLineWidth(stroke.options.size);
                      if (stroke.dashed) {
                        final size = max(stroke.options.size, 1.0);
                        pdfGraphics.setLineDashPattern([size * 3, size * 2.5]);
                      }
                      pdfGraphics.strokePath();
                      if (stroke.dashed) pdfGraphics.setLineDashPattern();
                    }

                    void polyline(List<Offset> points, {bool close = false}) {
                      pdfGraphics.moveTo(
                        points.first.dx,
                        pageHeight - points.first.dy,
                      );
                      for (final point in points.skip(1)) {
                        pdfGraphics.lineTo(point.dx, pageHeight - point.dy);
                      }
                      if (close) pdfGraphics.closePath();
                    }

                    void circlePath(CircleStroke circle) =>
                        pdfGraphics.drawEllipse(
                          circle.center.dx,
                          pageHeight - circle.center.dy,
                          circle.radius,
                          circle.radius,
                          clockwise: false,
                        );

                    void rectPath(RectangleStroke rect) {
                      final strokeSize = rect.options.size;
                      pdfGraphics.drawRRect(
                        rect.rect.left,
                        pageHeight - rect.rect.bottom,
                        rect.rect.width,
                        rect.rect.height,
                        strokeSize / 4,
                        strokeSize / 4,
                      );
                    }

                    if (stroke is GraphStroke) {
                      final drawing = stroke.drawing;
                      pdfGraphics.saveContext();
                      final f = stroke.frame;
                      pdfGraphics.drawRect(
                        f.left,
                        pageHeight - f.bottom,
                        f.width,
                        f.height,
                      );
                      pdfGraphics.clipPath();
                      final thin = max(stroke.options.size * 0.5, 1.0);
                      for (final (from, to) in drawing.axes) {
                        polyline([from, to]);
                        for (final (a, b)
                            in ShapeGeometry.arrowhead([from, to], thin) ??
                                const <(Offset, Offset)>[]) {
                          polyline([a, b]);
                        }
                      }
                      pdfGraphics.setStrokeColor(strokeColor);
                      pdfGraphics.setLineWidth(thin);
                      pdfGraphics.strokePath();
                      for (final (from, to) in drawing.asymptotes) {
                        polyline([from, to]);
                      }
                      pdfGraphics.setLineDashPattern([thin * 4, thin * 4]);
                      pdfGraphics.strokePath();
                      pdfGraphics.setLineDashPattern();
                      for (final piece in drawing.curve) {
                        polyline(piece);
                      }
                      outline();
                      pdfGraphics.restoreContext();
                      continue;
                    }

                    if (stroke is CircleStroke || stroke is RectangleStroke) {
                      void shapePath() => stroke is CircleStroke
                          ? circlePath(stroke)
                          : rectPath(stroke as RectangleStroke);
                      if (fillColor != null) {
                        shapePath();
                        pdfGraphics.setFillColor(fillColor);
                        pdfGraphics.fillPath();
                      }
                      shapePath();
                      outline();
                      continue;
                    }

                    final line = stroke.centerline;
                    final closed =
                        line.length >= 2 &&
                        (line.first - line.last).distance <=
                            stroke.options.size * 2;
                    final styledOutline =
                        line.length >= 2 &&
                        (stroke.crisp ||
                            stroke.dashed ||
                            (fillColor != null && closed));

                    if (styledOutline) {
                      if (fillColor != null && closed) {
                        polyline(line, close: true);
                        pdfGraphics.setFillColor(fillColor);
                        pdfGraphics.fillPath();
                      }
                      polyline(line, close: closed);
                      outline();
                    } else {
                      pdfGraphics.drawShape(stroke.toSvgPath());
                      pdfGraphics.setFillColor(strokeColor);
                      pdfGraphics.fillPath();
                    }

                    if (stroke.arrowEnd && line.length >= 2) {
                      final head = ShapeGeometry.arrowhead(
                        line,
                        stroke.options.size,
                      );
                      if (head != null) {
                        for (final (from, to) in head) {
                          polyline([from, to]);
                        }
                        pdfGraphics.setStrokeColor(strokeColor);
                        pdfGraphics.setLineWidth(stroke.options.size);
                        pdfGraphics.strokePath();
                      }
                    }
                  }
                },
                child: pw.Image(
                  pw.ImageImage(pageScreenshots[pageIndex]),
                  width: pageSize.width,
                  height: pageSize.height,
                ),
              ),
            );
            final notes = Annotations.inUse(page.annotations, page.strokes);
            if (page.outline.isEmpty && notes.isEmpty) return content;
            // The note's bookmarks and annotations become the PDF's
            // table of contents
            return pw.Stack(
              children: [
                content,
                for (final (i, entry) in page.outline.indexed)
                  pw.Outline(
                    name: 'saber-outline-$pageIndex-$i',
                    title: entry.title,
                    level: entry.level,
                    child: pw.SizedBox(width: 1, height: 1),
                  ),
                for (final note in notes)
                  pw.Outline(
                    name: 'saber-note-$pageIndex-${note.id}',
                    title:
                        note.name ??
                        t.editor.notes.unnamed(
                          kind: noteKindLabel(note.kind),
                          n: '${pageIndex + 1}',
                        ),
                    child: pw.SizedBox(width: 1, height: 1),
                  ),
              ],
            );
          },
        ),
      );
    }

    return pdf;
  }

  /// Returns a screenshot of the page at [pageIndex] in [coreInfo].
  ///
  /// Note that screenshots do not include most* strokes
  /// because they're added separately to the PDF as vector graphics.
  /// See [shouldRasterizeStroke] for more details, or set
  /// [rasterizeAllStrokes] to true to include all strokes in the screenshot.
  ///
  /// You must dispose this image when you're done.
  static Future<ui.Image> screenshotPage({
    required EditorCoreInfo coreInfo,
    required int pageIndex,
    bool rasterizeAllStrokes = false,
    Size? targetSize,
    double? cropHeight,
    double pixelRatio = 2,
  }) async {
    final page = coreInfo.pages[pageIndex].cloneForRasterization(
      rasterizeAllStrokes: rasterizeAllStrokes,
    );

    final imagesToLoad = [
      ?page.backgroundImage,
      ...page.images,
    ].where((image) => !image.loadedIn).toList(growable: false);
    await Future.wait(imagesToLoad.map((image) => image.loadIn()))
        .timeout(const Duration(seconds: 10), onTimeout: () => const []);

    try {
      targetSize ??= page.size;
      coreInfo = coreInfo.copyWith(
        pages: [for (var i = 0; i < coreInfo.pages.length; ++i) page],
      );
      return await ScreenshotController.widgetToUiImage(
        EditorExporterTheme(
          targetSize: targetSize,
          child: CanvasPreview(
            pageIndex: pageIndex,
            height: cropHeight,
            coreInfo: coreInfo,
          ),
        ),
        pixelRatio: pixelRatio,
        targetSize: targetSize,
        delay: isThisATest ? .zero : const Duration(milliseconds: 200),
      );
    } finally {
      for (final image in imagesToLoad) unawaited(image.loadOut());
      page.disposeClonedData();
    }
  }
}

/// Applies a consistent theme to its [child] so that exports
/// look the same regardless of the user's current theme or device.
class EditorExporterTheme extends StatelessWidget {
  const new({super.key, required this.targetSize, required this.child});

  final Size targetSize;
  final Widget child;

  static final theme = ThemeData(
    brightness: .light,
    colorScheme: const ColorScheme.light(
      primary: Colors.blue,
      secondary: Colors.red,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: targetSize),
      child: Localizations(
        // needed to avoid errors with Quill, but not actually used
        locale: const Locale('en', 'US'),
        delegates: GlobalMaterialLocalizations.delegates,
        child: Theme(
          data: theme,
          child: DefaultTextStyle(
            style: theme.textTheme.bodyMedium!,
            child: SizedBox(
              width: targetSize.width,
              height: targetSize.height,
              child: FittedBox(
                fit: BoxFit.cover,
                alignment: Alignment.topLeft,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
