import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/editor/stroke_clipboard.dart';
import 'package:saber/data/flavor_config.dart';

void main() {
  FlavorConfig.setup();
  setUp(StrokeClipboard.clear);

  final pageA = EditorPage();
  final pageB = EditorPage();

  Stroke line(EditorPage page) => Stroke(
    color: Colors.blue,
    pressureEnabled: false,
    options: StrokeOptions(size: 6, isComplete: true),
    pageIndex: 0,
    page: page,
    toolId: .ballpointPen,
  )..addPoints(const [Offset(10, 10), Offset(50, 30), Offset(90, 10)]);

  test('starts empty', () {
    expect(StrokeClipboard.isEmpty, isTrue);
  });

  test('pasted strokes are new copies on the target page', () {
    final original = line(pageA);
    StrokeClipboard.copy(
      strokes: [original],
      images: const [],
      filePath: '/a',
      pageIndex: 0,
    );
    final pasted = StrokeClipboard.strokesFor(pageIndex: 3, page: pageB);
    expect(pasted, hasLength(1));
    final copy = pasted.single;
    expect(identical(copy, original), isFalse);
    expect(copy.pageIndex, 3);
    expect(identical(copy.page, pageB), isTrue);
    expect(copy.color.toARGB32(), Colors.blue.toARGB32());
    expect(copy.options.size, 6);
    expect(copy.centerline.first.dx, closeTo(10, 1e-3));
  });

  test('editing the original after copying does not change the clipboard', () {
    final original = line(pageA);
    StrokeClipboard.copy(
      strokes: [original],
      images: const [],
      filePath: '/a',
      pageIndex: 0,
    );
    original.shift(const Offset(100, 100));
    final copy = StrokeClipboard.strokesFor(pageIndex: 0, page: pageA).single;
    expect(copy.centerline.first.dx, closeTo(10, 1e-3));
  });

  test('shapes paste as shapes', () {
    final rect = RectangleStroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 4),
      pageIndex: 0,
      page: pageA,
      toolId: .shapePen,
      rect: const Rect.fromLTWH(5, 5, 20, 10),
    );
    StrokeClipboard.copy(
      strokes: [rect],
      images: const [],
      filePath: '/a',
      pageIndex: 0,
    );
    final pasted = StrokeClipboard.strokesFor(pageIndex: 1, page: pageB).single;
    expect(pasted, isA<RectangleStroke>());
    expect((pasted as RectangleStroke).rect, const Rect.fromLTWH(5, 5, 20, 10));
  });

  test(
    'pasting onto the same page shifts the copy; elsewhere it stays put',
    () {
      StrokeClipboard.copy(
        strokes: [line(pageA)],
        images: const [],
        filePath: '/a',
        pageIndex: 2,
      );
      expect(
        StrokeClipboard.pasteOffset(filePath: '/a', pageIndex: 2),
        isNot(Offset.zero),
      );
      expect(
        StrokeClipboard.pasteOffset(filePath: '/a', pageIndex: 3),
        Offset.zero,
      );
      expect(
        StrokeClipboard.pasteOffset(filePath: '/b', pageIndex: 2),
        Offset.zero,
      );
    },
  );

  test('images only paste into the note they came from', () {
    StrokeClipboard.copy(
      strokes: const [],
      images: const [],
      filePath: '/a',
      pageIndex: 0,
    );
    expect(StrokeClipboard.hasImagesFor('/a'), isFalse);
    expect(
      StrokeClipboard.imagesFor(
        filePath: '/b',
        pageIndex: 0,
        nextImageId: () => 0,
      ),
      isEmpty,
    );
  });
}
