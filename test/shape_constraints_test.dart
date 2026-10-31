import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_constraints.dart';
import 'package:saber/data/tools/shape_library.dart';

void main() {
  FlavorConfig.setup();

  List<Offset> corners(LibraryShape shape, {int n = 6}) {
    final outline = ShapeLibrary.outline(
      shape,
      const Offset(100, 100),
      const Offset(300, 220),
      corners: n,
    );
    return outline.sublist(0, outline.length - 1);
  }

  /// Direction of a side, as an angle in degrees in [0, 180).
  double direction(Offset a, Offset b) {
    final d = atan2(b.dy - a.dy, b.dx - a.dx) * 180 / pi;
    return (d % 180 + 180) % 180;
  }

  double sideLength(List<Offset> v, int i) =>
      (v[(i + 1) % v.length] - v[i]).distance;

  group('trapezoid', () {
    test('the parallel sides stay parallel; the base stays put', () {
      final v = corners(.trapezoid);
      final move = ShapeConstraints.move(
        .trapezoid,
        v,
        1,
        const Offset(270, 80),
      );
      final w = move.vertices;
      expect(direction(w[0], w[1]), closeTo(direction(w[3], w[2]), 1e-9));
      expect(w[2], v[2]);
      expect(w[3], v[3]);
      expect(w[1], const Offset(270, 80));
    });

    test("shows the angle of the dragged corner's leg with the base", () {
      final v = corners(.trapezoid);
      final move = ShapeConstraints.move(.trapezoid, v, 1, v[1]);
      expect(move.angleAt, 2);
    });

    test('the leg angle snaps to 60°', () {
      final v = corners(.trapezoid); // base from (100,220) to (300,220)
      // 61° at the bottom-right corner, 120 high
      final target = Offset(300 - 120 / tan(61 * pi / 180), 100);
      final move = ShapeConstraints.move(.trapezoid, v, 1, target);
      expect(
        ShapeConstraints.angleAt(move.vertices, move.angleAt!),
        closeTo(60, 1e-6),
      );
      expect(move.vertices[1].dy, closeTo(100, 1e-6));
    });
  });

  test('a parallelogram stays a parallelogram', () {
    final v = corners(.parallelogram);
    final w = ShapeConstraints.move(
      .parallelogram,
      v,
      0,
      const Offset(110, 60),
    ).vertices;
    expect(sideLength(w, 0), closeTo(sideLength(w, 2), 1e-9));
    expect(sideLength(w, 1), closeTo(sideLength(w, 3), 1e-9));
    expect(direction(w[0], w[1]), closeTo(direction(w[3], w[2]), 1e-9));
  });

  test('a rhombus keeps four equal sides', () {
    final v = corners(.rhombus);
    final w = ShapeConstraints.move(
      .rhombus,
      v,
      1,
      const Offset(350, 170),
    ).vertices;
    for (int i = 1; i < 4; i++) {
      expect(sideLength(w, i), closeTo(sideLength(w, 0), 1e-9));
    }
  });

  group('right triangle', () {
    test('the right angle stays 90° when its corner moves', () {
      final v = corners(.rightTriangle);
      final w = ShapeConstraints.move(
        .rightTriangle,
        v,
        1,
        const Offset(130, 260),
      ).vertices;
      expect(ShapeConstraints.angleAt(w, 1), closeTo(90, 1e-6));
    });

    test('a leg end slides along its leg', () {
      final v = corners(.rightTriangle);
      final w = ShapeConstraints.move(
        .rightTriangle,
        v,
        2,
        const Offset(400, 240),
      ).vertices;
      expect(w[2].dy, closeTo(v[1].dy, 1e-9));
      expect(w[2].dx, closeTo(400, 1e-9));
      expect(ShapeConstraints.angleAt(w, 1), closeTo(90, 1e-6));
    });
  });

  test('a rectangle stays a rectangle; the opposite corner stays', () {
    final v = corners(.rectangle);
    final w = ShapeConstraints.move(
      .rectangle,
      v,
      2,
      const Offset(350, 300),
    ).vertices;
    for (int i = 0; i < 4; i++) {
      expect(ShapeConstraints.angleAt(w, i), closeTo(90, 1e-6));
    }
    expect(w[0], v[0]);
    expect(w[2], const Offset(350, 300));
  });

  test('a regular polygon stays regular', () {
    final v = ShapeLibrary.outline(
      .polygon,
      const Offset(100, 100),
      const Offset(300, 300),
    );
    final hexagon = v.sublist(0, v.length - 1);
    final w = ShapeConstraints.move(
      .polygon,
      hexagon,
      0,
      const Offset(260, 90),
    ).vertices;
    for (int i = 1; i < w.length; i++) {
      expect(sideLength(w, i), closeTo(sideLength(w, 0), 1e-6));
    }
    expect(w[0].dx, closeTo(260, 1e-6));
  });

  test("a star's inner corners move together; the points stay", () {
    final v = ShapeLibrary.outline(
      .star,
      const Offset(100, 100),
      const Offset(300, 300),
    );
    final star = v.sublist(0, v.length - 1);
    final w = ShapeConstraints.move(
      .star,
      star,
      1,
      const Offset(200, 150),
    ).vertices;
    const center = Offset(200, 200);
    for (int i = 0; i < 10; i += 2) {
      expect(w[i], star[i]);
    }
    final inner = (w[1] - center).distance;
    for (int i = 3; i < 10; i += 2) {
      expect((w[i] - center).distance, closeTo(inner, 1e-6));
    }
  });

  group('strokes', () {
    final page = EditorPage();
    Stroke library(LibraryShape shape) {
      final raw = Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
      )..addPoints(const [Offset(100, 100), Offset(300, 220)]);
      return ShapeLibrary.strokeFor(raw, shape);
    }

    test('remember their kind when saved and loaded', () {
      final stroke = library(.trapezoid);
      final loaded = Stroke.fromJson(
        stroke.toJson(),
        fileVersion: 19,
        pageIndex: 0,
        page: page,
      );
      expect(loaded.libraryKind, LibraryShape.trapezoid);
    });

    test('keep their kind after a corner is dragged', () {
      final stroke = library(.trapezoid);
      final moved = stroke.withVertex(1, const Offset(280, 90));
      expect(moved.libraryKind, LibraryShape.trapezoid);
      expect(moved.vertices, hasLength(4));
    });

    test('an ellipse has no corners to drag', () {
      expect(library(.ellipse).vertices, isEmpty);
    });

    test('a hand-drawn rectangle stays a rectangle', () {
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(100, 100, 200, 100),
      );
      final moved = rect.withVertex(2, const Offset(350, 260));
      final v = moved.vertices;
      expect(v, hasLength(4));
      for (int i = 0; i < 4; i++) {
        expect(ShapeConstraints.angleAt(v, i), closeTo(90, 1e-6));
      }
    });

    test('a stretched circle has no corner handles', () {
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        center: const Offset(200, 200),
        radius: 50,
      );
      final stretched = circle.transformed(Matrix4.diagonal3Values(2, 1, 1));
      expect(stretched.libraryKind, LibraryShape.ellipse);
      expect(stretched.vertices, isEmpty);
    });
  });

  group('snap to a perfect circle', () {
    test('a nearly round ellipse is drawn round', () {
      final r = ShapeLibrary.circleSnap(
        const Offset(100, 100),
        const Offset(200, 204),
      );
      expect(r.width, r.height);
      expect(r.topLeft, const Offset(100, 100));
    });

    test('a clearly oval one is left alone', () {
      final r = ShapeLibrary.circleSnap(
        const Offset(100, 100),
        const Offset(200, 160),
      );
      expect(r.width, isNot(r.height));
    });

    test('resizing a circle snaps back to round', () {
      const box = SelectionBox(Rect.fromLTWH(0, 0, 100, 100), 0);
      final (sx, sy) = SelectionTransform.resizeFactors(
        box,
        .right,
        const Offset(103, 50),
        keepAspectRatio: false,
        snapToCircle: const Size(100, 100),
      );
      expect(sx, sy);
      final (fx, fy) = SelectionTransform.resizeFactors(
        box,
        .right,
        const Offset(150, 50),
        keepAspectRatio: false,
        snapToCircle: const Size(100, 100),
      );
      expect(fx, isNot(fy));
    });
  });
}
