import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setUpAll(PencilShader.init);

  testWidgets('the S Pen button keys switch tools and kinds of notes', (
    tester,
  ) async {
    FileManager.documentsDirectory =
        '$tmpDir/air_actions/${FileManager.appRootDirectoryPrefix}';
    stows.lastTool.value = .fountainPen;
    Annotations.current.value = NoteKind.regular;
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();

    // One press: lasso, and back
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(state.currentTool, isA<Select>());
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(state.currentTool, isA<Pen>());

    // Double press: the next kind of note
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.pump();
    expect(Annotations.current.value, NoteKind.toSelf);
    Annotations.current.value = NoteKind.regular;
  });
}
