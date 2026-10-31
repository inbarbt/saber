import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/snap.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setUpAll(PencilShader.init);

  Future<EditorState> openEditor(WidgetTester tester, String name) async {
    FileManager.documentsDirectory =
        '$tmpDir/shape_editing_$name/${FileManager.appRootDirectoryPrefix}';
    stows.lastTool.value = .fountainPen;
    stows.snapToShapes.value = true;
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Editor()));
    final state = tester.state<EditorState>(find.byType(Editor));
    addTearDown(state.cancelAutosaveAndMarkSaved);
    await tester.pumpAndSettle();
    return state;
  }

  Stroke libraryShape(EditorState state, LibraryShape kind, Rect r) {
    final page = state.coreInfo.pages.first;
    final raw = Stroke(
      color: Colors.black,
      pressureEnabled: false,
      options: StrokeOptions(size: 3),
      pageIndex: 0,
      page: page,
      toolId: .shapePen,
    )..addPoints([r.topLeft, r.bottomRight]);
    final shape = ShapeLibrary.strokeFor(raw, kind);
    page.strokes.add(shape);
    return shape;
  }

  testWidgets('tapping a shape with the shapes tool selects it', (
    tester,
  ) async {
    final state = await openEditor(tester, 'tap');
    final page = state.coreInfo.pages.first;
    final rect = libraryShape(
      state,
      .rectangle,
      const Rect.fromLTWH(100, 100, 200, 100),
    );
    final shapePen = ShapePen();
    state.currentTool = shapePen;
    state.dragPageIndex = 0;
    shapePen.onDragStart(const Offset(200, 101), page, 0, null);
    state.onDrawEnd(.new());
    await tester.pumpAndSettle();

    expect(state.currentTool, isA<Select>());
    expect(Select.currentSelect.selectResult.strokes.single, same(rect));
    expect(page.strokes, hasLength(1)); // no dot was added
  });

  testWidgets("a line's end snaps onto another shape's corner", (tester) async {
    final state = await openEditor(tester, 'vertex');
    final page = state.coreInfo.pages.first;
    libraryShape(state, .rectangle, const Rect.fromLTWH(300, 100, 100, 100));
    final line = libraryShape(
      state,
      .line,
      const Rect.fromLTRB(100, 300, 200, 300),
    );

    final select = Select.currentSelect;
    select.selectResult = SelectResult(
      pageIndex: 0,
      strokes: [line],
      images: [],
      path: Path()..addRect(const Rect.fromLTRB(90, 290, 210, 310)),
      pageIndexStart: 0,
    );
    select.doneSelecting = true;
    state.currentTool = select;
    // ignore: invalid_use_of_protected_member
    state.setState(() {});
    await tester.pumpAndSettle();

    Offset global(Offset p) => page.renderBox!.localToGlobal(p);
    state.dragPageIndex = 0;
    state.onDrawStart(
      ScaleStartDetails(focalPoint: global(const Offset(200, 300))),
    );
    state.onDrawUpdate(
      ScaleUpdateDetails(focalPoint: global(const Offset(304, 205))),
    );
    expect(Snap.guides, isNotEmpty);
    state.onDrawEnd(.new());
    await tester.pumpAndSettle();

    final edited = select.selectResult.strokes.single;
    expect(edited.vertices.last.dx, closeTo(300, 1e-6));
    expect(edited.vertices.last.dy, closeTo(200, 1e-6));
    expect(Snap.guides, isEmpty);
  });
}
