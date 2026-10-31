import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/tools/shape_library.dart';

/// Something drawn while snapping, to show what snapped to what.
sealed class SnapGuide {
  const new();
}

/// A point that was snapped onto, drawn as a ring.
class const SnapPointGuide(final Offset at) extends SnapGuide;

/// A dashed line, e.g. two centres lined up, or a gap between shapes.
class const SnapLineGuide(final Offset from, final Offset to) extends SnapGuide;

/// The parts of shapes that other shapes snap to.
class SnapFeatures {
  new();

  /// Corners, ends of lines and middles of sides.
  final points = <Offset>[];

  /// Centres of shapes. Their vertical and horizontal lines are the
  /// symmetry lines of upright shapes.
  final centers = <Offset>[];

  /// Straight sides and lines.
  final segments = <(Offset, Offset)>[];

  /// Circles (and nearly round ellipses).
  final circles = <({Offset center, double radius})>[];

  /// Bounding boxes, for lining up edges and spacing.
  final boxes = <Rect>[];

  bool get isEmpty =>
      points.isEmpty && centers.isEmpty && segments.isEmpty && boxes.isEmpty;

  /// Features of the shapes among [strokes] (handwriting is left out:
  /// snapping to it would get in the way), and of [images].
  factory of(Iterable<Stroke> strokes, [Iterable<Rect>? images]) {
    final f = SnapFeatures();
    for (final stroke in strokes) {
      f._add(stroke);
    }
    for (final rect in images ?? const <Rect>[]) {
      f.boxes.add(rect);
      f.centers.add(rect.center);
      f.points.addAll([
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ]);
    }
    return f;
  }

  void _add(Stroke stroke) {
    if (stroke is CircleStroke) {
      circles.add((center: stroke.center, radius: stroke.radius));
      centers.add(stroke.center);
      boxes.add(Rect.fromCircle(center: stroke.center, radius: stroke.radius));
      return;
    }
    if (stroke is GraphStroke) {
      final frame = stroke.frame;
      boxes.add(frame);
      centers.add(frame.center);
      return;
    }
    if (!stroke.isShape && stroke is! RectangleStroke) return;

    final outline = stroke.erasablePoints.map((p) => Offset(p.x, p.y)).toList();
    if (outline.isEmpty) return;
    final box = _bounds(outline);
    boxes.add(box);

    if (stroke.libraryKind == LibraryShape.ellipse) {
      centers.add(box.center);
      if ((box.width / max(box.height, 1e-6) - 1).abs() < 0.02) {
        circles.add((center: box.center, radius: box.width / 2));
      }
      return;
    }

    final corners = stroke.vertices;
    if (corners.isEmpty) return;
    final closed = corners.length >= 3;
    points.addAll(corners);
    for (int i = 0; i < corners.length; i++) {
      if (!closed && i == corners.length - 1) break;
      final a = corners[i], b = corners[(i + 1) % corners.length];
      segments.add((a, b));
      points.add((a + b) / 2);
    }
    if (closed) {
      var sum = Offset.zero;
      for (final c in corners) {
        sum += c;
      }
      centers.add(sum / corners.length.toDouble());
    } else {
      // A line's centre is its middle, already a point.
    }
  }

  /// These features moved by [offset].
  SnapFeatures shifted(Offset offset) {
    final f = SnapFeatures();
    f.points.addAll(points.map((p) => p + offset));
    f.centers.addAll(centers.map((p) => p + offset));
    f.segments.addAll(segments.map((s) => (s.$1 + offset, s.$2 + offset)));
    f.circles.addAll(
      circles.map((c) => (center: c.center + offset, radius: c.radius)),
    );
    f.boxes.addAll(boxes.map((b) => b.shift(offset)));
    return f;
  }

