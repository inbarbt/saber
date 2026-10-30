import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:sbn/change.dart';

void main() {
  final page = EditorPage();

  Stroke reload(Stroke stroke) => Stroke.fromJson(
    stroke.toJson(),
    fileVersion: EditorCoreInfo.sbnVersion,
    pageIndex: 0,
    page: page,
  );

  Stroke line() => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: .shapePen,
  )..addPoints(const [Offset.zero, Offset(100, 0)]);

  test('plain strokes save nothing extra', () {
    expect(line().styleJson, isEmpty);
    expect(reload(line()).hasStyle, isFalse);
  });

  test('a dashed line with an arrowhead survives save and load', () {
    final loaded = reload(
      line()
        ..dashed = true
        ..arrowEnd = true,
    );
    expect(loaded.dashed, isTrue);
    expect(loaded.arrowEnd, isTrue);
    expect(loaded.fillColor, isNull);
  });

  test('a filled rectangle and circle survive save and load', () {
    final rect = RectangleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    )..fillColor = const Color(0x40FF0000);
    final circle = CircleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
      center: const Offset(5, 5),
      radius: 5,
    )..dashed = true;

    final loadedRect = reload(rect);
    expect(loadedRect, isA<RectangleStroke>());
    expect(loadedRect.fillColor, const Color(0x40FF0000));
    final loadedCircle = reload(circle);
    expect(loadedCircle, isA<CircleStroke>());
    expect(loadedCircle.dashed, isTrue);
  });

  test('copies and transformed strokes keep their style', () {
    final styled = line()
      ..dashed = true
      ..arrowEnd = true;
    expect(styled.copy().dashed, isTrue);
    final turned = styled.transformed(
      SelectionTransform.rotateMatrix(Offset.zero, 30),
    );
    expect(turned.dashed, isTrue);
    expect(turned.arrowEnd, isTrue);
  });

  test('erased pieces keep dashes but not the arrowhead', () {
    final styled = line()
      ..dashed = true
      ..arrowEnd = true;
    final pieces = styled.eraseAround(const Offset(50, 0), 5)!;
    expect(pieces, isNotEmpty);
    expect(pieces.every((p) => p.dashed && !p.arrowEnd), isTrue);
  });

  test('reversing a style change swaps the styles', () {
    final stroke = line();
    const StrokeStyle before = (dashed: false, fill: null, arrow: false);
    const StrokeStyle after = (dashed: true, fill: null, arrow: true);
    final reversed = HistoricStyleChange(
      pageIndex: 0,
      styleChanges: {stroke: const Change(previous: before, current: after)},
    ).reverse();
    expect(reversed.styleChanges[stroke]!.previous, after);
    expect(reversed.styleChanges[stroke]!.current, before);
  });

  test('shapes keep their line thickness when resized', () {
    final stretch = SelectionTransform.resizeMatrix(
      const SelectionBox(Rect.fromLTWH(0, 0, 10, 10), 0),
      SelectionHandle.right,
      const Offset(30, 5),
      keepAspectRatio: false,
    );
    final rect = RectangleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
      rect: const Rect.fromLTWH(0, 0, 10, 10),
    );
    final resized = rect.transformed(stretch) as RectangleStroke;
    expect(resized.options.size, 3);
    expect(resized.rect, const Rect.fromLTWH(0, 0, 30, 10));

    final triangle = line()
      ..addPoints(const [Offset(50, 50), Offset.zero])
      ..crisp = true;
    expect(triangle.transformed(stretch).options.size, 3);

    // Handwriting still scales its thickness
    final handwriting = line()..crisp = false;
    expect(handwriting.transformed(stretch).options.size, isNot(3));
  });

  test('crisp survives save and load', () {
    expect(reload(line()..crisp = true).crisp, isTrue);
  });
}
