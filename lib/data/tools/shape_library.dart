import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Shapes the shape pen can draw directly, by dragging a box.
/// [auto] recognises whatever was drawn instead.
enum LibraryShape {
  auto,
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
  rightTriangle,
  rhombus,
  parallelogram,
  trapezoid,
  polygon,
  star,
  graph;

  static LibraryShape fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => auto);
}

/// Builds library shapes inside a box.
abstract final class ShapeLibrary {
  static const minCorners = 3;
  static const maxCorners = 12;

  /// The outline of [shape] in the box from [start] to [end] (where the
  /// drag began and ended). Closed shapes repeat their first point.
  /// [corners] is used by [LibraryShape.polygon].
  static List<Offset> outline(
    LibraryShape shape,
    Offset start,
    Offset end, {
    int corners = 6,
  }) {
    final r = Rect.fromPoints(start, end);
    List<Offset> closed(List<Offset> points) => [...points, points.first];

    switch (shape) {
      case .auto:
        return const [];
      case .line:
      case .arrow:
        // Lines follow the drag, so they can point any way.
        return [start, end];
      case .rectangle:
        return closed([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
      case .ellipse:
        final r = circleSnap(start, end);
        const segments = 72;
        return [
          for (int i = 0; i <= segments; i++)
            Offset(
              r.center.dx + r.width / 2 * cos(2 * pi * i / segments),
              r.center.dy + r.height / 2 * sin(2 * pi * i / segments),
            ),
        ];
      case .triangle:
        return closed([r.bottomLeft, r.topCenter, r.bottomRight]);
      case .rightTriangle:
        return closed([r.topLeft, r.bottomLeft, r.bottomRight]);
      case .rhombus:
        return closed([
          r.topCenter,
          r.centerRight,
          r.bottomCenter,
          r.centerLeft,
        ]);
      case .parallelogram:
        final shift = r.width / 4;
        return closed([
          r.topLeft + Offset(shift, 0),
          r.topRight,
          r.bottomRight - Offset(shift, 0),
          r.bottomLeft,
        ]);
      case .trapezoid:
        final inset = r.width / 4;
        return closed([
          r.topLeft + Offset(inset, 0),
          r.topRight - Offset(inset, 0),
          r.bottomRight,
          r.bottomLeft,
        ]);
      case .polygon:
        final n = corners.clamp(minCorners, maxCorners);
        return closed([
          for (int i = 0; i < n; i++)
            Offset(
              r.center.dx + r.width / 2 * cos(-pi / 2 + 2 * pi * i / n),
              r.center.dy + r.height / 2 * sin(-pi / 2 + 2 * pi * i / n),
            ),
        ]);
      case .graph:
        // Previewed as its frame; the graph itself is a GraphStroke.
        return closed([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]);
      case .star:
        return closed([
          for (int i = 0; i < 10; i++)
            Offset(
              r.center.dx +
                  r.width /
                      2 *
                      (i.isEven ? 1 : 0.4) *
                      cos(-pi / 2 + pi * i / 5),
              r.center.dy +
                  r.height /
                      2 *
                      (i.isEven ? 1 : 0.4) *
                      sin(-pi / 2 + pi * i / 5),
            ),
        ]);
    }
  }

  /// An ellipse's width and height snap together, to a perfect circle,
  /// when they are within this fraction of each other.
  static const circleSnapTolerance = 0.06;

  /// The box from [start] to [end], made square when it is nearly
  /// square, so a drawn ellipse snaps to a perfect circle.
  static Rect circleSnap(Offset start, Offset end) {
    final w = (end.dx - start.dx).abs();
    final h = (end.dy - start.dy).abs();
    if (w <= 0 || h <= 0 || (w / h - 1).abs() > circleSnapTolerance) {
      return Rect.fromPoints(start, end);
    }
    final side = (w + h) / 2;
    return Rect.fromPoints(
      start,
      start +
          Offset(
            end.dx >= start.dx ? side : -side,
            end.dy >= start.dy ? side : -side,
          ),
    );
  }

  /// Replaces the shape pen's drag [rawStroke] with [shape], drawn in the
  /// box from the stroke's first point to its last.
  static Stroke strokeFor(
    Stroke rawStroke,
    LibraryShape shape, {
    int corners = 6,
  }) {
    final line = rawStroke.centerline;
    final points = outline(shape, line.first, line.last, corners: corners);
    if (points.length < 2) return rawStroke;
    return Stroke(
        color: rawStroke.color,
        pressureEnabled: false,
        options: rawStroke.options.copyWith(
          smoothing: 0,
          streamline: 0,
          simulatePressure: false,
          isComplete: true,
        ),
        pageIndex: rawStroke.pageIndex,
        page: rawStroke.page,
        toolId: rawStroke.toolId,
      )
      ..addPoints(points)
      ..crisp = true
      ..arrowEnd = shape == .arrow
      ..libraryKind = shape;
  }
}