  static Rect _bounds(List<Offset> points) {
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

/// Where something snapped to, and what to draw to show it.
typedef SnapResult<T> = ({T value, List<SnapGuide> guides});

/// Snapping shapes to each other: corners to corners, centres to
/// centres and symmetry lines, lines tangent to circles, edges lined up,
/// and equal gaps between shapes.
///
/// All distances are in page units; [tolerance] is how close is close
/// enough (the editor turns a fixed screen distance into page units).
abstract final class Snap {
  /// How close (screen pixels) counts as close enough to snap.
  static const screenTolerance = 12.0;

  /// The guides to draw right now, and on which page.
  static var guides = const <SnapGuide>[];
  static int? guidesPage;

  static void showGuides(int pageIndex, List<SnapGuide> newGuides) {
    guides = newGuides;
    guidesPage = newGuides.isEmpty ? null : pageIndex;
  }

  static void clearGuides() {
    guides = const [];
    guidesPage = null;
  }

  /// Snaps a single point [p] (a dragged corner, the end of a line being
  /// drawn) to [targets]. [anchor] is the other end of the line through
  /// [p], if any, so the line can snap tangent to a circle.
  static SnapResult<Offset> point(
    Offset p,
    SnapFeatures targets,
    double tolerance, {
    Offset? anchor,
  }) {
    // Strong snaps first: corners, middles, centres, tangent points.
    Offset? best;
    var bestDistance = tolerance;
    void consider(Offset candidate) {
      final d = (candidate - p).distance;
      if (d <= bestDistance) {
        best = candidate;
        bestDistance = d;
      }
    }

    for (final t in targets.points) {
      consider(t);
    }
    for (final t in targets.centers) {
      consider(t);
    }
    if (anchor != null) {
      for (final circle in targets.circles) {
        for (final t in tangentPoints(anchor, circle.center, circle.radius)) {
          consider(t);
        }
      }
    }
    if (best case final Offset target) {
      return (
        value: target,
        guides: [
          SnapPointGuide(target),
          if (anchor != null && _isTangentPoint(target, targets))
            SnapLineGuide(anchor, target),
        ],
      );
    }

    // Weaker: anywhere on a side or on a circle.
    for (final (a, b) in targets.segments) {
      consider(nearestOnSegment(p, a, b));
    }
    for (final circle in targets.circles) {
      final direction = p - circle.center;
      if (direction.distance > 1e-6) {
        consider(
          circle.center + direction / direction.distance * circle.radius,
        );
      }
    }
    if (best case final Offset target) {
      return (value: target, guides: [SnapPointGuide(target)]);
    }

    // Weakest: in line with a corner or centre, across or up and down.
    final features = [...targets.points, ...targets.centers];
    final x = _nearestValue(p.dx, [for (final f in features) f.dx], tolerance);
    final y = _nearestValue(p.dy, [for (final f in features) f.dy], tolerance);
    final snapped = Offset(x ?? p.dx, y ?? p.dy);
    return (
      value: snapped,
      guides: [
        if (x != null)
          SnapLineGuide(snapped, _closestWith(features, x, snapped, true)),
        if (y != null)
          SnapLineGuide(snapped, _closestWith(features, y, snapped, false)),
      ],
    );
  }

  static bool _isTangentPoint(Offset target, SnapFeatures targets) {
    for (final circle in targets.circles) {
      if (((target - circle.center).distance - circle.radius).abs() < 1e-6) {
        return true;
      }
    }
    return false;
  }

  /// How far to move a selection whose features are [moving], dragged by
  /// [raw], so it snaps to [targets]. Returns the total offset to use.
  static SnapResult<Offset> move(
    SnapFeatures moving,
    SnapFeatures targets,
    Offset raw,
    double tolerance,
  ) {
    final m = moving.shifted(raw);

    // Two-way snaps: a corner or centre onto a corner or centre, or a
    // side tangent to a circle. These fix both directions at once.
    Offset? best;
    List<SnapGuide> bestGuides = const [];
    var bestDistance = tolerance;
    void consider(Offset correction, List<SnapGuide> guides) {
      final d = correction.distance;
      if (d <= bestDistance) {
        best = correction;
        bestGuides = guides;
        bestDistance = d;
      }
    }

    final movingPoints = [...m.points, ...m.centers];
    final targetPoints = [...targets.points, ...targets.centers];
    for (final p in movingPoints) {
      for (final t in targetPoints) {
        consider(t - p, [SnapPointGuide(t)]);
      }
    }
    // A moving side touching a circle that stays put...
    for (final (a, b) in m.segments) {
      for (final circle in targets.circles) {
        final correction = _tangentCorrection(
          a,
          b,
          circle.center,
          circle.radius,
        );
        if (correction != null) {
          consider(correction, [
            SnapPointGuide(
              nearestOnLine(circle.center, a + correction, b + correction),
            ),
          ]);
        }
      }
    }
    // ...and a moving circle touching a side that stays put.
    for (final circle in m.circles) {
      for (final (a, b) in targets.segments) {
        final correction = _tangentCorrection(
          a,
          b,
          circle.center,
          circle.radius,
        );
        if (correction != null) {
          consider(-correction, [
            SnapPointGuide(nearestOnLine(circle.center - correction, a, b)),
          ]);
        }
      }
    }
    if (best case final Offset correction) {
      return (value: raw + correction, guides: bestGuides);
    }

    // One-way snaps, across and up and down separately.
    final (dx, xGuides) = _axisSnap(m, targets, tolerance, horizontal: true);
    final (dy, yGuides) = _axisSnap(m, targets, tolerance, horizontal: false);
    final correction = Offset(dx ?? 0, dy ?? 0);
    final guides = [
      for (final g in [...xGuides, ...yGuides])
        if (g is SnapLineGuide)
          SnapLineGuide(
            // Lines drawn from the moving shape go with it.
            _belongsToMoving(g.from, m) ? g.from + correction : g.from,
            _belongsToMoving(g.to, m) ? g.to + correction : g.to,
          )
        else
          g,
    ];
    return (value: raw + correction, guides: guides);
  }

  static bool _belongsToMoving(Offset p, SnapFeatures m) {
    bool near(Offset q) => (q - p).distanceSquared < 1e-12;
    return m.points.any(near) ||
        m.centers.any(near) ||
        m.boxes.any(
          (b) =>
              near(b.topLeft) ||
              near(b.bottomRight) ||
              near(b.centerLeft) ||
              near(b.centerRight) ||
              near(b.topCenter) ||
              near(b.bottomCenter) ||
              near(b.center),
        );
  }

  /// The best correction along one axis, from lining up edges, centres
  /// and corners, or from evening out gaps; and its guides.
  static (double?, List<SnapGuide>) _axisSnap(
    SnapFeatures m,
    SnapFeatures targets,
    double tolerance, {
    required bool horizontal,
  }) {
    double coord(Offset p) => horizontal ? p.dx : p.dy;

    double? best;
    var bestDistance = tolerance;
    List<SnapGuide> bestGuides = const [];
    void consider(double correction, List<SnapGuide> guides) {
      if (correction.abs() <= bestDistance) {
        best = correction;
        bestDistance = correction.abs();
        bestGuides = guides;
      }
    }

    // Lining up: box edges and middles, centres, corners.
    List<Offset> lineUpPoints(SnapFeatures f) => [
      ...f.centers,
      ...f.points,
      for (final b in f.boxes) ...[
        if (horizontal) ...[
          b.centerLeft,
          b.centerRight,
        ] else ...[
          b.topCenter,
          b.bottomCenter,
        ],
      ],
    ];
    final mine = lineUpPoints(m);
    final theirs = lineUpPoints(targets);
    for (final p in mine) {
      for (final t in theirs) {
        consider(coord(t) - coord(p), [SnapLineGuide(p, t)]);
      }
    }

    // Even gaps between shapes in the same row (or column).
    for (final box in m.boxes.isEmpty ? <Rect>[] : [_union(m.boxes)]) {
      final row = [
        for (final b in targets.boxes)
          if (horizontal
              ? b.top < box.bottom && b.bottom > box.top
              : b.left < box.right && b.right > box.left)
            b,
      ];
      if (row.isEmpty) continue;
      double start(Rect b) => horizontal ? b.left : b.top;
      double end(Rect b) => horizontal ? b.right : b.bottom;
      row.sort((a, b) => start(a).compareTo(start(b)));

      final gaps = <(Rect, Rect)>[
        for (int i = 0; i + 1 < row.length; i++)
          if (start(row[i + 1]) - end(row[i]) > 0) (row[i], row[i + 1]),
      ];
      Rect? before, after;
      for (final b in row) {
        if (end(b) <= start(box) + tolerance &&
            (before == null || end(b) > end(before))) {
          before = b;
        }
        if (start(b) >= end(box) - tolerance &&
            (after == null || start(b) < start(after))) {
          after = b;
        }
      }

      SnapLineGuide gapLine(double from, double to, Rect a, Rect b) {
        final across = horizontal
            ? (max(a.top, b.top) + min(a.bottom, b.bottom)) / 2
            : (max(a.left, b.left) + min(a.right, b.right)) / 2;
        return horizontal
            ? SnapLineGuide(Offset(from, across), Offset(to, across))
            : SnapLineGuide(Offset(across, from), Offset(across, to));
      }

      for (final (a, b) in gaps) {
        final gap = start(b) - end(a);
        final existing = gapLine(end(a), start(b), a, b);
        if (before != null) {
          final correction = end(before) + gap - start(box);
          final moved = box.shift(
            horizontal ? Offset(correction, 0) : Offset(0, correction),
          );
          consider(correction, [
            existing,
            gapLine(end(before), start(moved), before, moved),
          ]);
        }
        if (after != null) {
          final correction = start(after) - gap - end(box);
          final moved = box.shift(
            horizontal ? Offset(correction, 0) : Offset(0, correction),
          );
          consider(correction, [
            existing,
            gapLine(end(moved), start(after), moved, after),
          ]);
        }
      }
      // Right in the middle between two neighbours.
      if (before != null && after != null) {
        final middle = (end(before) + start(after)) / 2;
        final correction = middle - (start(box) + end(box)) / 2;
        final moved = box.shift(
          horizontal ? Offset(correction, 0) : Offset(0, correction),
        );
        consider(correction, [
          gapLine(end(before), start(moved), before, moved),
          gapLine(end(moved), start(after), moved, after),
        ]);
      }
    }
    return (best, bestGuides);
  }

  static Rect _union(List<Rect> boxes) =>
      boxes.reduce((a, b) => a.expandToInclude(b));

  /// The move that makes the line through [a] and [b] touch the circle,
  /// if the line nearly touches it already and the touching point is on
  /// the side itself. Null otherwise.
  static Offset? _tangentCorrection(
    Offset a,
    Offset b,
    Offset center,
    double radius,
  ) {
    final along = b - a;
    final length = along.distance;
    if (length < 1e-6) return null;
    final unit = along / length;
    final normal = Offset(-unit.dy, unit.dx);
    final distance = _dot(center - a, normal);
    final t = _dot(center - a, unit) / length;
    if (t < 0 || t > 1) return null;
    final target = distance >= 0 ? radius : -radius;
    // Moving the line by c along the normal changes the distance by -c.
    return normal * (distance - target);
  }

  /// The points where lines from [from] touch the circle, if [from] is
  /// outside it.
  static List<Offset> tangentPoints(Offset from, Offset center, double r) {
    final toCenter = center - from;
    final d = toCenter.distance;
    if (d <= r + 1e-6) return const [];
    final angle = asin(r / d);
    final base = toCenter.direction;
    final length = sqrt(d * d - r * r);
    return [
      for (final sign in const [-1, 1])
        from + Offset.fromDirection(base + sign * angle, length),
    ];
  }

  static Offset nearestOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared < 1e-12) return a;
    final t = (_dot(p - a, ab) / lengthSquared).clamp(0.0, 1.0);
    return a + ab * t;
  }

  static Offset nearestOnLine(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.distanceSquared;
    if (lengthSquared < 1e-12) return a;
    return a + ab * (_dot(p - a, ab) / lengthSquared);
  }

  static double? _nearestValue(double v, List<double> options, double tol) {
    double? best;
    var bestDistance = tol;
    for (final o in options) {
      final d = (o - v).abs();
      if (d <= bestDistance) {
        best = o;
        bestDistance = d;
      }
    }
    return best;
  }

  /// Of the [features] at [value] (x if [vertical], else y), the one
  /// nearest [p], to draw the line to.
  static Offset _closestWith(
    List<Offset> features,
    double value,
    Offset p,
    bool vertical,
  ) {
    Offset? best;
    var bestDistance = double.infinity;
    for (final f in features) {
      if (((vertical ? f.dx : f.dy) - value).abs() > 1e-9) continue;
      final d = (f - p).distance;
      if (d < bestDistance) {
        best = f;
        bestDistance = d;
      }
    }
    return best ?? p;
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
}
