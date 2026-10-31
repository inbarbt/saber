import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/shape_library.dart';

void main() {
  const start = Offset.zero;
  const end = Offset(100, 60);

  List<Offset> outline(LibraryShape shape, {int corners = 6}) =>
      ShapeLibrary.outline(shape, start, end, corners: corners);

  test('auto has no outline', () {
    expect(outline(LibraryShape.auto), isEmpty);
  });

  test('closed shapes repeat their first point', () {
    for (final shape in LibraryShape.values) {
      if (shape == LibraryShape.auto ||
          shape == LibraryShape.line ||
          shape == LibraryShape.arrow) {
        continue;
      }
      final points = outline(shape);
      expect(
        (points.first - points.last).distance,
        lessThan(1e-6),
        reason: '$shape',
      );
    }
  });

  test('every shape fits in the dragged box', () {
    final box = Rect.fromPoints(start, end).inflate(1e-6);
    for (final shape in LibraryShape.values) {
      for (final point in outline(shape)) {
        expect(box.contains(point), isTrue, reason: '$shape $point');
      }
    }
  });

  test('corner counts', () {
    int corners(LibraryShape shape, {int n = 6}) =>
        outline(shape, corners: n).length - 1;
    expect(corners(LibraryShape.triangle), 3);
    expect(corners(LibraryShape.rightTriangle), 3);
    expect(corners(LibraryShape.rhombus), 4);
    expect(corners(LibraryShape.parallelogram), 4);
    expect(corners(LibraryShape.trapezoid), 4);
    expect(corners(LibraryShape.star), 10);
    expect(corners(LibraryShape.polygon, n: 8), 8);
    expect(corners(LibraryShape.polygon, n: 50), ShapeLibrary.maxCorners);
  });

  test('lines follow the drag direction', () {
    final points = ShapeLibrary.outline(
      LibraryShape.line,
      const Offset(100, 0),
      const Offset(0, 100),
    );
    expect(points, const [Offset(100, 0), Offset(0, 100)]);
  });

  test('the drawn shape is a clean, editable shape in the pen colour', () {
    final raw = Stroke(
      color: Colors.red,
      pressureEnabled: true,
      options: StrokeOptions(size: 4),
      pageIndex: 0,
      page: EditorPage(),
      toolId: .shapePen,
    )..addPoints(const [start, Offset(40, 30), end]);
    final triangle = ShapeLibrary.strokeFor(raw, LibraryShape.triangle);
    expect(triangle.crisp, isTrue);
    expect(triangle.vertices, hasLength(3));
    expect(triangle.color.toARGB32(), Colors.red.toARGB32());
    expect(triangle.options.size, 4);

    final arrow = ShapeLibrary.strokeFor(raw, LibraryShape.arrow);
    expect(arrow.arrowEnd, isTrue);
    expect(arrow.vertices, hasLength(2));
  });
}
