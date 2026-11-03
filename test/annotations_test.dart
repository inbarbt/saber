import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  final page = EditorPage();

  Stroke line(Offset from, Offset to) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3),
    pageIndex: 0,
    page: page,
    toolId: .fountainPen,
  )..addPoints([from, to]);

  group('grouping', () {
    test('strokes written together form one note', () {
      final annotations = <Annotation>[];
      final strokes = <Stroke>[];
      for (int i = 0; i < 3; i++) {
        final s = line(
          Offset(100.0 + i * 30, 100),
          Offset(120.0 + i * 30, 120),
        );
        Annotations.assign(
          s,
          NoteKind.toSelf,
          annotations: annotations,
          pageStrokes: strokes,
          now: 1000 + i * 2000,
        );
        strokes.add(s);
      }
      expect(annotations, hasLength(1));
      expect(strokes.map((s) => s.noteGroup).toSet(), {annotations.single.id});
    });

    test('a stroke far away starts a new note', () {
      final annotations = <Annotation>[];
      final a = line(const Offset(100, 100), const Offset(120, 120));
      final b = line(const Offset(100, 900), const Offset(120, 920));
      Annotations.assign(
        a,
        NoteKind.general,
        annotations: annotations,
        pageStrokes: [],
        now: 0,
      );
      Annotations.assign(
        b,
        NoteKind.general,
        annotations: annotations,
        pageStrokes: [a],
        now: 1000,
      );
      expect(annotations, hasLength(2));
      expect(a.noteGroup, isNot(b.noteGroup));
    });

    test('a stroke much later starts a new note', () {
      final annotations = <Annotation>[];
      final a = line(const Offset(100, 100), const Offset(120, 120));
      final b = line(const Offset(130, 100), const Offset(150, 120));
      Annotations.assign(
        a,
        NoteKind.toSelf,
        annotations: annotations,
        pageStrokes: [],
        now: 0,
      );
      Annotations.assign(
        b,
        NoteKind.toSelf,
        annotations: annotations,
        pageStrokes: [a],
        now: Annotations.joinTime.inMilliseconds + 1,
      );
      expect(annotations, hasLength(2));
    });

    test('regular writing belongs to no note', () {
      final s = line(Offset.zero, const Offset(10, 10));
      Annotations.assign(
        s,
        NoteKind.regular,
        annotations: [],
        pageStrokes: [],
        now: 0,
      );
      expect(s.noteKind, NoteKind.regular);
      expect(s.noteGroup, isNull);
    });

    test('classifying a selection makes one note of it', () {
      final annotations = <Annotation>[];
      final strokes = [
        line(Offset.zero, const Offset(10, 10)),
        line(const Offset(500, 500), const Offset(510, 510)),
      ];
      final note = Annotations.classify(
        strokes,
        NoteKind.general,
        annotations: annotations,
        now: 5,
      );
      expect(note, isNotNull);
      expect(strokes.every((s) => s.noteGroup == note!.id), isTrue);
    });
  });

  test('a stroke keeps its kind and note when saved', () {
    final s = line(Offset.zero, const Offset(10, 10))
      ..noteKind = NoteKind.toSelf
      ..noteGroup = 3;
    final loaded = Stroke.fromJson(
      s.toJson(),
      fileVersion: 19,
      pageIndex: 0,
      page: page,
    );
    expect(loaded.noteKind, NoteKind.toSelf);
    expect(loaded.noteGroup, 3);
  });

  test('only notes that still have strokes are saved with the page', () {
    final p = EditorPage();
    final s = line(Offset.zero, const Offset(10, 10))
      ..noteKind = NoteKind.general
      ..noteGroup = 1;
    p.strokes.add(s);
    p.annotations.addAll([
      Annotation(id: 1, kind: NoteKind.general, createdAt: 1, name: 'Parseval'),
      Annotation(id: 2, kind: NoteKind.toSelf, createdAt: 2),
    ]);
    final json = p.toJson(OrderedAssetCache());
    final loaded = EditorPage.fromJson(
      json,
      inlineAssets: null,
      readOnly: false,
      fileVersion: 19,
      sbnPath: '/t',
      assetCache: AssetCache(),
    );
    expect(loaded.annotations.single.name, 'Parseval');
  });

  test('layers can be hidden and shown', () {
    stows.hiddenNoteKinds.value = [];
    Annotations.setShown(NoteKind.toSelf, false);
    expect(Annotations.isShown(NoteKind.toSelf), isFalse);
    expect(Annotations.isShown(NoteKind.general), isTrue);
    Annotations.setShown(NoteKind.toSelf, true);
    expect(Annotations.isShown(NoteKind.toSelf), isTrue);
  });

  group('in the editor', () {
    setUpAll(PencilShader.init);
    setUp(() {
      stows.hiddenNoteKinds.value = [];
      Annotations.current.value = NoteKind.regular;
    });

    Future<EditorState> open(WidgetTester tester, String name) async {
      FileManager.documentsDirectory =
          '$tmpDir/annotations_$name/${FileManager.appRootDirectoryPrefix}';
      stows.lastTool.value = .fountainPen;
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Editor()));
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('the notes button switches what new writing is', (
      tester,
    ) async {
      final state = await open(tester, 'button');
      await tester.tap(
        find.byTooltip(
          t.editor.notes.writingAs(kind: noteKindLabel(NoteKind.regular)),
        ),
      );
      await tester.pumpAndSettle();
      expect(Annotations.current.value, NoteKind.toSelf);

      final page = state.coreInfo.pages.first;
      final pen = state.currentTool as Pen;
      state.dragPageIndex = 0;
      pen.onDragStart(const Offset(200, 200), page, 0, null);
      pen.onDragUpdate(const Offset(260, 230), null);
      pen.onDragUpdate(const Offset(320, 210), null);
      state.onDrawEnd(.new());
      await tester.pumpAndSettle();

      final written = page.strokes.last;
      expect(written.noteKind, NoteKind.toSelf);
      expect(page.annotations.single.id, written.noteGroup);
    });

    testWidgets('classifying a selection can be undone', (tester) async {
      final state = await open(tester, 'classify');
      final page = state.coreInfo.pages.first;
      final s = line(const Offset(200, 300), const Offset(300, 320));
      page.strokes.add(s);
      final select = Select.currentSelect
        ..selectResult = SelectResult(
          pageIndex: 0,
          strokes: [s],
          images: [],
          path: Path()..addRect(const Rect.fromLTWH(150, 250, 200, 100)),
          pageIndexStart: 0,
        )
        ..doneSelecting = true;
      state.currentTool = select;

      state.classifySelection(NoteKind.general);
      expect(s.noteKind, NoteKind.general);
      state.undo();
      expect(s.noteKind, NoteKind.regular);
    });
  });
}
