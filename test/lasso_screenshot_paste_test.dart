import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/stroke_clipboard.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setUpAll(PencilShader.init);
  tearDown(StrokeClipboard.clear);

  testWidgets('a lasso screenshot pastes in the middle of the screen', (
    tester,
  ) async {
    stows.lassoRectangle.value = false;
    FileManager.documentsDirectory =
        '$tmpDir/lasso_paste/${FileManager.appRootDirectoryPrefix}';
    stows.lastTool.value = .fountainPen;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();

    final page = state.coreInfo.pages.first;
    page.insertStroke(
      Stroke(
        color: Colors.black,
        pressureEnabled: false,
        options: StrokeOptions(size: 4),
        pageIndex: 0,
        page: page,
        toolId: .fountainPen,
      )..addPoints([const Offset(500, 500), const Offset(700, 700)]),
    );

    // A lasso around an empty corner, ending where it started.
    state.currentTool = Select.currentSelect;
    Offset global(Offset p) => page.renderBox!.localToGlobal(p);
    const corners = [
      Offset(100, 100),
      Offset(300, 100),
      Offset(300, 300),
      Offset(100, 300),
      Offset(100, 100),
    ];
    state.dragPageIndex = 0;
    state.onDrawStart(ScaleStartDetails(focalPoint: global(corners.first)));
    for (final p in corners.skip(1)) {
      state.onDrawUpdate(ScaleUpdateDetails(focalPoint: global(p)));
    }
    state.onDrawEnd(.new());
    await tester.pump();
    expect(find.byIcon(Icons.screenshot), findsOneWidget);

    await tester.runAsync(state.screenshotLasso);
    await tester.pumpAndSettle();
    expect(StrokeClipboard.screenshot, isNotNull);

    state.pasteFromStrokeClipboard();
    await tester.pumpAndSettle();
    expect(page.images, hasLength(1));
    expect(find.byType(CanvasImage), findsOneWidget);

    final pasted = page.images.single.dstRect;
    expect(pasted.size, const Size(200, 200));
    expect(pasted.overlaps(const Rect.fromLTRB(100, 100, 300, 300)), isFalse);

    // let the snackbars and autosave timers finish
    state.cancelAutosaveAndMarkSaved();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
