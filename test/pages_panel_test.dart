import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/components/toolbar/pages_panel.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setUpAll(PencilShader.init);

  testWidgets('the pages button opens the panel; a bookmark can be added', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/pages_panel/${FileManager.appRootDirectoryPrefix}';
    stows.lastTool.value = .fountainPen;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(t.editor.pages));
    await tester.pumpAndSettle();
    expect(find.byType(PagesPanel), findsOneWidget);

    await tester.tap(find.text(t.editor.outline.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.editor.outline.addBookmark));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Chapter 1');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(state.coreInfo.pages.first.outline.single.title, 'Chapter 1');
    expect(find.text('Chapter 1'), findsOneWidget);
  });
}
