import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_pen.dart';

/// Points along the outline of a w x h rectangle centred on [center],
/// turned by [degrees], like a hand-drawn rectangle.
List<Offset> rectangleOutline(
  Offset center,
  double w,
  double h,
  double degrees,
) {
  final corners = [
    Offset(-w / 2, -h / 2),
    Offset(w / 2, -h / 2),
    Offset(w / 2, h / 2),
    Offset(-w / 2, h / 2),
  ];
  final a = degrees * pi / 180;
  Offset turn(Offset p) =>
      center +
      Offset(p.dx * cos(a) - p.dy * sin(a), p.dx * sin(a) + p.dy * cos(a));
  final points = <Offset>[];
  for (int side = 0; side < 4; side++) {
    final from = corners[side], to = corners[(side + 1) % 4];
    for (int i = 0; i < 30; i++) {
      points.add(turn(Offset.lerp(from, to, i / 30)!));
    }
  }
  // Hand-drawn: the end lands near the start, not exactly on it
  points.add(turn(corners.first) + const Offset(1.5, 0.5));
  return points;
}

void main() {
  FlavorConfig.setup();
  final page = EditorPage();

  Stroke drawn(List<Offset> points) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 4, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: .ballpointPen,
  )..addPoints(points);

  group('minAreaRect:', () {
    test('finds the turn of a turned rectangle', () {
      final corners = ShapeGeometry.minAreaRect(
        rectangleOutline(const Offset(200, 200), 120, 60, 20),
      );
      expect(corners, hasLength(4));
      final turn = ShapeGeometry.rectTurnDegrees(corners);
      // Either the long or the short side may come first
      expect(
        (turn - 20).abs() < 1 ||
            (turn + 70).abs() < 1 ||
            (turn - 20 + 90).abs() < 1,
        isTrue,
        reason: 'turn was $turn',
      );
      expect(ShapeGeometry.isUpright(corners), isFalse);
    });

    test('an upright rectangle is upright', () {
      final corners = ShapeGeometry.minAreaRect(
        rectangleOutline(const Offset(200, 200), 120, 60, 3),
      );
      expect(ShapeGeometry.isUpright(corners), isTrue);
    });

    test('too few points give no rectangle', () {
      expect(
        ShapeGeometry.minAreaRect(const [Offset.zero, Offset(1, 1)]),
        isEmpty,
      );
    });
  });

  group('strokeToShape:', () {
    test('a turned rectangle keeps its angle', () {
      final stroke = drawn(
        rectangleOutline(const Offset(200, 200), 120, 60, 25),
      );
      final shape = stroke.detectShape();
      expect(shape?.name, isNotNull);
      expect(shape!.name, DefaultUnistrokeNames.rectangle);
      final result = ShapePen.strokeToShape(stroke, shape);
      expect(result, isNot(isA<RectangleStroke>()));
      final corners = ShapeGeometry.minAreaRect(result.centerline);
      expect(ShapeGeometry.isUpright(corners), isFalse);
    });

    test('an upright rectangle becomes a rectangle shape', () {
      final stroke = drawn(
        rectangleOutline(const Offset(200, 200), 120, 60, 0),
      );
      final shape = stroke.detectShape();
      expect(shape!.name, DefaultUnistrokeNames.rectangle);
      final result = ShapePen.strokeToShape(stroke, shape);
      expect(result, isA<RectangleStroke>());
    });

    test('a rectangle that ends exactly at its start is still a rectangle', () {
      final points = rectangleOutline(const Offset(200, 200), 120, 60, 0)
        ..removeLast();
      final stroke = drawn([...points, points.first]);
      expect(stroke.detectShape()?.name, DefaultUnistrokeNames.rectangle);
    });

    test('a circle becomes a circle shape in the same colour', () {
      final stroke = drawn([
        for (double a = 0; a <= 2 * pi; a += 0.03)
          const Offset(100, 100) + Offset.fromDirection(a, 50),
      ])..color = Colors.red;
      final shape = stroke.detectShape();
      expect(shape!.name, DefaultUnistrokeNames.circle);
      final result = ShapePen.strokeToShape(stroke, shape);
      expect(result, isA<CircleStroke>());
      expect(result.color, Colors.red);
      expect(result.toolId, stroke.toolId);
    });
  });
}
