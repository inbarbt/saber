import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/pencil_shader.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
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

  testWidgets('PDF export draws dashed, filled and arrowed strokes', (
    tester,
  ) async {
    final page = EditorPage();
    final coreInfo = EditorCoreInfo(filePath: '/tests/export_styles')
      ..pages.add(page);

    StrokeOptions options() => StrokeOptions(size: 4, isComplete: true);
    page.strokes.addAll([
      RectangleStroke(
          color: Colors.black,
          pressureEnabled: false,
          options: options(),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
          rect: const Rect.fromLTWH(50, 50, 200, 100),
        )
        ..dashed = true
        ..fillColor = const Color(0x40FF0000),
      CircleStroke(
        color: Colors.blue,
        pressureEnabled: false,
        options: options(),
        pageIndex: 0,
        page: page,
        toolId: .shapePen,
        center: const Offset(400, 100),
        radius: 50,
      )..fillColor = const Color(0x400000FF),
      Stroke(
          color: Colors.black,
          pressureEnabled: false,
          options: options(),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
        )
        ..addPoints(const [Offset(50, 300), Offset(400, 300)])
        ..dashed = true
        ..arrowEnd = true,
      Stroke(
          color: Colors.green,
          pressureEnabled: false,
          options: options(),
          pageIndex: 0,
          page: page,
          toolId: .shapePen,
        )
        ..addPoints(const [
          Offset(100, 400),
          Offset(200, 500),
          Offset(0, 500),
          Offset(100, 400),
        ])
        ..fillColor = const Color(0x4000FF00),
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
      expect(bytes, isNotEmpty);
    });
  });
}
