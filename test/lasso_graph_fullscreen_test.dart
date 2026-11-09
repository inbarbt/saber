import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/toolbar/graph_editor.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/stroke_clipboard.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/graph/graph_spec.dart';

void main() {
  FlavorConfig.setup();

  group('graph domain', () {
    test('the curve is drawn only inside the domain', () {
      const spec = GraphSpec(formula: 'x', domainMin: 0, domainMax: 2);
      final xs = [
        for (final piece in spec.curvePieces())
          for (final p in piece) p.dx,
      ];
      expect(xs, isNotEmpty);
      expect(xs.reduce((a, b) => a < b ? a : b), closeTo(0, 1e-9));
      expect(xs.reduce((a, b) => a > b ? a : b), closeTo(2, 1e-9));
      // The axes still span the whole box
      expect(spec.xMin, -5);
      expect(spec.xMax, 5);
    });

    test('without a domain the curve spans the axes', () {
      const spec = GraphSpec(formula: 'x');
      final xs = [for (final p in spec.curvePieces().single) p.dx];
      expect(xs.first, -5);
      expect(xs.last, 5);
    });

    test('the domain survives a save and load', () {
      const spec = GraphSpec(formula: 'x^2', domainMin: -1);
      final loaded = GraphSpec.fromJson(spec.toJson());
      expect(loaded, spec);
      expect(loaded.domainMin, -1);
      expect(loaded.domainMax, isNull);
      expect(GraphSpec.fromJson(const GraphSpec().toJson()).domainMin, isNull);
    });

    test('copyWith can clear the domain', () {
      const spec = GraphSpec(domainMin: 1, domainMax: 3);
      expect(spec.copyWith(domainMin: () => null).domainMin, isNull);
      expect(spec.copyWith(domainMin: () => null).domainMax, 3);
    });

    test('a domain closed on both sides has no horizontal asymptote', () {
      const open = GraphSpec(template: GraphTemplate.hyperbola);
      expect(open.horizontalAsymptotes(), [0]);
      const closed = GraphSpec(
        template: GraphTemplate.hyperbola,
        domainMin: 1,
        domainMax: 4,
      );
      expect(closed.horizontalAsymptotes(), isEmpty);
    });

    test('vertical asymptotes outside the domain are not drawn', () {
      const spec = GraphSpec(template: GraphTemplate.hyperbola, domainMin: 1);
      expect(spec.verticalAsymptotes(), isEmpty);
    });
  });

  group('graph number fields', () {
    test('read numbers the way they are typed', () {
      const parse = GraphSpecEditorNumbers.parse;
      expect(parse('-2'), -2);
      expect(parse('−2'), -2);
      expect(parse(' 1,5 '), 1.5);
      expect(parse('pi/2'), closeTo(1.5708, 1e-4));
      expect(parse('-2pi'), closeTo(-6.2832, 1e-4));
      expect(parse(''), isNull);
      expect(parse('abc'), isNull);
    });
  });

  group('system bars', () {
    tearDown(() {
      DynamicMaterialApp.setHideSystemBars(false);
      DynamicMaterialApp.setFullscreen(false, updateSystem: false);
    });

    test('bars hidden by the editor are not full screen', () {
      DynamicMaterialApp.setHideSystemBars(true);
      DynamicMaterialApp.systemBarsChanged(visible: false);
      expect(DynamicMaterialApp.isFullscreen, isFalse);
    });

    test('without the setting, hidden bars still mean full screen', () {
      DynamicMaterialApp.systemBarsChanged(visible: false);
      expect(DynamicMaterialApp.isFullscreen, isTrue);
      DynamicMaterialApp.systemBarsChanged(visible: true);
      expect(DynamicMaterialApp.isFullscreen, isFalse);
    });
  });

  group('lasso screenshot', () {
    tearDown(StrokeClipboard.clear);

    test('a screenshot replaces copied writing on the clipboard', () {
      StrokeClipboard.copyScreenshot(
        png: Uint8List.fromList([1, 2, 3]),
        rect: const Rect.fromLTWH(10, 10, 50, 40),
        pixels: const Size(100, 80),
        filePath: '/a',
        pageIndex: 0,
      );
      expect(StrokeClipboard.isNotEmpty, isTrue);
      expect(StrokeClipboard.screenshot!.rect.width, 50);

      StrokeClipboard.copy(
        strokes: const [],
        images: const [],
        filePath: '/a',
        pageIndex: 0,
      );
      expect(StrokeClipboard.screenshot, isNull);
    });

    testWidgets('only what is inside the lasso is kept', (tester) async {
      await tester.runAsync(() async {
        // A red "page" of 100x100, pictured at 2 pixels per unit
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 200, 200),
          Paint()..color = const Color(0xFFFF0000),
        );
        final page = await recorder.endRecording().toImage(200, 200);

        final lasso = Path()..addOval(const Rect.fromLTWH(20, 20, 40, 40));
        final cut = await LassoScreenshot.cutOut(
          page,
          lasso,
          lasso.getBounds(),
          const Size(100, 100),
        );
        expect(cut.width, 80);
        expect(cut.height, 80);

        final bytes = (await cut.toByteData())!;
        int alphaAt(int x, int y) =>
            bytes.getUint8((y * cut.width + x) * 4 + 3);
        expect(alphaAt(40, 40), 255, reason: 'the middle is inside');
        expect(alphaAt(1, 1), 0, reason: 'the corner is outside the oval');
        page.dispose();
        cut.dispose();
      });
    });
  });
}
