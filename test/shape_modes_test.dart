import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_constraints.dart';
import 'package:saber/data/tools/shape_library.dart';

void main() {
  FlavorConfig.setup();
  final page = EditorPage();

  Stroke raw(List<Offset> points) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3),
    pageIndex: 0,
    page: page,
    toolId: .fountainPen,
  )..addPoints(points);

  Stroke library(LibraryShape kind) => ShapeLibrary.strokeFor(
    raw(const [Offset(100, 100), Offset(300, 220)]),
    kind,
  );

  test('a straightened line has just its two ends', () {
    final line = raw(const [Offset(0, 0), Offset(40, 3), Offset(100, 1)])
      ..convertToLine()
      ..crisp = true;
    expect(line.vertices, hasLength(2));
  });

  test('a line always shows its ends, never a box', () {
    final line = library(.line);
    expect(
      SelectionTransform.isEditingShape([line], const [], editShape: false),
      isTrue,
    );
    expect(SelectionTransform.canEditShape([line], const []), isFalse);
  });

  test('other shapes switch between shape editing and the box', () {
    final rect = library(.rectangle);
    expect(SelectionTransform.canEditShape([rect], const []), isTrue);
    expect(
      SelectionTransform.editableVertices([rect], const [], editShape: false),
      isEmpty,
    );
    expect(
      SelectionTransform.editableVertices([rect], const [], editShape: true),
      hasLength(4),
    );
  });

  test('several strokes are always moved as a box', () {
    final a = library(.rectangle), b = library(.triangle);
    expect(SelectionTransform.canEditShape([a, b], const []), isFalse);
    expect(
      SelectionTransform.isEditingShape([a, b], const [], editShape: true),
      isFalse,
    );
  });

  test('sides that can move, per shape', () {
    expect(ShapeConstraints.movableSides(.rectangle, 4), [0, 1, 2, 3]);
    expect(ShapeConstraints.movableSides(.trapezoid, 4), [0, 2]);
    expect(ShapeConstraints.movableSides(.rightTriangle, 3), [0, 1]);
    expect(ShapeConstraints.movableSides(.rhombus, 4), isEmpty);
    expect(ShapeConstraints.movableSides(.polygon, 6), isEmpty);
  });

  test('moving a side keeps it parallel and moves it straight out', () {
    final rect = library(.rectangle).vertices; // TL TR BR BL
    final moved = ShapeConstraints.moveSide(rect, 1, const Offset(50, 30));
    // The right side moves right by 50; the slant of the drag is ignored
    expect(moved[1], rect[1] + const Offset(50, 0));
    expect(moved[2], rect[2] + const Offset(50, 0));
    expect(moved[0], rect[0]);
    for (int i = 0; i < 4; i++) {
      expect(ShapeConstraints.angleAt(moved, i), closeTo(90, 1e-6));
    }
  });

  test("a trapezoid's top moves up and stays parallel to the base", () {
    final t = library(.trapezoid).vertices; // top 0-1, base 2-3
    final moved = ShapeConstraints.moveSide(t, 0, const Offset(10, -40));
    expect(moved[0].dy, t[0].dy - 40);
    expect(moved[1].dy, t[1].dy - 40);
    expect(moved[2], t[2]);
  });

  test('side handles sit in the middle of movable sides', () {
    final rect = library(.rectangle);
    final handles = SelectionTransform.sideHandles(
      [rect],
      const [],
      editShape: true,
    );
    expect(handles, hasLength(4));
    expect(handles.first.$2, const Offset(200, 100));
    expect(
      SelectionTransform.sideHandles([rect], const [], editShape: false),
      isEmpty,
    );
  });
}
