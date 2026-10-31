import 'dart:math';

import 'package:flutter/widgets.dart';

/// Plane geometry used by the shape and gesture tools.
abstract final class ShapeGeometry {
  /// A recognised rectangle closer than this to upright (degrees)
  /// is drawn upright.
  static const uprightToleranceDegrees = 7.0;

  /// The convex hull of [points] (Andrew's monotone chain),
  /// counter-clockwise on screen.
  static List<Offset> convexHull(List<Offset> points) {
    final sorted = [...points]
      ..sort(
        (a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy),
      );
    if (sorted.length < 3) return sorted;

    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    return [...lower..removeLast(), ...upper..removeLast()];
  }

  /// The smallest-area rectangle around [points], which may be turned.
  /// Returns its four corners in order, or an empty list if there are
  /// too few points.
  static List<Offset> minAreaRect(List<Offset> points) {
    final hull = convexHull(points);
    if (hull.length < 3) return const [];

    var bestArea = double.infinity;
    var bestAngle = 0.0;
    var best = Rect.zero;
    for (int i = 0; i < hull.length; i++) {
      final a = hull[i], b = hull[(i + 1) % hull.length];
      final angle = (b - a).direction;
      final c = cos(-angle), s = sin(-angle);
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      for (final p in hull) {
        final x = p.dx * c - p.dy * s, y = p.dx * s + p.dy * c;
        minX = min(minX, x);
        minY = min(minY, y);
        maxX = max(maxX, x);
        maxY = max(maxY, y);
      }
      final area = (maxX - minX) * (maxY - minY);
      if (area < bestArea) {
        bestArea = area;
        bestAngle = angle;
        best = Rect.fromLTRB(minX, minY, maxX, maxY);
      }
    }

    final c = cos(bestAngle), s = sin(bestAngle);
    Offset back(Offset p) => Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
    return [
      back(best.topLeft),
      back(best.topRight),
      back(best.bottomRight),
      back(best.bottomLeft),
    ];
  }

  /// How far a rectangle with these [corners] is turned from upright,
  /// in degrees, in the range (-45, 45].
  static double rectTurnDegrees(List<Offset> corners) {
    final degrees = (corners[1] - corners[0]).direction * 180 / pi;
    var d = degrees % 90;
    if (d > 45) d -= 90;
    return d;
  }

  /// The two lines of an arrowhead at the end of [line], for a stroke
  /// [strokeSize] thick. Null if the line has no direction.
  static List<(Offset, Offset)>? arrowhead(
    List<Offset> line,
    double strokeSize,
  ) {
    if (line.length < 2) return null;
    final tip = line.last;
    final reach = max(strokeSize * 3, 6.0);
    // Look back far enough that the pen's wobble doesn't set the direction.
    var from = line.first;
    for (int i = line.length - 2; i >= 0; i--) {
      if ((line[i] - tip).distance >= reach) {
        from = line[i];
        break;
      }
    }
    if (from == tip) return null;
    final direction = (tip - from).direction;
    final length = max(12.0, strokeSize * 4);
    const spread = 2.6; // radians back from the direction, about 150°
    return [
      (tip, tip + Offset.fromDirection(direction + spread, length)),
      (tip, tip + Offset.fromDirection(direction - spread, length)),
    ];
  }

  /// Shortest distance from [p] to the polyline through [points].
  static double distanceToPolyline(Offset p, List<Offset> points) {
    if (points.isEmpty) return double.infinity;
    if (points.length == 1) return (p - points.first).distance;
    var best = double.infinity;
    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final ab = b - a;
      final lengthSquared = ab.distanceSquared;
      final double distance;
      if (lengthSquared == 0) {
        distance = (p - a).distance;
      } else {
        final ap = p - a;
        final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(
          0.0,
          1.0,
        );
        distance = (p - (a + ab * t)).distance;
      }
      best = min(best, distance);
    }
    return best;
  }

  /// Whether a rectangle with these [corners] is close enough to upright.
  static bool isUpright(List<Offset> corners) =>
      rectTurnDegrees(corners).abs() < uprightToleranceDegrees;
}
