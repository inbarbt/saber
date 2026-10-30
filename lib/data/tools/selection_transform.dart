import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';

/// A handle on the box around a selection.
enum SelectionHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  rotate;

  bool get isCorner => this != rotate;
}

/// Geometry for resizing and rotating a selection with handles.
///
/// Everything here is pure math on page coordinates, so it can be tested
/// without a running editor.
abstract final class SelectionTransform {
  /// Whether corner handles keep the selection's aspect ratio.
  /// Shared for the whole app session.
  static var keepAspectRatio = true;

  /// Handle radius and hit area, in screen pixels.
  static const handleRadius = 9.0;
  static const handleHitRadius = 28.0;

  /// Distance of the rotate handle above the box, in screen pixels.
  static const rotateHandleOffset = 40.0;

  /// Rotation snaps to multiples of this angle (degrees)
  /// when it is within [snapTolerance] of one.
  static const snapStep = 15.0;
  static const snapTolerance = 3.0;

  /// Selections can't be scaled below this factor in one gesture,
  /// so they never collapse to nothing or flip inside out.
  static const minScale = 0.05;

  /// The axis-aligned box around the selected content.
  /// Returns null if nothing with a size is selected.
  static Rect? contentBounds(List<Stroke> strokes, List<EditorImage> images) {
    Rect? bounds;
    for (final stroke in strokes) {
      final polygon = stroke.lowQualityPolygon.where((p) => p.isFinite);
      if (polygon.isEmpty) continue;
      final rect = _boundsOf(polygon);
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }
    for (final image in images) {
      bounds = bounds?.expandToInclude(image.dstRect) ?? image.dstRect;
    }
    return bounds;
  }

  static Rect _boundsOf(Iterable<Offset> points) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx);
      maxY = max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Where each handle sits, in page coordinates.
  /// [scale] is the current zoom, so handles keep a constant screen size.
  static Map<SelectionHandle, Offset> handlePositions(
    Rect bounds,
    double scale,
  ) => {
    .topLeft: bounds.topLeft,
    .topRight: bounds.topRight,
    .bottomLeft: bounds.bottomLeft,
    .bottomRight: bounds.bottomRight,
    .rotate: bounds.topCenter - Offset(0, rotateHandleOffset / scale),
  };

  /// The handle under [position], if any. The rotate handle wins ties.
  static SelectionHandle? hitTest(Offset position, Rect bounds, double scale) {
    final hitRadius = handleHitRadius / scale;
    SelectionHandle? best;
    var bestDistance = double.infinity;
    for (final MapEntry(key: handle, value: center) in handlePositions(
      bounds,
      scale,
    ).entries) {
      final distance = (position - center).distance;
      if (distance > hitRadius) continue;
      if (handle == .rotate || distance < bestDistance) {
        best = handle;
        bestDistance = handle == .rotate ? -1 : distance;
      }
    }
    return best;
  }

  /// The corner opposite [handle]: it stays fixed while resizing.
  static Offset anchorFor(SelectionHandle handle, Rect bounds) =>
      switch (handle) {
        .topLeft => bounds.bottomRight,
        .topRight => bounds.bottomLeft,
        .bottomLeft => bounds.topRight,
        .bottomRight => bounds.topLeft,
        .rotate => bounds.center,
      };

  static Offset _cornerFor(SelectionHandle handle, Rect bounds) =>
      switch (handle) {
        .topLeft => bounds.topLeft,
        .topRight => bounds.topRight,
        .bottomLeft => bounds.bottomLeft,
        .bottomRight => bounds.bottomRight,
        .rotate => bounds.topCenter,
      };

  /// The scale factors for dragging a corner [handle] of [startBounds]
  /// to [pointer].
  static (double sx, double sy) resizeFactors(
    Rect startBounds,
    SelectionHandle handle,
    Offset pointer, {
    required bool keepAspectRatio,
  }) {
    assert(handle.isCorner);
    final anchor = anchorFor(handle, startBounds);
    final corner = _cornerFor(handle, startBounds);

    double factor(double pointer, double anchor, double corner) {
      final span = corner - anchor;
      // A zero-width or zero-height selection (e.g. a straight line)
      // can't be stretched along that axis.
      if (span.abs() < 1e-6) return 1;
      return max(minScale, (pointer - anchor) / span);
    }

    var sx = factor(pointer.dx, anchor.dx, corner.dx);
    var sy = factor(pointer.dy, anchor.dy, corner.dy);

    final hasWidth = startBounds.width.abs() > 1e-6;
    final hasHeight = startBounds.height.abs() > 1e-6;
    if (keepAspectRatio && hasWidth && hasHeight) {
      final s = max(sx, sy);
      sx = s;
      sy = s;
    } else if (keepAspectRatio && hasWidth != hasHeight) {
      // A line only has one real axis: scale both by it.
      final s = hasWidth ? sx : sy;
      sx = s;
      sy = s;
    }
    return (sx, sy);
  }

  /// The matrix for dragging a corner [handle] of [startBounds] to [pointer].
  static Matrix4 resizeMatrix(
    Rect startBounds,
    SelectionHandle handle,
    Offset pointer, {
    required bool keepAspectRatio,
  }) {
    final (sx, sy) = resizeFactors(
      startBounds,
      handle,
      pointer,
      keepAspectRatio: keepAspectRatio,
    );
    final anchor = anchorFor(handle, startBounds);
    return Matrix4.identity()
      ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
  }

  /// The rotation (degrees, clockwise on screen) from dragging the rotate
  /// handle from [startPointer] to [pointer] around [center].
  /// Snaps to multiples of [snapStep] when close.
  static double rotationDegrees(
    Offset center,
    Offset startPointer,
    Offset pointer,
  ) {
    final start = (startPointer - center).direction;
    final now = (pointer - center).direction;
    var degrees = (now - start) * 180 / pi;
    // Normalise to (-180, 180]
    degrees = (degrees + 180) % 360 - 180;
    if (degrees == -180) degrees = 180;

    final nearest = (degrees / snapStep).roundToDouble() * snapStep;
    if ((degrees - nearest).abs() <= snapTolerance) degrees = nearest;
    // Avoid showing "-0°"
    if (degrees == 0) degrees = 0;
    return degrees;
  }

  static Matrix4 rotateMatrix(Offset center, double degrees) {
    return Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(degrees * pi / 180)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  /// Whether [m] only scales and translates (no rotation or skew).
  static bool isAxisAligned(Matrix4 m) =>
      m.entry(0, 1).abs() < 1e-9 && m.entry(1, 0).abs() < 1e-9;

  /// How much [m] scales areas, as a single length factor.
  /// Used to scale stroke thickness.
  static double lengthScale(Matrix4 m) {
    final det = m.entry(0, 0) * m.entry(1, 1) - m.entry(0, 1) * m.entry(1, 0);
    return sqrt(det.abs());
  }

  /// Applies [m] to an image's rectangle.
  ///
  /// Images can't be rotated, so under rotation only their centre moves.
  static Rect transformImageRect(Rect rect, Matrix4 m) {
    if (isAxisAligned(m)) return MatrixUtils.transformRect(m, rect);
    final center = MatrixUtils.transformPoint(m, rect.center);
    return Rect.fromCenter(
      center: center,
      width: rect.width,
      height: rect.height,
    );
  }
}
