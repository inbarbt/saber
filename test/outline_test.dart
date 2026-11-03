import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/components/toolbar/pages_panel.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/outline.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/i18n/strings.g.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  BackgroundIsolateBinaryMessenger.ensureInitialized(
    ServicesBinding.rootIsolateToken!,
  );
  setupMockPathProvider();
  setupMockPrinting();
  FlavorConfig.setup();
  setUpAll(() => Future.wait([FileManager.init(), PencilShader.init()]));

  EditorPage reload(EditorPage page) => EditorPage.fromJson(
    jsonDecode(jsonEncode(page.toJson(OrderedAssetCache())))
        as Map<String, dynamic>,
    inlineAssets: null,
    readOnly: false,
    fileVersion: 19,
    sbnPath: '/test',
    assetCache: AssetCache(),
  );

  test('bookmarks are saved with their page', () {
    final page = EditorPage()
      ..outline.addAll([
        OutlineEntry(title: 'Chapter 1'),
        OutlineEntry(title: 'Section 1.1', level: 1),
      ]);
    final loaded = reload(page);
    expect(loaded.outline.map((e) => e.title), ['Chapter 1', 'Section 1.1']);
    expect(loaded.outline.map((e) => e.level), [0, 1]);
  });

  test('a page with only a bookmark is not empty', () {
    expect(EditorPage().isEmpty, isTrue);
    expect(
      (EditorPage()..outline.add(OutlineEntry(title: 'x'))).isEmpty,
      isFalse,
    );
  });

  test('nesting stays within limits when loading', () {
    final entry = OutlineEntry.fromJson({'t': 'deep', 'l': 99});
    expect(entry.level, OutlineEntry.maxLevel);
  });

  test('entries are listed in page order', () {
    final pages = [
      EditorPage()..outline.add(OutlineEntry(title: 'a')),
      EditorPage(),
      EditorPage()
        ..outline.addAll([
          OutlineEntry(title: 'b'),
          OutlineEntry(title: 'c', level: 1),
        ]),
    ];
    final entries = OutlineView.entriesOf(pages);
    expect(entries.map((e) => e.entry.title), ['a', 'b', 'c']);
    expect(entries.map((e) => e.pageIndex), [0, 2, 2]);
  });

  test("a PDF's own contents become nested lines with pages", () {
    const dest = PdfDestCommand.xyz;
    final nodes = [
      const PdfOutlineNode(
        title: 'Part A',
        dest: PdfDest(1, dest, null),
        children: [
          PdfOutlineNode(
            title: 'A.1',
            dest: PdfDest(3, dest, null),
            children: [],
          ),
        ],
      ),
      const PdfOutlineNode(title: 'No page', dest: null, children: []),
    ];
    final lines = OutlineView.flattenPdfOutline(nodes, (n) => n - 1);
    expect(lines.map((l) => l.title), ['Part A', 'A.1', 'No page']);
    expect(lines.map((l) => l.level), [0, 1, 0]);
    expect(lines.map((l) => l.pageIndex), [0, 2, null]);
  });

  test('undoing a change brings the old entries back', () {
    final change = HistoricOutlineChange(
      pageIndex: 0,
      before: [OutlineEntry(title: 'old')],
      after: [OutlineEntry(title: 'new')],
    );
    final reversed = change.reverse();
    expect(reversed.before.single.title, 'new');
    expect(reversed.after.single.title, 'old');
  });

  testWidgets('bookmarks become the contents of an exported PDF', (
    tester,
  ) async {
    final coreInfo = EditorCoreInfo(filePath: '/tests/outline_export')
      ..pages.addAll([
        EditorPage()..outline.add(OutlineEntry(title: 'Fourier series')),
        EditorPage()..outline.add(OutlineEntry(title: 'Parseval', level: 1)),
      ]);
    final completer = Completer<BuildContext>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              if (!completer.isCompleted) completer.complete(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final context = await completer.future;
    await tester.runAsync(() async {
      final doc = await EditorExporter.generatePdf(coreInfo, context);
      final bytes = await doc.save();
      final text = latin1.decode(bytes);
      expect(text, contains('/Outlines'));
      expect(text, contains('Fourier series'));
      expect(text, contains('Parseval'));
    });
  });

  testWidgets('named notes become entries in the exported contents', (
    tester,
  ) async {
    final page = EditorPage();
    page.strokes.add(
      Stroke(
          color: Colors.black,
          pressureEnabled: false,
          options: StrokeOptions(size: 3, isComplete: true),
          pageIndex: 0,
          page: page,
          toolId: .fountainPen,
        )
        ..addPoints(const [Offset(100, 100), Offset(200, 120)])
        ..noteKind = NoteKind.general
        ..noteGroup = 1,
    );
    page.annotations.add(
      Annotation(
        id: 1,
        kind: NoteKind.general,
        createdAt: 0,
        name: 'Why it works',
      ),
    );
    final coreInfo = EditorCoreInfo(filePath: '/tests/notes_export')
      ..pages.add(page);
    final completer = Completer<BuildContext>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              if (!completer.isCompleted) completer.complete(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final context = await completer.future;
    await tester.runAsync(() async {
      final doc = await EditorExporter.generatePdf(coreInfo, context);
      final text = latin1.decode(await doc.save());
      expect(text, contains('Why it works'));
    });
  });
}
