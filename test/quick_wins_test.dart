import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setUpAll(PencilShader.init);

  setUp(() {
    stows.lassoRectangle.value = false;
    stows.lassoSelectsLocked.value = false;
    stows.eraserErasesLocked.value = false;
    stows.highlighterStraight.value = 'hold';
  });

  Future<EditorState> open(WidgetTester tester, String name) async {
    FileManager.documentsDirectory =
        '$tmpDir/quick_wins_$name/${FileManager.appRootDirectoryPrefix}';
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

  Stroke line(EditorPage page, Offset a, Offset b) => Stroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 4),
    pageIndex: 0,
    page: page,
    toolId: .fountainPen,
  )..addPoints([a, b]);

  Select selectOnly(EditorState state, List<Stroke> strokes) {
    final select = Select.currentSelect
      ..selectResult = SelectResult(
        pageIndex: 0,
        strokes: List.of(strokes),
        images: [],
        path: Path()..addRect(const Rect.fromLTWH(0, 0, 900, 900)),
        pageIndexStart: 0,
      )
      ..doneSelecting = true;
    state.currentTool = select;
    return select;
  }

  /// Drags on the page from [from] to [to] with the current tool.
  void drag(EditorState state, Offset from, Offset to) {
    final page = state.coreInfo.pages.first;
    Offset global(Offset p) => page.renderBox!.localToGlobal(p);
    state.dragPageIndex = 0;
    state.onDrawStart(ScaleStartDetails(focalPoint: global(from)));
    for (int i = 1; i <= 6; i++) {
      state.onDrawUpdate(
        ScaleUpdateDetails(focalPoint: global(Offset.lerp(from, to, i / 6)!)),
      );
    }
    state.onDrawEnd(.new());
  }

  testWidgets('flipping mirrors the selection, and undo puts it back', (
    tester,
  ) async {
    final state = await open(tester, 'flip');
    final page = state.coreInfo.pages.first;
    final s = line(page, const Offset(100, 100), const Offset(300, 200));
    page.strokes.add(s);
    final select = selectOnly(state, [s]);
    state.flipSelection(horizontal: true);
    final flipped = select.selectResult.strokes.single;
    expect(flipped.points.first.dx, closeTo(300, 0.5));
    expect(flipped.points.last.dx, closeTo(100, 0.5));
    expect(flipped.points.first.dy, closeTo(100, 1e-6));
    state.undo();
    expect(page.strokes.single, same(s));
  });

  testWidgets('bring to front and send to back change the drawing order', (
    tester,
  ) async {
    final state = await open(tester, 'order');
    final page = state.coreInfo.pages.first;
    final a = line(page, const Offset(10, 10), const Offset(20, 20));
    final b = line(page, const Offset(30, 30), const Offset(40, 40));
    page.strokes.addAll([a, b]);
    selectOnly(state, [a]);
    state.reorderSelection(toFront: true);
    expect(page.strokes, [b, a]);
    state.reorderSelection(toFront: false);
    expect(page.strokes, [a, b]);
    state.undo();
    expect(page.strokes, [b, a]);
  });

  testWidgets("locked writing isn't selected or erased", (tester) async {
    final state = await open(tester, 'lock');
    final page = state.coreInfo.pages.first;
    final s = line(page, const Offset(200, 300), const Offset(400, 300));
    page.strokes.add(s);
    selectOnly(state, [s]);
    state.toggleLockSelection();
    expect(s.locked, isTrue);

    // The lasso goes right around it but doesn't pick it
    stows.lassoRectangle.value = true;
    state.currentTool = Select.currentSelect..unselect();
    drag(state, const Offset(150, 250), const Offset(450, 350));
    expect(Select.currentSelect.selectResult.strokes, isEmpty);

    // The eraser goes right over it
    state.currentTool = Eraser(size: 20);
    drag(state, const Offset(200, 300), const Offset(400, 300));
    expect(page.strokes, contains(s));

    stows.eraserErasesLocked.value = true;
    state.currentTool = Eraser(size: 20);
    drag(state, const Offset(200, 300), const Offset(400, 300));
    expect(page.strokes, isNot(contains(s)));
  });

  test('the rectangle lasso selects a box from where it started', () {
    stows.lassoRectangle.value = true;
    final select = Select.currentSelect
      ..onDragStart(const Offset(10, 10), 0)
      ..onDragUpdate(const Offset(50, 80))
      ..onDragUpdate(const Offset(100, 60));
    final bounds = select.selectResult.path.getBounds();
    expect(bounds, const Rect.fromLTRB(10, 10, 100, 60));
  });

  testWidgets('the highlighter can always draw straight lines', (tester) async {
    final state = await open(tester, 'highlighter');
    final page = state.coreInfo.pages.first;
    stows.highlighterStraight.value = 'always';
    state.currentTool = Highlighter.currentHighlighter;
    final pen = Highlighter.currentHighlighter;
    state.dragPageIndex = 0;
    pen.onDragStart(const Offset(100, 100), page, 0, null);
    pen.onDragUpdate(const Offset(150, 160), null);
    pen.onDragUpdate(const Offset(250, 90), null);
    pen.onDragUpdate(const Offset(300, 120), null);
    state.onDrawEnd(.new());
    final drawn = page.strokes.last;
    // A straight line keeps just its two ends (the end is repeated)
    expect(drawn.points.map((p) => (p.dx, p.dy)).toSet(), hasLength(2));
  });
}
