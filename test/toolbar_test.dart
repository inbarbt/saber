import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/components/toolbar/color_grid.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/selection_menu_layout.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/color_presets.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();

  group('ColorPresets', () {
    setUp(() {
      stows.presetColorsPen.value = [];
      stows.presetColorsHighlighter.value = [];
    });

    test('five defaults per tool', () {
      for (final kind in PresetKind.values) {
        expect(ColorPresets.colorsFor(kind), hasLength(ColorPresets.count));
      }
    });

    test('replacing one keeps the others', () {
      final before = ColorPresets.colorsFor(.pen);
      ColorPresets.replace(.pen, 2, Colors.teal);
      final after = ColorPresets.colorsFor(.pen);
      expect(after[2].toARGB32(), Colors.teal.toARGB32());
      expect(after[0], before[0]);
      expect(after[4], before[4]);
      expect(ColorPresets.colorsFor(.highlighter)[2], isNot(Colors.teal));
    });

    test("the highlighter's transparency doesn't hide a match", () {
      final yellow = ColorPresets.colorsFor(.highlighter)[0];
      expect(
        ColorPresets.indexOf(.highlighter, yellow.withAlpha(Highlighter.alpha)),
        0,
      );
      expect(ColorPresets.indexOf(.highlighter, Colors.brown), isNull);
    });

    test('tools map to their own colors', () {
      expect(ColorPresets.kindFor(Pen.fountainPen()), PresetKind.pen);
      expect(ColorPresets.kindFor(Pencil()), PresetKind.pen);
      expect(ColorPresets.kindFor(Highlighter()), PresetKind.highlighter);
      expect(ColorPresets.kindFor(ShapePen()), PresetKind.shape);
      expect(ColorPresets.kindFor(Select.currentSelect), PresetKind.pen);
    });
  });

  group('SelectionMenuLayout', () {
    const screen = Size(800, 600);
    const menu = Size(300, 48);

    test('sits centred above the selection', () {
      const anchor = Rect.fromLTWH(300, 300, 200, 100);
      final pos = const SelectionMenuLayout(anchor)
          .getPositionForChild(screen, menu);
      expect(pos.dx, 400 - menu.width / 2);
      expect(pos.dy + menu.height, lessThan(anchor.top));
    });

    test('goes below when there is no room above', () {
      const anchor = Rect.fromLTWH(300, 10, 200, 100);
      final pos = const SelectionMenuLayout(anchor)
          .getPositionForChild(screen, menu);
      expect(pos.dy, greaterThan(anchor.bottom));
    });

    test('stays on screen at the edge', () {
      const anchor = Rect.fromLTWH(-100, 300, 120, 100);
      final pos = const SelectionMenuLayout(anchor)
          .getPositionForChild(screen, menu);
      expect(pos.dx, SelectionMenuLayout.margin);
    });
  });

  group('toolbar in the editor', () {
    setUpAll(PencilShader.init);

    Future<EditorState> openEditor(WidgetTester tester, String name) async {
      FileManager.documentsDirectory =
          '$tmpDir/toolbar_$name/${FileManager.appRootDirectoryPrefix}';
      stows.lastTool.value = .fountainPen;
      stows.presetColorsPen.value = [];
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Editor()));
      final state = tester.state<EditorState>(find.byType(Editor));
      addTearDown(state.cancelAutosaveAndMarkSaved);
      await tester.pumpAndSettle();
      return state;
    }

    Finder presetButtons() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_PresetColorButton',
    );

    testWidgets('a second tap on the pen opens its panel; '
        'a tap on the page closes it', (tester) async {
      await openEditor(tester, 'panel');
      expect(find.byType(PenModal), findsNothing);

      await tester.tap(find.byTooltip(t.editor.toolbar.pen));
      await tester.pumpAndSettle();
      expect(find.byType(PenModal), findsOneWidget);

      await tester.tapAt(const Offset(800, 400));
      await tester.pumpAndSettle();
      expect(find.byType(PenModal), findsNothing);
    });

    testWidgets('five colors next to the pen; a tap sets the color', (
      tester,
    ) async {
      final state = await openEditor(tester, 'presets');
      expect(presetButtons(), findsNWidgets(ColorPresets.count));

      await tester.tap(presetButtons().at(2));
      await tester.pumpAndSettle();
      expect(
        (state.currentTool as Pen).color.toARGB32(),
        ColorPresets.colorsFor(.pen)[2].toARGB32(),
      );
    });

    testWidgets('a long press on a color opens the color picker', (
      tester,
    ) async {
      await openEditor(tester, 'longpress');
      await tester.longPress(presetButtons().at(1));
      await tester.pumpAndSettle();
      expect(find.byType(ColorGrid), findsOneWidget);
    });

    testWidgets('the shapes button switches to shapes and back', (
      tester,
    ) async {
      final state = await openEditor(tester, 'shapes');
      await tester.tap(find.byTooltip(t.editor.toolbar.shapes));
      await tester.pumpAndSettle();
      expect(state.currentTool, isA<ShapePen>());

      await tester.tap(find.byTooltip(t.editor.toolbar.pen));
      await tester.pumpAndSettle();
      expect(state.currentTool, isA<Pen>());
      expect(state.currentTool, isNot(isA<ShapePen>()));
    });

    testWidgets('the pencil is a pen type, under the pen button', (
      tester,
    ) async {
      final state = await openEditor(tester, 'pencil');
      await tester.tap(find.byTooltip(t.editor.toolbar.pen));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.editor.pens.pencil));
      await tester.pumpAndSettle();
      expect(state.currentTool, isA<Pencil>());

      // Tapping the pen button again opens the pencil's panel
      await tester.tapAt(const Offset(800, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(t.editor.toolbar.pen));
      await tester.pumpAndSettle();
      expect(state.currentTool, isA<Pencil>());
      expect(find.byType(PenModal), findsOneWidget);
    });

    testWidgets('the insert menu lists text, images, graph and paste', (
      tester,
    ) async {
      await openEditor(tester, 'insert');
      await tester.tap(find.byTooltip(t.editor.toolbar.insert));
      await tester.pumpAndSettle();
      expect(find.text(t.editor.toolbar.text), findsOneWidget);
      expect(find.text(t.editor.toolbar.photo), findsOneWidget);
      expect(find.text(t.editor.toolbar.graph), findsOneWidget);
      expect(find.text(t.editor.toolbar.paste), findsOneWidget);
    });

    testWidgets('the selection menu floats once something is selected', (
      tester,
    ) async {
      final state = await openEditor(tester, 'selection');
      final page = state.coreInfo.pages.first;
      final stroke =
          Stroke(
            color: Colors.blue,
            pressureEnabled: false,
            options: StrokeOptions(size: 6, isComplete: true),
            pageIndex: 0,
            page: page,
            toolId: .ballpointPen,
          )..addPoints(const [
            Offset(200, 300),
            Offset(300, 350),
            Offset(400, 300),
          ]);
      page.strokes.add(stroke);

      final select = Select.currentSelect;
      select.selectResult = SelectResult(
        pageIndex: 0,
        strokes: [stroke],
        images: const [],
        path: Path()..addRect(const Rect.fromLTWH(150, 250, 300, 150)),
        pageIndexStart: 0,
      );
      select.doneSelecting = true;
      state.currentTool = select;
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      await tester.pumpAndSettle();
      // One more frame, so the menu can read where the page was laid out
      // ignore: invalid_use_of_protected_member
      state.setState(() {});
      await tester.pumpAndSettle();

      expect(find.byType(SelectionBar), findsOneWidget);
      final menuTop = tester.getTopLeft(find.byType(SelectionBar)).dy;
      final strokeTop = page.renderBox!.localToGlobal(const Offset(0, 300)).dy;
      expect(menuTop, lessThan(strokeTop));
    });

    testWidgets('a shape from the library is selected once placed', (
      tester,
    ) async {
      final state = await openEditor(tester, 'autoselect');
      final page = state.coreInfo.pages.first;
      stows.shapeKind.value = 'trapezoid';
      final shapePen = ShapePen();
      state.currentTool = shapePen;
      state.dragPageIndex = 0;
      shapePen.onDragStart(const Offset(100, 100), page, 0, null);
      shapePen.onDragUpdate(const Offset(200, 150), null);
      shapePen.onDragUpdate(const Offset(300, 250), null);
      state.onDrawEnd(.new());
      await tester.pumpAndSettle();

      expect(state.currentTool, isA<Select>());
      final selected = Select.currentSelect.selectResult.strokes.single;
      expect(selected.libraryKind, LibraryShape.trapezoid);
      expect(page.strokes, contains(selected));
      stows.shapeKind.value = 'auto';
    });
  });
}
