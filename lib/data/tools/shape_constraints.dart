import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/data/tools/shape_library.dart';

/// The result of dragging one corner of a shape: its new corners, and
/// which corner's angle to show while dragging (or null).
typedef VertexMove = ({List<Offset> vertices, int? angleAt});

/// How dragging a corner reshapes each kind of shape, so it stays the
/// kind of shape it is: a trapezoid keeps its parallel sides, a rhombus
/// its equal sides, a right triangle its right angle.
///
/// Rules work on the corners as they are now, so they hold however the
/// shape was turned or moved. Corners are in the order
/// [ShapeLibrary.outline] makes them, without the repeated first point.
abstract final class ShapeConstraints {
  /// Angles snap to multiples of this (degrees)...
  static const snapStep = 15.0;

  /// ...when they are within this many degrees of one.
  static const snapTolerance = 2.0;

  /// Whether a shape of [kind] has corners to drag at all.
  static bool hasVertices(LibraryShape? kind) =>
      kind != LibraryShape.ellipse && kind != LibraryShape.graph;

  /// Moves corner [index] of a shape of [kind] towards [target].
  /// A null [kind] (a hand-drawn shape) moves just that corner.
  static VertexMove move(
    LibraryShape? kind,
    List<Offset> vertices,
    int index,
    Offset target,
  ) {
    final v = List.of(vertices);
    switch (kind) {
      case LibraryShape.rectangle when v.length == 4:
        return (vertices: _rectangle(v, index, target), angleAt: null);
      case LibraryShape.rightTriangle when v.length == 3:
        return _rightTriangle(v, index, target);
      case LibraryShape.rhombus when v.length == 4:
        return (vertices: _rhombus(v, index, target), angleAt: index);
      case LibraryShape.parallelogram when v.length == 4:
        return _parallelSides(v, index, target, moveWholeSide: true);
      case LibraryShape.trapezoid when v.length == 4:
        return _parallelSides(v, index, target, moveWholeSide: false);
      case LibraryShape.polygon:
        return (vertices: _similar(v, index, target), angleAt: null);
      case LibraryShape.star when v.length == 10:
        return (
          vertices: index.isEven
              ? _similar(v, index, target)
              : _starInner(v, index, target),
          angleAt: null,
        );
      default:
        v[index] = target;
        return (vertices: v, angleAt: v.length >= 3 ? index : null);
    }
  }

  /// The sides of a shape of [kind] with [count] corners that can be
  /// moved (side i joins corner i and the next), keeping its kind:
  /// a rectangle's sides, a trapezoid's parallel sides, a parallelogram's
  /// sides, a triangle's sides, a right triangle's legs. A hand-drawn
  /// shape (null [kind]) can move any side.
  static List<int> movableSides(LibraryShape? kind, int count) {
    if (count < 3) return const [];
    return switch (kind) {
      null => [for (int i = 0; i < count; i++) i],
      LibraryShape.rectangle ||
      LibraryShape.parallelogram when count == 4 => const [0, 1, 2, 3],
      LibraryShape.trapezoid when count == 4 => const [0, 2],
      LibraryShape.triangle when count == 3 => const [0, 1, 2],
      LibraryShape.rightTriangle when count == 3 => const [0, 1],
      _ => const [],
    };
  }

  /// Moves side [side] of [vertices] straight out or in by the part of
  /// [delta] across it, so it stays parallel to where it was.
  static List<Offset> moveSide(List<Offset> vertices, int side, Offset delta) {
    final v = List.of(vertices);
    final a = v[side], b = v[(side + 1) % v.length];
    final along = _unit(b - a);
    final normal = Offset(-along.dy, along.dx);
    final shift = normal * _dot(delta, normal);
    v[side] = a + shift;
    v[(side + 1) % v.length] = b + shift;
    return v;
  }

  /// The inside angle at corner [index] of the closed shape [v], degrees.
  static double angleAt(List<Offset> v, int index) {
    final n = v.length;
    final a = v[(index - 1 + n) % n] - v[index];
    final b = v[(index + 1) % n] - v[index];
    return _angleBetween(a, b);
  }

