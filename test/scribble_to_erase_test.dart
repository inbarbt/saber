import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/scribble_to_erase.dart';

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

  /// Back and forth across x = 0..100, drifting slowly down.
  List<Offset> zigzag({int passes = 8, double width = 100}) => [
    for (int pass = 0; pass < passes; pass++)
      for (int i = 0; i <= 10; i++)
        Offset(
          pass.isEven ? width * i / 10 : width * (10 - i) / 10,
          100 + pass * 3 + i * 0.3,
        ),
  ];

  group('isScribble:', () {
    test('a back-and-forth zigzag is a scribble', () {
      expect(ScribbleToErase.isScribble(zigzag()), isTrue);
    });

    test('a straight line is not', () {
      expect(
        ScribbleToErase.isScribble([
          for (int i = 0; i < 30; i++) Offset(i * 5.0, 0),
        ]),
        isFalse,
      );
    });

    test('a circle is not', () {
      expect(
        ScribbleToErase.isScribble([
          for (double a = 0; a < 2 * pi; a += 0.1) Offset.fromDirection(a, 50),
        ]),
        isFalse,
      );
    });

    test('a short wave like cursive "mm" is not', () {
      expect(ScribbleToErase.isScribble(zigzag(passes: 3)), isFalse);
    });

    test('a tiny scribble is not', () {
      expect(ScribbleToErase.isScribble(zigzag(width: 8)), isFalse);
    });

    test('reversals ignore small wiggles', () {
      expect(ScribbleToErase.countReversals([0, 10, 9, 10, 0, 10, 0], 3), 3);
    });
  });

  group('strokesUnder:', () {
    test('erases writing under the scribble but not beside it', () {
      final under = strokeThrough([
        for (int i = 0; i <= 10; i++) Offset(20 + i * 6.0, 110),
      ]);
      final beside = strokeThrough([
        for (int i = 0; i <= 10; i++) Offset(300 + i * 6.0, 110),
      ]);
      final scribble = strokeThrough(zigzag());
      expect(
        ScribbleToErase.strokesUnder(scribble, [under, beside, scribble]),
        [under],
      );
    });

    test('a stroke only half under it is kept unless mostly covered', () {
      final mostlyOutside = strokeThrough([
        for (int i = 0; i <= 20; i++) Offset(60 + i * 10.0, 110),
      ]);
      final scribble = strokeThrough(zigzag());
      expect(ScribbleToErase.strokesUnder(scribble, [mostlyOutside]), isEmpty);
    });
  });

  test('convex hull of a square with an inner point', () {
    final hull = ScribbleToErase.convexHull(const [
      Offset.zero,
      Offset(10, 0),
      Offset(5, 5),
      Offset(10, 10),
      Offset(0, 10),
    ]);
    expect(hull.length, 4);
    expect(hull, isNot(contains(const Offset(5, 5))));
  });
}
