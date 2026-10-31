import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/selection_transform.dart';

void main() {
  final page = EditorPage();

  Stroke triangle() =>
      Stroke(
          color: Colors.black,
          pressureEnabled: false,
          options: StrokeOptions(size: 3, isComplete: true),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
        )
        ..addPoints(const [
          Offset.zero,
          Offset(100, 0),
          Offset(50, 80),
          Offset.zero,
        ])
        ..crisp = true;

  test('a closed triangle has three vertices', () {
    expect(triangle().vertices, const [
      Offset.zero,
      Offset(100, 0),
      Offset(50, 80),
    ]);
  });

  test('moving a vertex changes only that corner', () {
    final original = triangle();
    final moved = original.withVertex(2, const Offset(80, 120));
    expect(moved.vertices[2], const Offset(80, 120));
    expect(moved.vertices[0], Offset.zero);
    expect(original.vertices[2], const Offset(50, 80));
  });

  test('moving the first vertex keeps the shape closed', () {
    final moved = triangle().withVertex(0, const Offset(-20, -10));
    expect(moved.centerline.first, const Offset(-20, -10));
    expect(moved.centerline.last, const Offset(-20, -10));
    expect(moved.vertices, hasLength(3));
  });

  test('moved shapes keep their style', () {
    final moved =
        (triangle()
              ..dashed = true
              ..fillColor = const Color(0x40FF0000))
            .withVertex(1, const Offset(120, 10));
    expect(moved.crisp, isTrue);
    expect(moved.dashed, isTrue);
    expect(moved.fillColor, const Color(0x40FF0000));
  });

  test('a rectangle becomes a four-sided shape when a corner moves', () {
    final rect = RectangleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
      rect: const Rect.fromLTWH(0, 0, 100, 50),
    );
    expect(rect.vertices, hasLength(4));
    final moved = rect.withVertex(1, const Offset(130, -20));
    expect(moved, isNot(isA<RectangleStroke>()));
    expect(moved.vertices, hasLength(4));
    expect(moved.vertices[1], const Offset(130, -20));
    expect(moved.options.size, 3);
  });

  test('handwriting and circles have no vertices', () {
    final writing = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(),
      pageIndex: 0,
      page: page,
      toolId: .ballpointPen,
    )..addPoints(const [Offset.zero, Offset(10, 10), Offset(20, 0)]);
    final circle = CircleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
      center: Offset.zero,
      radius: 10,
    );
    expect(writing.vertices, isEmpty);
    expect(circle.vertices, isEmpty);
  });

  test('vertices are editable only when one shape is selected', () {
    expect(
      SelectionTransform.editableVertices([triangle()], const []),
      hasLength(3),
    );
    expect(
      SelectionTransform.editableVertices([triangle(), triangle()], const []),
      isEmpty,
    );
  });

  test('vertex hit test finds the nearest corner', () {
    final vertices = triangle().vertices;
    expect(
      SelectionTransform.hitTestVertex(const Offset(98, 4), vertices, 1),
      1,
    );
    expect(
      SelectionTransform.hitTestVertex(const Offset(50, 30), vertices, 1),
      isNull,
    );
  });

  test('the box can be padded away from the content', () {
    final padded = SelectionTransform.contentBox(
      [triangle()],
      const [],
      padding: 10,
    )!;
    final tight = SelectionTransform.contentBox([triangle()], const [])!;
    expect(padded.local.width, closeTo(tight.local.width + 20, 1e-9));
  });
}