  static double _angleBetween(Offset a, Offset b) {
    final denominator = a.distance * b.distance;
    if (denominator < 1e-9) return 0;
    final cosine = ((a.dx * b.dx + a.dy * b.dy) / denominator).clamp(-1.0, 1.0);
    return acos(cosine) * 180 / pi;
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  static Offset _unit(Offset a) {
    final d = a.distance;
    return d < 1e-9 ? const Offset(1, 0) : a / d;
  }

  /// Stays a rectangle: the opposite corner stays put and the sides keep
  /// their directions.
  static List<Offset> _rectangle(List<Offset> v, int i, Offset p) {
    final o = v[(i + 2) % 4];
    final u = _unit(v[1] - v[0]);
    final w = _unit(v[3] - v[0]);
    final a0 = _dot(v[i] - o, u), b0 = _dot(v[i] - o, w);
    final a1 = _dot(p - o, u), b1 = _dot(p - o, w);
    final sa = a0.abs() < 1e-6 ? 1.0 : a1 / a0;
    final sb = b0.abs() < 1e-6 ? 1.0 : b1 / b0;
    return [
      for (final corner in v)
        o + u * (_dot(corner - o, u) * sa) + w * (_dot(corner - o, w) * sb),
    ];
  }

  /// Corners: [0] the end of one leg, [1] the right angle, [2] the end
  /// of the other leg. Leg ends slide along their legs; the right-angle
  /// corner moves around the circle through the other two (Thales), so
  /// the angle stays 90°.
  static VertexMove _rightTriangle(List<Offset> v, int i, Offset p) {
    if (i == 1) {
      final center = (v[0] + v[2]) / 2;
      final radius = (v[0] - v[2]).distance / 2;
      final direction = p - center;
      if (direction.distance > 1e-6) {
        v[1] = center + _unit(direction) * radius;
      }
      return (vertices: v, angleAt: 0);
    }
    final leg = _unit(v[i] - v[1]);
    final length = max(1.0, _dot(p - v[1], leg));
    v[i] = v[1] + leg * length;
    return (vertices: v, angleAt: i);
  }

  /// Corners: top, right, bottom, left. A corner and its opposite move
  /// together along their diagonal, so all four sides stay equal.
  static List<Offset> _rhombus(List<Offset> v, int i, Offset p) {
    final center = (v[0] + v[2]) / 2;
    final axis = _unit(v[i] - center);
    final half = max(1.0, _dot(p - center, axis));
    v[i] = center + axis * half;
    v[(i + 2) % 4] = center - axis * half;
    return v;
  }

  /// Corners: [0] and [1] on one side, [2] and [3] on the parallel side.
  ///
  /// Parallelogram ([moveWholeSide]): the dragged corner's side moves
  /// with it, which changes the slant and the height.
  /// Trapezoid: only the dragged corner follows the pointer; the other
  /// corner on its side moves straight up or down to stay parallel.
  /// Either way, the angle the dragged side's leg makes with the other
  /// side is shown, and snaps to multiples of [snapStep].
  static VertexMove _parallelSides(
    List<Offset> v,
    int i,
    Offset p, {
    required bool moveWholeSide,
  }) {
    final partner = i ^ 1; // 0<->1, 2<->3
    // Corners are in order around the shape, so the leg from corner i
    // goes to the corner next to it on the other side.
    final foot = switch (i) {
      0 => 3,
      1 => 2,
      2 => 1,
      _ => 0,
    };
    final footPartner = foot ^ 1;

    final along = _unit(v[footPartner] - v[foot]); // the other side
    final normal = Offset(-along.dy, along.dx);

    if (moveWholeSide) {
      final delta = p - v[i];
      v[i] += delta;
      v[partner] += delta;
    } else {
      v[i] = p;
      v[partner] += normal * _dot(v[i] - v[partner], normal);
    }

    // Snap the leg's angle with the other side.
    final leg = v[i] - v[foot];
    final height = _dot(leg, normal);
    final angle = _angleBetween(along, leg);
    final nearest = (angle / snapStep).roundToDouble() * snapStep;
    if ((angle - nearest).abs() <= snapTolerance &&
        nearest > 0 &&
        nearest < 180 &&
        height.abs() > 1e-6) {
      final radians = nearest * pi / 180;
      final snapped =
          v[foot] + along * (height.abs() / tan(radians)) + normal * height;
      final shift = snapped - v[i];
      v[i] = snapped;
      if (moveWholeSide) v[partner] += shift;
    }
    return (vertices: v, angleAt: foot);
  }

  /// Turns and scales the whole shape about its centre, so corner [i]
  /// lands on [p]. Regular polygons stay regular.
  static List<Offset> _similar(List<Offset> v, int i, Offset p) {
    final center = _centroid(v);
    final from = v[i] - center;
    final to = p - center;
    final fromSquared = from.distanceSquared;
    if (fromSquared < 1e-9) return v;
    // Complex division to/from: the turn and scale that maps one onto
    // the other.
    final re = (to.dx * from.dx + to.dy * from.dy) / fromSquared;
    final im = (to.dy * from.dx - to.dx * from.dy) / fromSquared;
    return [
      for (final corner in v)
        center +
            Offset(
              re * (corner.dx - center.dx) - im * (corner.dy - center.dy),
              im * (corner.dx - center.dx) + re * (corner.dy - center.dy),
            ),
    ];
  }

  /// Moves all of a star's inner corners in or out together.
  static List<Offset> _starInner(List<Offset> v, int i, Offset p) {
    final center = _centroid(v);
    final current = (v[i] - center).distance;
    if (current < 1e-6) return v;
    final outer = (v[0] - center).distance;
    final wanted = (p - center).distance.clamp(outer * 0.1, outer * 0.95);
    final k = wanted / current;
    return [
      for (int j = 0; j < v.length; j++)
        if (j.isOdd) center + (v[j] - center) * k else v[j],
    ];
  }

  static Offset _centroid(List<Offset> v) {
    var sum = Offset.zero;
    for (final p in v) {
      sum += p;
    }
    return sum / v.length.toDouble();
  }
}
