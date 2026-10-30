import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/change.dart';

void main() {
  test('reversing a thickness change swaps previous and current', () {
    final stroke = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: EditorPage(),
      toolId: .ballpointPen,
    );
    final change = HistoricSizeChange(
      pageIndex: 0,
      sizeChanges: {stroke: const Change(previous: 3, current: 8)},
    );
    final reversed = change.reverse();
    expect(reversed.sizeChanges[stroke]!.previous, 8);
    expect(reversed.sizeChanges[stroke]!.current, 3);
  });
}
