import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_pen.dart';

class CanvasPainter extends CustomPainter {
  const new({
    super.repaint,
    this.invert = false,
    required this.strokes,
    required this.laserStrokes,
    required this.currentStroke,
    required this.currentSelection,
    required this.primaryColor,
    required this.page,
    required this.showPageIndicator,
    required this.pageIndex,
    required this.totalPages,
    required this.currentScale,
    required this.defaultTextStyle,
  });

  final bool invert;
  final List<Stroke> strokes;
  final List<LaserStroke> laserStrokes;
  final Stroke? currentStroke;
  final SelectResult? currentSelection;
  final Color primaryColor;
  final EditorPage page;
  final bool showPageIndicator;
  final int pageIndex;
  final int totalPages;
  final double currentScale;
  final TextStyle defaultTextStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;

    _drawHighlighterStrokes(canvas, canvasRect);
    _drawNonHighlighterStrokes(canvas);
    for (final stroke in laserStrokes) _drawLaserStroke(canvas, stroke);
    _drawCurrentStroke(canvas);
    _drawDetectedShape(canvas);
    _drawSelection(canvas);
    _drawPageIndicator(canvas, size);
  }

  @override
  bool shouldRepaint(CanvasPainter oldDelegate) {
    return false ||
        // Current stroke is being drawn, so always repaint if present
        (currentStroke != null || oldDelegate.currentStroke != null) ||
        // Laser strokes are always fading out, so always repaint if present
        (laserStrokes.isNotEmpty || oldDelegate.laserStrokes.isNotEmpty) ||
        // Check for any other changes
        invert != oldDelegate.invert ||
        strokes.length != oldDelegate.strokes.length ||
        currentSelection != oldDelegate.currentSelection ||
        primaryColor != oldDelegate.primaryColor ||
        page != oldDelegate.page ||
        showPageIndicator != oldDelegate.showPageIndicator ||
        pageIndex != oldDelegate.pageIndex ||
        totalPages != oldDelegate.totalPages ||
        currentScale != oldDelegate.currentScale;
  }

  void _drawHighlighterStrokes(Canvas canvas, Rect canvasRect) {
    final layerPaint = Paint()
      ..blendMode = invert ? BlendMode.lighten : BlendMode.darken
      ..color = Colors.white.withAlpha(Highlighter.alpha);
    bool needToRestoreCanvasLayer = false;

    Color? lastColor;
    for (final stroke in strokes) {
      if (stroke.toolId != .highlighter) continue;

      final color = stroke.color.withValues(alpha: 1).withInversion(invert);

      if (color != lastColor) {
        // new layer for each color
        if (needToRestoreCanvasLayer) canvas.restore();
        canvas.saveLayer(canvasRect, layerPaint);

        needToRestoreCanvasLayer = true;
        lastColor = color;
      }

      canvas.drawPath(_selectPath(stroke), Paint()..color = color);
    }

    if (needToRestoreCanvasLayer) canvas.restore();
  }

  void _drawNonHighlighterStrokes(Canvas canvas) {
    late final paint = Paint();

    for (final stroke in strokes) {
      if (stroke.toolId == .highlighter) continue;

      var color = stroke.color.withInversion(invert);
      if (currentSelection?.strokes.contains(stroke) ?? false) {
        color = Color.lerp(color, primaryColor, 0.5)!;
      }

      paint.color = color;
      paint.shader = null;
      paint.maskFilter = null;
      if (stroke.toolId == .pencil) {
        if (shouldUsePencilShader(stroke.options.size)) {
          paint.color = Colors.white;
          paint.shader = page.pencilShader
            ..setFloat(0, color.r)
            ..setFloat(1, color.g)
            ..setFloat(2, color.b);
          paint.maskFilter = _getPencilMaskFilter(stroke.options.size);
        } else {
          // Fast imitation of pencil when zoomed out
          final background = invert ? Colors.black : Colors.white;
          paint.color = Color.lerp(background, color, 0.6)!;
        }
      }

      late final shapePaint = Paint()
        ..color = paint.color
        ..style = .stroke
        ..strokeWidth = stroke.options.size
        ..strokeCap = .round
        ..strokeJoin = .round;

      if (stroke is CircleStroke) {
        _drawStyledOutline(
          canvas,
          stroke,
          Path()..addOval(
            Rect.fromCircle(center: stroke.center, radius: stroke.radius),
          ),
          shapePaint,
        );
      } else if (stroke is RectangleStroke) {
        final strokeSize = stroke.options.size;
        _drawStyledOutline(
          canvas,
          stroke,
          Path()..addRRect(
            RRect.fromRectAndRadius(
              stroke.rect,
              Radius.circular(strokeSize / 4),
            ),
          ),
          shapePaint,
        );
      } else if (stroke.hasStyle && stroke.centerline.length >= 2) {
        final line = stroke.centerline;
        final closed =
            (line.first - line.last).distance <= stroke.options.size * 2;
        if (stroke.dashed || (stroke.fillColor != null && closed)) {
          _drawStyledOutline(
            canvas,
            stroke,
            Path()..addPolygon(line, closed),
            shapePaint,
            canFill: closed,
          );
        } else {
          canvas.drawPath(_selectPath(stroke), paint);
        }
        if (stroke.arrowEnd) _drawArrowhead(canvas, stroke, line, shapePaint);
      } else {
        canvas.drawPath(_selectPath(stroke), paint);
      }
    }
  }

  /// Draws [path] for [stroke] with its fill and dash style.
  void _drawStyledOutline(
    Canvas canvas,
    Stroke stroke,
    Path path,
    Paint outlinePaint, {
    bool canFill = true,
  }) {
    final fill = stroke.fillColor;
    if (fill != null && canFill) {
      canvas.drawPath(path, Paint()..color = fill.withInversion(invert));
    }
    if (stroke.dashed) {
      final size = max(stroke.options.size, 1.0);
      canvas.drawPath(
        dashPath(path, dashArray: CircularIntervalList([size * 3, size * 2.5])),
        outlinePaint,
      );
    } else {
      canvas.drawPath(path, outlinePaint);
    }
  }

  /// Draws an arrowhead at the end of [line].
  void _drawArrowhead(
    Canvas canvas,
    Stroke stroke,
    List<Offset> line,
    Paint paint,
  ) {
    final tip = line.last;
    final reach = max(stroke.options.size * 3, 6.0);
    // Look back far enough that the pen's wobble doesn't set the direction.
    var from = line.first;
    for (int i = line.length - 2; i >= 0; i--) {
      if ((line[i] - tip).distance >= reach) {
        from = line[i];
        break;
      }
    }
    if (from == tip) return;
    final direction = (tip - from).direction;
    final length = max(12.0, stroke.options.size * 4);
    const spread = 2.6; // radians back from the direction, about 150°
    canvas.drawLine(
      tip,
      tip + Offset.fromDirection(direction + spread, length),
      paint,
    );
    canvas.drawLine(
      tip,
      tip + Offset.fromDirection(direction - spread, length),
      paint,
    );
  }

  void _drawCurrentStroke(Canvas canvas) {
    if (currentStroke == null) return;

    if (currentStroke! is LaserStroke) {
      return _drawLaserStroke(canvas, currentStroke as LaserStroke);
    }

    final color = currentStroke!.color.withInversion(invert);
    final paint = Paint();

    paint.color = color;
    paint.shader = null;
    paint.maskFilter = null;
    if (currentStroke!.toolId == .pencil) {
      paint.color = Colors.white;
      paint.shader = page.pencilShader
        ..setFloat(0, color.r)
        ..setFloat(1, color.g)
        ..setFloat(2, color.b);
      paint.maskFilter = _getPencilMaskFilter(currentStroke!.options.size);
    }

    // Current stroke always uses high quality
    canvas.drawPath(currentStroke!.highQualityPath, paint);
  }

  void _drawLaserStroke(Canvas canvas, LaserStroke stroke) {
    canvas.drawPath(
      _selectPath(stroke),
      Paint()
        ..color = stroke.color.withInversion(invert)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.solid,
          stroke.options.size * 0.4,
        ),
    );
    canvas.drawPath(stroke.innerPath, Paint()..color = const Color(0xDDffffff));
  }

  void _drawDetectedShape(Canvas canvas) {
    final shape = ShapePen.detectedShape;
    if (shape == null) return;

    final color = currentStroke?.color.withInversion(invert) ?? Colors.black;
    final shapePaint = Paint()
      ..color = Color.lerp(color, primaryColor, 0.5)!.withValues(alpha: 0.7)
      ..style = .stroke
      ..strokeWidth = currentStroke?.options.size ?? 3;

    switch (shape.name) {
      case null:
        break;
      case DefaultUnistrokeNames.line:
        var (firstPoint, lastPoint) = shape.convertToLine();
        (firstPoint, lastPoint) = Stroke.snapLine(
          firstPoint is PointVector
              ? firstPoint
              : PointVector.fromOffset(offset: firstPoint),
          lastPoint is PointVector
              ? lastPoint
              : PointVector.fromOffset(offset: lastPoint),
        );
        canvas.drawLine(firstPoint, lastPoint, shapePaint);
      case DefaultUnistrokeNames.rectangle:
        // Preview the angle the rectangle will keep (see ShapePen).
        final corners = currentStroke == null
            ? const <Offset>[]
            : ShapeGeometry.minAreaRect(currentStroke!.centerline);
        if (corners.isNotEmpty && !ShapeGeometry.isUpright(corners)) {
          canvas.drawPath(Path()..addPolygon(corners, true), shapePaint);
        } else {
          canvas.drawRect(shape.convertToRect(), shapePaint);
        }
      case DefaultUnistrokeNames.circle:
        final (center, radius) = shape.convertToCircle();
        canvas.drawCircle(center, radius, shapePaint);
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        final polygon = shape.convertToCanonicalPolygon();
        canvas.drawPath(Path()..addPolygon(polygon, true), shapePaint);
    }
  }

  void _drawSelection(Canvas canvas) {
    if (currentSelection == null) return;

    // Once something is selected, the box with handles replaces the lasso.
    if (_drawSelectionBox(canvas)) return;

    // draw translucent fill
    canvas.drawPath(
      currentSelection!.path,
      Paint()..color = primaryColor.withValues(alpha: 0.1),
    );

    // draw dashed stroke
    canvas.drawPath(
      dashPath(
        currentSelection!.path,
        dashArray: CircularIntervalList([10, 10]),
      ),
      Paint()
        ..color = primaryColor
        ..strokeWidth = 3
        ..style = .stroke,
    );
  }

  /// Draws the box with resize handles and the rotate handle around the
  /// selected content. The box turns with the selection.
  /// Returns false if there's no box to draw (e.g. still lassoing).
  bool _drawSelectionBox(Canvas canvas) {
    final selection = currentSelection!;
    final box = SelectionTransform.contentBox(
      selection.strokes,
      selection.images,
      angle: selection.frameAngle,
    );
    if (box == null) return false;
    // Previews are drawn without a real zoom level
    if (currentScale < 0.01) return true;

    final scale = currentScale;
    final handles = SelectionTransform.handlePositions(box, scale);
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 1.5 / scale
      ..style = .stroke;

    canvas.drawPath(
      Path()..addPolygon(box.corners, true),
      Paint()..color = primaryColor.withValues(alpha: 0.06),
    );
    canvas.drawPath(Path()..addPolygon(box.corners, true), linePaint);
    canvas.drawLine(
      box.toPage(box.local.topCenter),
      handles[SelectionHandle.rotate]!,
      linePaint,
    );

    final radius = SelectionTransform.handleRadius / scale;
    final fillPaint = Paint()..color = Colors.white;
    for (final MapEntry(key: handle, value: center) in handles.entries) {
      canvas.drawCircle(
        center,
        radius,
        handle == .rotate ? (Paint()..color = primaryColor) : fillPaint,
      );
      canvas.drawCircle(center, radius, linePaint);
    }

    final degrees = selection.rotationDegrees;
    if (degrees != null) {
      final text = TextPainter(
        text: TextSpan(
          text: '${degrees.round()}°',
          style: TextStyle(
            color: primaryColor,
            fontSize: 16 / scale,
            fontWeight: .bold,
          ),
        ),
        textDirection: .ltr,
      )..layout();
      final rotateHandle = handles[SelectionHandle.rotate]!;
      text.paint(canvas, rotateHandle + Offset(radius * 1.8, -text.height / 2));
    }
    return true;
  }

  static const double _pageIndicatorFontSize = 20;
  static const double _pageIndicatorPadding = 5;
  void _drawPageIndicator(Canvas canvas, Size pageSize) {
    if (!showPageIndicator) return;

    final style = ui.ParagraphStyle(
      textAlign: .end,
      textDirection: .ltr,
      maxLines: 1,
    );

    final builder = ui.ParagraphBuilder(style)
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black.withInversion(invert).withValues(alpha: 0.5),
          fontSize: _pageIndicatorFontSize,
          fontFamily: defaultTextStyle.fontFamily,
          fontFamilyFallback: defaultTextStyle.fontFamilyFallback,
        ),
      )
      ..addText('${pageIndex + 1} / $totalPages');

    final paragraph = builder.build();
    paragraph.layout(
      ui.ParagraphConstraints(
        width: pageSize.width - 2 * _pageIndicatorPadding,
      ),
    );

    canvas.drawParagraph(
      paragraph,
      Offset(
        _pageIndicatorPadding,
        pageSize.height - _pageIndicatorPadding - _pageIndicatorFontSize * 1.2,
      ),
    );
  }

  static MaskFilter _getPencilMaskFilter(double size) =>
      MaskFilter.blur(BlurStyle.normal, min(size * 0.2, 3));
  bool shouldUsePencilShader(double strokeSize) =>
      currentScale >= _zoomThreshold && (strokeSize * currentScale) >= 3;

  static const _zoomThreshold = 0.9;
  Path _selectPath(Stroke stroke) => switch (currentScale) {
    < _zoomThreshold => stroke.lowQualityPath,
    _ => stroke.highQualityPath,
  };
}
