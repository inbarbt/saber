import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/shape_geometry.dart';

/// "Circle to lasso": draw a loop around something with the pen,
/// lift the pen, then press and hold on the loop. The loop turns into
/// a lasso selection of what's inside it.
///
/// A loop that was turned into a shape (circle, rectangle) no longer
/// counts, the same as in Notewise.
abstract final class CircleToLasso {
  /// How long to hold the pen on the loop.
  static const holdDuration = Duration(milliseconds: 700);

  /// How far the pen may wander during the hold, in screen pixels.
  static const moveTolerance = 10.0;

  /// How close to the loop the press must be, in screen pixels,
  /// on top of the stroke's own thickness.
  static const touchTolerance = 16.0;

  /// Loops smaller than this (page units, bounding box diagonal) are
  /// more likely letters like "o" than a lasso.
  static const minLoopDiagonal = 40.0;

  /// The loop counts as closed if its ends are within this fraction
  /// of its size (or [minGap], whichever is larger).
  static const closedGapFraction = 0.25;
  static const minGap = 20.0;

  /// Whether [stroke] is a hand-drawn closed loop.
  static bool isLoop(Stroke stroke) {
    if (stroke is RectangleStroke || stroke is CircleStroke) return false;
    final points = stroke.centerline;
    if (points.length < 8) return false;

    final bounds = _boundsOf(points);
    final diagonal = bounds.size.longestSide * sqrt2;
    if (bounds.width < minLoopDiagonal / 4 ||
        bounds.height < minLoopDiagonal / 4) {
      return false;
    }
    if (diagonal < minLoopDiagonal) return false;

    final gap = (points.first - points.last).distance;
    return gap <= max(minGap, closedGapFraction * diagonal);
  }

  /// The loop whose outline is under [position], if any.
  /// [scale] is the current zoom level.
  static Stroke? loopAt(Offset position, List<Stroke> strokes, double scale) {
    Stroke? best;
    var bestDistance = double.infinity;
    for (final stroke in strokes) {
      if (!isLoop(stroke)) continue;
      final tolerance = touchTolerance / scale + stroke.options.size;
      final distance = distanceToPolyline(position, stroke.centerline);
      if (distance <= tolerance && distance < bestDistance) {
        best = stroke;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// The selection area enclosed by [loop].
  static Path lassoPath(Stroke loop) {
    return Path()
      ..addPolygon(loop.centerline, true)
      ..close();
  }

  /// Shortest distance from [p] to the polyline through [points].
  static double distanceToPolyline(Offset p, List<Offset> points) =>
      ShapeGeometry.distanceToPolyline(p, points);

  static Rect _boundsOf(List<Offset> points) {
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
}
