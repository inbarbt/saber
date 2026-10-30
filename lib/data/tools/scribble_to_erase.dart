import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/shape_geometry.dart';

/// "Scribble to erase": scribble back and forth over something with the
/// pen, and it is erased together with the scribble.
abstract final class ScribbleToErase {
  /// The pen must change direction at least this many times.
  static const minReversals = 5;

  /// Back-and-forth movements shorter than this fraction of the scribble's
  /// length are treated as jitter, not as a change of direction.
  static const reversalHysteresis = 0.2;

  /// The pen travels at least this many times the scribble's length.
  static const minPathToLengthRatio = 4.0;

  /// Scribbles shorter than this (page units) are more likely writing.
  static const minLength = 20.0;

  /// A stroke is erased if at least this fraction of it lies under the
  /// scribble.
  static const minCoveredFraction = 0.5;

  /// Whether the pen path [points] looks like a scribble.
  static bool isScribble(List<Offset> points) {
    if (points.length < 15) return false;

    final axis = _principalAxis(points);
    final projections = [
      for (final p in points) p.dx * axis.dx + p.dy * axis.dy,
    ];
    final lowest = projections.reduce(min);
    final highest = projections.reduce(max);
    final length = highest - lowest;
    if (length < minLength) return false;

    var pathLength = 0.0;
    for (int i = 1; i < points.length; i++) {
      pathLength += (points[i] - points[i - 1]).distance;
    }
    if (pathLength < minPathToLengthRatio * length) return false;

    return countReversals(projections, length * reversalHysteresis) >=
        minReversals;
  }

  /// Counts direction changes in [values], ignoring wiggles smaller
  /// than [threshold].
  static int countReversals(List<double> values, double threshold) {
    var reversals = 0;
    var direction = 0; // 1 increasing, -1 decreasing
    var extreme = values.first;
    for (final value in values.skip(1)) {
      if (direction >= 0) {
        if (value > extreme) {
          extreme = value;
          direction = 1;
        } else if (extreme - value > threshold) {
          if (direction == 1) reversals++;
          direction = -1;
          extreme = value;
        }
      } else {
        if (value < extreme) {
          extreme = value;
        } else if (value - extreme > threshold) {
          reversals++;
          direction = 1;
          extreme = value;
        }
      }
    }
    return reversals;
  }

  /// The strokes in [strokes] that [scribble] covers.
  static List<Stroke> strokesUnder(Stroke scribble, List<Stroke> strokes) {
    final hull = Path()..addPolygon(convexHull(scribble.centerline), true);
    return [
      for (final stroke in strokes)
        if (!identical(stroke, scribble) && _covered(stroke, hull)) stroke,
    ];
  }

  static bool _covered(Stroke stroke, Path hull) {
    final points = stroke.lowQualityPolygon.where((p) => p.isFinite).toList();
    if (points.isEmpty) return false;
    final inside = points.where(hull.contains).length;
    return inside / points.length >= minCoveredFraction;
  }

  /// The direction along which [points] spread the most.
  static Offset _principalAxis(List<Offset> points) {
    var meanX = 0.0, meanY = 0.0;
    for (final p in points) {
      meanX += p.dx;
      meanY += p.dy;
    }
    meanX /= points.length;
    meanY /= points.length;

    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in points) {
      final dx = p.dx - meanX, dy = p.dy - meanY;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    final angle = 0.5 * atan2(2 * sxy, sxx - syy);
    return Offset(cos(angle), sin(angle));
  }

  /// The convex hull of [points]. See [ShapeGeometry.convexHull].
  static List<Offset> convexHull(List<Offset> points) =>
      ShapeGeometry.convexHull(points);
}
