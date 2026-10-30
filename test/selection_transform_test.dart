import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/selection_transform.dart';

void main() {
  const bounds = Rect.fromLTWH(100, 100, 200, 100);

  group('hitTest:', () {
    test('finds a corner', () {
      expect(
        SelectionTransform.hitTest(const Offset(302, 98), bounds, 1),
        SelectionHandle.topRight,
      );
    });

    test('finds the rotate handle above the box', () {
      final rotate = bounds.topCenter - const Offset(0, 40);
      expect(
        SelectionTransform.hitTest(rotate, bounds, 1),
        SelectionHandle.rotate,
      );
    });

    test('misses the middle of the box', () {
      expect(SelectionTransform.hitTest(bounds.center, bounds, 1), isNull);
    });

    test('hit area shrinks in page units when zoomed in', () {
      // 20 page units away: inside at 1x (28px), outside at 2x (14 units)
      const near = Offset(320, 100);
      expect(
        SelectionTransform.hitTest(near, bounds, 1),
        SelectionHandle.topRight,
      );
      expect(SelectionTransform.hitTest(near, bounds, 2), isNull);
    });
  });

  group('resize:', () {
    test('dragging bottom-right outward doubles the size', () {
      final (sx, sy) = SelectionTransform.resizeFactors(
        bounds,
        SelectionHandle.bottomRight,
        const Offset(500, 300),
        keepAspectRatio: false,
      );
      expect(sx, 2);
      expect(sy, 2);
    });

    test('top-left keeps the bottom-right corner fixed', () {
      final m = SelectionTransform.resizeMatrix(
        bounds,
        SelectionHandle.topLeft,
        const Offset(200, 150),
        keepAspectRatio: false,
      );
      expect(
        MatrixUtils.transformPoint(m, bounds.bottomRight),
        bounds.bottomRight,
      );
      expect(
        MatrixUtils.transformPoint(m, bounds.topLeft),
        const Offset(200, 150),
      );
    });

    test('keeping the aspect ratio uses one factor', () {
      final (sx, sy) = SelectionTransform.resizeFactors(
        bounds,
        SelectionHandle.bottomRight,
        const Offset(500, 220),
        keepAspectRatio: true,
      );
      expect(sx, sy);
      expect(sx, 2);
    });

    test('never flips or collapses', () {
      final (sx, sy) = SelectionTransform.resizeFactors(
        bounds,
        SelectionHandle.bottomRight,
        const Offset(0, 0),
        keepAspectRatio: false,
      );
      expect(sx, SelectionTransform.minScale);
      expect(sy, SelectionTransform.minScale);
    });

    test('a horizontal line still scales', () {
      const line = Rect.fromLTRB(0, 50, 100, 50);
      final (sx, sy) = SelectionTransform.resizeFactors(
        line,
        SelectionHandle.bottomRight,
        const Offset(200, 90),
        keepAspectRatio: true,
      );
      expect(sx, 2);
      expect(sy, 2);
    });
  });

  group('rotate:', () {
    const center = Offset(0, 0);

    test('quarter turn clockwise on screen is 90 degrees', () {
      expect(
        SelectionTransform.rotationDegrees(
          center,
          const Offset(0, -10),
          const Offset(10, 0),
        ),
        closeTo(90, 1e-9),
      );
    });

    test('snaps to 45 degrees when close', () {
      final p = Offset.fromDirection((-90 + 46) * pi / 180, 10);
      expect(
        SelectionTransform.rotationDegrees(center, const Offset(0, -10), p),
        45,
      );
    });

    test('does not snap when far from a step', () {
      final p = Offset.fromDirection((-90 + 37) * pi / 180, 10);
      expect(
        SelectionTransform.rotationDegrees(center, const Offset(0, -10), p),
        closeTo(37, 1e-9),
      );
    });

    test('rotation keeps the center in place', () {
      final m = SelectionTransform.rotateMatrix(bounds.center, 30);
      final moved = MatrixUtils.transformPoint(m, bounds.center);
      expect(moved.dx, closeTo(bounds.center.dx, 1e-9));
      expect(moved.dy, closeTo(bounds.center.dy, 1e-9));
    });

    test('images only move under rotation', () {
      const rect = Rect.fromLTWH(0, 0, 40, 20);
      final m = SelectionTransform.rotateMatrix(const Offset(100, 0), 90);
      final result = SelectionTransform.transformImageRect(rect, m);
      expect(result.width, closeTo(40, 1e-9));
      expect(result.height, closeTo(20, 1e-9));
      expect(result.center, isNot(rect.center));
    });
  });

  group('strokes:', () {
    final page = EditorPage();

    Stroke line() => Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 4, isComplete: true),
      pageIndex: 0,
      page: page,
      toolId: .ballpointPen,
    )..addPoints(const [Offset(0, 0), Offset(10, 0), Offset(20, 0)]);

    test(
      'transformed stroke is a new object and the original is unchanged',
      () {
        final original = line();
        final m = SelectionTransform.rotateMatrix(Offset.zero, 90);
        final result = original.transformed(m);
        expect(identical(result, original), isFalse);
        expect(original.lowQualityPolygon.first.dy, closeTo(0, 4));
        final bounds = SelectionTransform.contentBounds([result], const [])!;
        // A horizontal line turned 90 degrees becomes vertical
        expect(bounds.height, greaterThan(bounds.width));
      },
    );

    test('scaling doubles thickness', () {
      final original = line();
      final m = SelectionTransform.resizeMatrix(
        const Rect.fromLTWH(0, 0, 20, 20),
        SelectionHandle.bottomRight,
        const Offset(40, 40),
        keepAspectRatio: true,
      );
      expect(original.transformed(m).options.size, 8);
    });

    test('a rectangle stays a rectangle when resized', () {
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(0, 0, 10, 10),
      );
      final m = SelectionTransform.resizeMatrix(
        const Rect.fromLTWH(0, 0, 10, 10),
        SelectionHandle.bottomRight,
        const Offset(20, 30),
        keepAspectRatio: false,
      );
      final result = rect.transformed(m);
      expect(result, isA<RectangleStroke>());
      expect(
        (result as RectangleStroke).rect,
        const Rect.fromLTWH(0, 0, 20, 30),
      );
    });

    test('a rotated rectangle becomes a plain stroke', () {
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(0, 0, 10, 10),
      );
      final result = rect.transformed(
        SelectionTransform.rotateMatrix(const Offset(5, 5), 30),
      );
      expect(result, isNot(isA<RectangleStroke>()));
      expect(result.isEmpty, isFalse);
    });

    test('a circle stays a circle when rotated or evenly scaled', () {
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        center: const Offset(10, 10),
        radius: 5,
      );
      final rotated = circle.transformed(
        SelectionTransform.rotateMatrix(Offset.zero, 90),
      );
      expect(rotated, isA<CircleStroke>());
      expect((rotated as CircleStroke).radius, closeTo(5, 1e-9));

      final stretched = circle.transformed(
        SelectionTransform.resizeMatrix(
          const Rect.fromLTWH(5, 5, 10, 10),
          SelectionHandle.bottomRight,
          const Offset(35, 15),
          keepAspectRatio: false,
        ),
      );
      expect(stretched, isNot(isA<CircleStroke>()));
    });
  });

  test('history: reversing a transform swaps before and after', () {
    final page = EditorPage();
    final a = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(),
      pageIndex: 0,
      page: page,
      toolId: .ballpointPen,
    );
    final b = a.copy();
    final historic = HistoricTransform(
      pageIndex: 0,
      before: [a],
      after: [b],
      images: const [],
      imageRectsBefore: const [],
      imageRectsAfter: const [],
    );
    final reversed = historic.reverse();
    expect(reversed.before.single, same(b));
    expect(reversed.after.single, same(a));
  });
}
