import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:saber/i18n/strings.g.dart';

class ShapePen extends Pen {
  new()
    : super(
        name: t.editor.pens.shapePen,
        sizeMin: 1,
        sizeMax: 25,
        sizeStep: 1,
        icon: shapePenIcon,
        options: stows.lastShapePenOptions.value,
        pressureEnabled: false,
        color: Color(stows.lastShapePenColor.value),
        toolId: .shapePen,
      );

  static final log = Logger('ShapePen');

  static const shapePenIcon = FontAwesomeIcons.shapes;

  static RecognizedUnistroke? detectedShape;

  /// The library shape chosen in the shape pen panel, or [LibraryShape.auto]
  /// to recognise what's drawn.
  static LibraryShape get libraryShape =>
      LibraryShape.fromName(stows.shapeKind.value);

  /// Outline of the library shape being dragged out, for the preview.
  static List<Offset>? libraryPreview;
  void _detectShape() {
    detectedShape = Pen.currentStroke?.detectShape();
  }

  static Timer? _detectShapeDebouncer;
  static var debounceDuration = getDebounceFromPref();
  static Duration getDebounceFromPref() {
    assert(stows.shapeRecognitionDelay.loaded);
    final ms = stows.shapeRecognitionDelay.value;
    if (ms < 0) {
      return const Duration(hours: 1);
    } else {
      return Duration(milliseconds: ms);
    }
  }

  @override
  void onDragUpdate(Offset position, double? pressure) {
    super.onDragUpdate(position, pressure);

    final library = libraryShape;
    if (library != .auto) {
      final line = Pen.currentStroke?.centerline ?? const [];
      libraryPreview = line.isEmpty
          ? null
          : ShapeLibrary.outline(
              library,
              line.first,
              position,
              corners: stows.shapeCorners.value,
            );
      return;
    }

    final isPreviewEnabled = debounceDuration < const Duration(hours: 1);
    final isTimerActive = _detectShapeDebouncer?.isActive ?? false;
    if (isPreviewEnabled && !isTimerActive) {
      _detectShapeDebouncer = Timer(debounceDuration, _detectShape);
    }
  }

  @override
  Stroke? onDragEnd() {
    _detectShapeDebouncer?.cancel();
    _detectShapeDebouncer = null;
    libraryPreview = null;

    final library = libraryShape;
    if (library != .auto) {
      ShapePen.detectedShape = null;
      final rawStroke = super.onDragEnd();
      if (rawStroke == null) return null;
      final shape = ShapeLibrary.strokeFor(
        rawStroke,
        library,
        corners: stows.shapeCorners.value,
      );
      return applyShapeStyle(
        shape,
        isLine: library == .line || library == .arrow,
      );
    }

    _detectShape();

    final rawStroke = super.onDragEnd();
    if (rawStroke == null) return null;
    assert(rawStroke.options.isComplete == true);

    final detectedShape = ShapePen.detectedShape;
    ShapePen.detectedShape = null;

    final result = detectedShape == null
        ? rawStroke
        : strokeToShape(rawStroke, detectedShape);
    return applyShapeStyle(
      result,
      isLine: detectedShape?.name == DefaultUnistrokeNames.line,
    );
  }

  /// How translucent a shape's fill is (0 to 255).
  static const fillAlpha = 0x40;

  /// Applies the shape pen's style settings to a new [shape].
  static Stroke applyShapeStyle(Stroke shape, {required bool isLine}) {
    shape.dashed = stows.shapeDashed.value;
    if (stows.shapeFilled.value && !isLine) {
      shape.fillColor = shape.color.withAlpha(fillAlpha);
    }
    if (stows.shapeArrow.value && isLine) shape.arrowEnd = true;
    return shape;
  }

  /// Replaces a hand-drawn [rawStroke] with the shape it was recognised as.
  ///
  /// Used by the shape pen, and by the other pens when the pen is held
  /// still at the end of a stroke.
  static Stroke strokeToShape(Stroke rawStroke, RecognizedUnistroke detected) {
    final shapeOptions = rawStroke.options.copyWith(
      smoothing: 0,
      streamline: 0,
      simulatePressure: false,
      isComplete: true,
    );
    Stroke polygon(List<Offset> points) =>
        Stroke(
            color: rawStroke.color,
            pressureEnabled: false,
            options: shapeOptions,
            pageIndex: rawStroke.pageIndex,
            page: rawStroke.page,
            toolId: rawStroke.toolId,
          )
          ..addPoints(points)
          ..crisp = true;

    switch (detected.name) {
      case null:
        log.info('Detected unknown shape');
        return rawStroke;
      case DefaultUnistrokeNames.line:
        log.info('Detected line');
        return rawStroke
          ..convertToLine()
          ..crisp = true;
      case DefaultUnistrokeNames.rectangle:
        // Keep the angle the rectangle was drawn at,
        // unless it's nearly upright.
        final corners = ShapeGeometry.minAreaRect(rawStroke.centerline);
        if (corners.isNotEmpty && !ShapeGeometry.isUpright(corners)) {
          log.info('Detected turned rectangle');
          return polygon([...corners, corners.first]);
        }
        final rect = detected.convertToRect();
        log.info('Detected rectangle: $rect');
        return RectangleStroke(
          color: rawStroke.color,
          pressureEnabled: false,
          options: shapeOptions,
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          rect: rect,
        );
      case DefaultUnistrokeNames.circle:
        final (center, radius) = detected.convertToCircle();
        log.info('Detected circle: c=$center, r=$radius');
        return CircleStroke(
          color: rawStroke.color,
          pressureEnabled: false,
          options: shapeOptions,
          pageIndex: rawStroke.pageIndex,
          page: rawStroke.page,
          toolId: rawStroke.toolId,
          radius: radius,
          center: center,
        );
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        log.info('Detected ${detected.name}');
        final corners = detected.convertToCanonicalPolygon();
        // Make sure the outline closes, so the last side is drawn.
        if (corners.length >= 3 &&
            (corners.first - corners.last).distance > 0.5) {
          corners.add(corners.first);
        }
        return polygon(corners);
    }
  }
}
