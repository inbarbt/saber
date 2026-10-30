import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/circle_to_lasso.dart';

void main() {
  final page = EditorPage();

  Stroke strokeThrough(List<Offset> points) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 4, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: .ballpointPen,
  )..addPoints(points);

  /// A hand-drawn-ish loop around (200, 200), radius 80,
  /// that doesn't quite close.
  Stroke loop({double endAngle = 2 * pi - 0.2}) => strokeThrough([
    for (double a = 0; a <= endAngle; a += 0.1)
      const Offset(200, 200) + Offset.fromDirection(a, 80),
  ]);

  group('isLoop:', () {
    test('a nearly closed circle is a loop', () {
      expect(CircleToLasso.isLoop(loop()), isTrue);
    });

    test('a half circle is not a loop', () {
      expect(CircleToLasso.isLoop(loop(endAngle: pi)), isFalse);
    });

    test('a straight line is not a loop', () {
      expect(
        CircleToLasso.isLoop(
          strokeThrough([for (int i = 0; i < 20; i++) Offset(i * 10.0, 0)]),
        ),
        isFalse,
      );
    });

    test('a small "o" is not a loop', () {
      expect(
        CircleToLasso.isLoop(
          strokeThrough([
            for (double a = 0; a < 2 * pi; a += 0.3)
              const Offset(50, 50) + Offset.fromDirection(a, 6),
          ]),
        ),
        isFalse,
      );
    });

    test('a loop turned into a circle shape no longer counts', () {
      final circle = CircleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        center: const Offset(200, 200),
        radius: 80,
      );
      expect(CircleToLasso.isLoop(circle), isFalse);
    });
  });

  group('loopAt:', () {
    test('finds the loop when pressing on its outline', () {
      final l = loop();
      expect(CircleToLasso.loopAt(const Offset(280, 200), [l], 1), same(l));
    });

    test('ignores presses inside the loop', () {
      expect(CircleToLasso.loopAt(const Offset(200, 200), [loop()], 1), isNull);
    });

    test('ignores presses far outside', () {
      expect(CircleToLasso.loopAt(const Offset(400, 200), [loop()], 1), isNull);
    });
  });

  test('the lasso path encloses what the loop surrounds', () {
    final path = CircleToLasso.lassoPath(loop());
    expect(path.contains(const Offset(200, 200)), isTrue);
    expect(path.contains(const Offset(400, 400)), isFalse);
  });
}
