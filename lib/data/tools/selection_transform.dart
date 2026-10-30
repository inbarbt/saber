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

  /// Middle of a side: stretches the selection in one direction only.
  top,
  bottom,
  left,
  right,

  rotate;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;

  bool get isEdge =>
      this == top || this == bottom || this == left || this == right;
}

/// The box around a selection. It turns with the selection:
/// [local] is the box in a frame rotated by [angle] (radians,
/// clockwise on screen) around the page origin.
@immutable
class SelectionBox {
  const new(this.local, this.angle);

  final Rect local;
  final double angle;

  /// A point in the box's frame, in page coordinates.
  Offset toPage(Offset localPoint) => _rotate(localPoint, angle);

  /// A page point, in the box's frame.
  Offset toLocal(Offset pagePoint) => _rotate(pagePoint, -angle);

  Offset get center => toPage(local.center);

  /// The corners in drawing order, in page coordinates.
  List<Offset> get corners => [
    toPage(local.topLeft),
    toPage(local.topRight),
    toPage(local.bottomRight),
    toPage(local.bottomLeft),
  ];

  bool contains(Offset pagePoint) => local.contains(toLocal(pagePoint));

  static Offset _rotate(Offset p, double angle) {
    if (angle == 0) return p;
    final c = cos(angle), s = sin(angle);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }
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

