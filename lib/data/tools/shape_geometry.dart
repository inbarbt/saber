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

  /// Whether a rectangle with these [corners] is close enough to upright.
  static bool isUpright(List<Offset> corners) =>
      rectTurnDegrees(corners).abs() < uprightToleranceDegrees;
}
