import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/outline.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:sbn/tool_id.dart';

void main() {
  FlavorConfig.setup();

  EditorCoreInfo note() {
    final info = EditorCoreInfo(filePath: '/roundtrip');
    final page = EditorPage();
    info.pages.add(page);
    Stroke pen() => Stroke(
      color: Colors.black,
      pressureEnabled: true,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .fountainPen,
    )..addPoints(const [Offset(10, 10), Offset(50, 60), Offset(90, 20)]);
    page.strokes.addAll([
      pen(),
      pen()
        ..noteKind = NoteKind.toSelf
        ..noteGroup = 1
        ..locked = true,
      ShapeLibrary.strokeFor(pen(), LibraryShape.trapezoid)..dashed = true,
      ShapeLibrary.strokeFor(pen(), LibraryShape.line),
      CircleStroke(
        color: Colors.red,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        center: const Offset(200, 200),
        radius: 40,
      )..fillColor = Colors.blue,
      RectangleStroke(
        color: Colors.green,
        pressureEnabled: false,
        options: StrokeOptions(size: 2),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        rect: const Rect.fromLTWH(300, 300, 80, 40),
      ),
      GraphStroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 3),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        frame: const Rect.fromLTWH(100, 400, 200, 200),
        spec: const GraphSpec(formula: 'sin(x)'),
      ),
    ]);
    page.annotations.add(
      Annotation(
        id: 1,
        kind: NoteKind.toSelf,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        name: 'check',
      ),
    );
    page.outline.add(OutlineEntry(title: 'Chapter', level: 0));
    info.pages.add(EditorPage());
    return info;
  }

  Future<EditorCoreInfo> reload(Uint8List bson) =>
      EditorCoreInfo.loadFromFileContents(
        bsonBytes: bson,
        path: '/roundtrip',
        onlyFirstPage: false,
      );

  test('a saved note opens again with everything in it', () async {
    final original = note();
    final createdAt = original.pages.first.annotations.single.createdAt;
    final (first, _) = original.saveToBinary(currentPageIndex: 0);

    final loaded = await reload(first);
    expect(loaded.readOnly, isFalse, reason: 'the note must open');
    expect(loaded.pages, hasLength(2));
    expect(loaded.pages.first.strokes, hasLength(7));
    final annotation = loaded.pages.first.annotations.single;
    expect(annotation.name, 'check');
    expect(annotation.kind, NoteKind.toSelf);
    expect(annotation.createdAt, createdAt);
    expect(loaded.pages.first.outline.single.title, 'Chapter');

    // Saving what was loaded and opening it again changes nothing
    final (second, _) = loaded.saveToBinary(currentPageIndex: 0);
    final again = await reload(second);
    expect(again.readOnly, isFalse);
    expect(again.pages.first.strokes, hasLength(7));
    expect(again.pages.first.annotations.single.createdAt, createdAt);
    final (third, _) = again.saveToBinary(currentPageIndex: 0);
    expect(third.length, second.length);
  });

  test(
    'an annotation that cannot be read does not stop the note opening',
    () async {
      final json = {
        'v': EditorCoreInfo.sbnVersion,
        'z': [
          {
            'w': 1000.0,
            'h': 1400.0,
            'an': [
              {'id': 1, 'k': 1, 'n': 42},
            ],
          },
        ],
      };
      final loaded = EditorCoreInfo.fromJson(
        json,
        filePath: '/roundtrip',
        onlyFirstPage: false,
      );
      expect(loaded.pages, hasLength(1));
      expect(loaded.pages.first.annotations, isEmpty);
    },
  );

  test('the drawing order survives a save and load', () async {
    final original = note();
    final page = original.pages.first;
    // Move the first pen stroke to the front, over the shapes
    page.strokes.add(page.strokes.removeAt(0));
    final highlighter = Stroke(
      color: Colors.yellow,
      pressureEnabled: false,
      options: StrokeOptions(size: 20),
      pageIndex: 0,
      page: page,
      toolId: .highlighter,
    )..addPoints(const [Offset.zero, Offset(100, 0)]);
    page.strokes.insert(3, highlighter);
    final order = [
      for (final s in page.strokes)
        if (s.toolId != .highlighter) s.toJson()['shape'] ?? s.toolId.id,
    ];

    final (bson, _) = original.saveToBinary(currentPageIndex: 0);
    final loaded = (await reload(bson)).pages.first.strokes;
    expect(loaded.first.toolId, ToolId.highlighter);
    expect([
      for (final s in loaded.skip(1)) s.toJson()['shape'] ?? s.toolId.id,
    ], order);
    expect(loaded.last.toolId, ToolId.fountainPen);
  });
}