  /// The box around the selected content, turned by [angle] radians.
  /// Returns null if nothing with a size is selected.
  static SelectionBox? contentBox(
    List<Stroke> strokes,
    List<EditorImage> images, {
    double angle = 0,
  }) {
    final points = <Offset>[
      for (final stroke in strokes)
        ...stroke.lowQualityPolygon.where((p) => p.isFinite),
      for (final image in images) ...[
        image.dstRect.topLeft,
        image.dstRect.topRight,
        image.dstRect.bottomLeft,
        image.dstRect.bottomRight,
      ],
    ];
    if (points.isEmpty) return null;

    final frame = SelectionBox(Rect.zero, angle);
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final point in points) {
      final p = frame.toLocal(point);
      minX = min(minX, p.dx);
      minY = min(minY, p.dy);
      maxX = max(maxX, p.dx);
      maxY = max(maxY, p.dy);
    }
    return SelectionBox(Rect.fromLTRB(minX, minY, maxX, maxY), angle);
  }

  /// Where each handle sits, in page coordinates.
  /// [scale] is the current zoom, so handles keep a constant screen size.
  static Map<SelectionHandle, Offset> handlePositions(
    SelectionBox box,
    double scale,
  ) {
    final r = box.local;
    return {
      .topLeft: box.toPage(r.topLeft),
      .topRight: box.toPage(r.topRight),
      .bottomLeft: box.toPage(r.bottomLeft),
      .bottomRight: box.toPage(r.bottomRight),
      .top: box.toPage(r.topCenter),
      .bottom: box.toPage(r.bottomCenter),
      .left: box.toPage(r.centerLeft),
      .right: box.toPage(r.centerRight),
      .rotate: box.toPage(r.topCenter - Offset(0, rotateHandleOffset / scale)),
    };
  }

  /// The handle under [position], if any. The rotate handle wins ties.
  static SelectionHandle? hitTest(
    Offset position,
    SelectionBox box,
    double scale,
  ) {
    final hitRadius = handleHitRadius / scale;
    SelectionHandle? best;
    var bestDistance = double.infinity;
    for (final MapEntry(key: handle, value: center) in handlePositions(
      box,
      scale,
    ).entries) {
      final distance = (position - center).distance;
      if (distance > hitRadius) continue;
      if (handle == .rotate) return handle;
      if (distance < bestDistance) {
        best = handle;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The corner opposite [handle] (in the box's frame):
  /// it stays fixed while resizing.
  static Offset anchorFor(SelectionHandle handle, Rect r) => switch (handle) {
    .topLeft => r.bottomRight,
    .topRight => r.bottomLeft,
    .bottomLeft => r.topRight,
    .bottomRight => r.topLeft,
    .top => r.bottomCenter,
    .bottom => r.topCenter,
    .left => r.centerRight,
    .right => r.centerLeft,
    .rotate => r.center,
  };

  static Offset _cornerFor(SelectionHandle handle, Rect r) => switch (handle) {
    .topLeft => r.topLeft,
    .topRight => r.topRight,
    .bottomLeft => r.bottomLeft,
    .bottomRight => r.bottomRight,
    .top => r.topCenter,
    .bottom => r.bottomCenter,
    .left => r.centerLeft,
    .right => r.centerRight,
    .rotate => r.topCenter,
  };

  /// The scale factors (along the box's own axes) for dragging a corner
  /// [handle] of [box] to [pointer].
  static (double sx, double sy) resizeFactors(
    SelectionBox box,
    SelectionHandle handle,
    Offset pointer, {
    required bool keepAspectRatio,
  }) {
    assert(handle != .rotate);
    final r = box.local;
    final anchor = anchorFor(handle, r);
    final corner = _cornerFor(handle, r);
    final local = box.toLocal(pointer);

    double factor(double pointer, double anchor, double corner) {
      final span = corner - anchor;
      // A zero-width or zero-height selection (e.g. a straight line)
      // can't be stretched along that axis.
      if (span.abs() < 1e-6) return 1;
      return max(minScale, (pointer - anchor) / span);
    }

    var sx = factor(local.dx, anchor.dx, corner.dx);
    var sy = factor(local.dy, anchor.dy, corner.dy);

    // Side handles stretch one direction and ignore the aspect ratio.
    if (handle == .top || handle == .bottom) return (1, sy);
    if (handle == .left || handle == .right) return (sx, 1);

    final hasWidth = r.width.abs() > 1e-6;
    final hasHeight = r.height.abs() > 1e-6;
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

  /// The matrix for dragging a corner [handle] of [box] to [pointer].
  static Matrix4 resizeMatrix(
    SelectionBox box,
    SelectionHandle handle,
    Offset pointer, {
    required bool keepAspectRatio,
  }) {
    final (sx, sy) = resizeFactors(
      box,
      handle,
      pointer,
      keepAspectRatio: keepAspectRatio,
    );
    final anchor = anchorFor(handle, box.local);
    return Matrix4.identity()
      ..rotateZ(box.angle)
      ..translateByDouble(anchor.dx, anchor.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1)
      ..rotateZ(-box.angle);
  }

  /// The rotation (degrees, clockwise on screen) from dragging the rotate
  /// handle from [startPointer] to [pointer] around [center].
  ///
  /// [startAngle] is how far the box is already turned (degrees).
  /// Snapping is to absolute multiples of [snapStep], so a turned box
  /// can be put back to exactly 0°.
  static double rotationDegrees(
    Offset center,
    Offset startPointer,
    Offset pointer, {
    double startAngle = 0,
  }) {
    final start = (startPointer - center).direction;
    final now = (pointer - center).direction;
    final delta = (now - start) * 180 / pi;
    final total = normalizeDegrees(startAngle + delta);

    var snapped = total;
    final nearest = (total / snapStep).roundToDouble() * snapStep;
    if ((total - nearest).abs() <= snapTolerance) snapped = nearest;
    return normalizeDegrees(snapped - startAngle);
  }

  /// [degrees] in the range (-180, 180], without "-0".
  static double normalizeDegrees(double degrees) {
    var d = (degrees + 180) % 360 - 180;
    if (d == -180) d = 180;
    if (d == 0) d = 0;
    return d;
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
  /// Images stay upright: under rotation only their centre moves, and
  /// under a turned resize they scale evenly.
  static Rect transformImageRect(Rect rect, Matrix4 m) {
    if (isAxisAligned(m)) return MatrixUtils.transformRect(m, rect);
    final center = MatrixUtils.transformPoint(m, rect.center);
    final scale = lengthScale(m);
    return Rect.fromCenter(
      center: center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
  }
}
