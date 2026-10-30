import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:sbn/tool_id.dart';

void main() {
  final page = EditorPage();

  Stroke line({ToolId toolId = .ballpointPen}) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 2, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: toolId,
  )..addPoints([for (int i = 0; i <= 100; i += 5) Offset(i.toDouble(), 0)]);

  group('eraseAround:', () {
    test('erasing the middle leaves two pieces', () {
      final pieces = line().eraseAround(const Offset(50, 0), 8)!;
      expect(pieces, hasLength(2));
      expect(pieces[0].centerline.last.dx, lessThan(42));
      expect(pieces[1].centerline.first.dx, greaterThan(58));
    });

    test('erasing an end leaves one piece', () {
      final pieces = line().eraseAround(Offset.zero, 8)!;
      expect(pieces, hasLength(1));
      expect(pieces.single.centerline.first.dx, greaterThan(8));
    });

    test('missing the stroke changes nothing', () {
      expect(line().eraseAround(const Offset(50, 40), 8), isNull);
    });

    test('a big eraser removes the whole stroke', () {
      expect(line().eraseAround(const Offset(50, 0), 200), isEmpty);
    });

    test('pieces keep colour, tool and thickness', () {
      final original = line()..color = Colors.red;
      final piece = original.eraseAround(const Offset(50, 0), 8)!.first;
      expect(piece.color, Colors.red);
      expect(piece.toolId, original.toolId);
      expect(piece.options.size, original.options.size);
    });

    test('a rectangle can be cut too', () {
      final rect = RectangleStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(0, 0, 100, 50),
      );
      // Erase the middle of the top side
      final pieces = rect.eraseAround(const Offset(50, 0), 5)!;
      expect(pieces, isNotEmpty);
      expect(pieces.every((p) => p is! RectangleStroke), isTrue);
    });
  });

  test('eraser targets', () {
    expect(EraserTarget.of(line()), EraserTarget.pen);
    expect(
      EraserTarget.of(line(toolId: .highlighter)),
      EraserTarget.highlighter,
    );
    expect(EraserTarget.of(line(toolId: .shapePen)), EraserTarget.shapes);
  });

  test('reversing a replace swaps removed and added', () {
    final a = line(), b = line();
    final reversed = HistoricReplace(removed: [a], added: [b]).reverse();
    expect(reversed.removed.single, same(b));
    expect(reversed.added.single, same(a));
  });
}
