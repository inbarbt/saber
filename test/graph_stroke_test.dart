import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/selection_transform.dart';

void main() {
  FlavorConfig.setup();

  final page = EditorPage();

  // A 200x200 graph of 1/x over [-5, 5]², at (100, 100) on the page
  GraphStroke graph({
    GraphSpec spec = const GraphSpec(template: GraphTemplate.hyperbola),
  }) => GraphStroke(
    color: Colors.black,
    pressureEnabled: false,
    options: StrokeOptions(size: 3),
    pageIndex: 0,
    page: page,
    toolId: .shapePen,
    frame: const Rect.fromLTWH(100, 100, 200, 200),
    spec: spec,
  );

  test('graph and page coordinates match the frame', () {
    final g = graph();
    expect(g.toPage(Offset.zero), const Offset(200, 200));
    expect(g.toPage(const Offset(5, 5)), const Offset(300, 100));
    expect(g.toGraph(const Offset(100, 300)), const Offset(-5, -5));
  });

  test('survives save and load as a graph', () {
    final original = graph(spec: const GraphSpec(formula: '1/(x-1)', yMax: 8))
      ..dashed = true;
    final loaded = Stroke.fromJson(
      original.toJson(),
      fileVersion: EditorCoreInfo.sbnVersion,
      pageIndex: 0,
      page: page,
    );
    expect(loaded, isA<GraphStroke>());
    loaded as GraphStroke;
    expect(loaded.frame, original.frame);
    expect(loaded.spec, original.spec);
    expect(loaded.dashed, isTrue);
  });

  test('drawing has two curve pieces and two axes', () {
    final d = graph().drawing;
    expect(d.curve, hasLength(2));
    expect(d.axes, hasLength(2));
    // 1/x's asymptotes lie on the axes, so they aren't drawn again
    expect(d.asymptotes, isEmpty);
  });

  test('shifted asymptotes are drawn', () {
    final d = graph(
      spec: const GraphSpec(template: GraphTemplate.hyperbola, h: 1, k: 2),
    ).drawing;
    expect(d.asymptotes, hasLength(2));
  });

  test('resizing the frame keeps the function and the line thickness', () {
    final g = graph();
    final m = SelectionTransform.resizeMatrix(
      SelectionBox(g.frame, 0),
      SelectionHandle.right,
      const Offset(500, 200),
      keepAspectRatio: false,
    );
    final resized = g.transformed(m) as GraphStroke;
    expect(resized.frame.width, closeTo(400, 1e-9));
    expect(resized.spec, g.spec);
    expect(resized.options.size, 3);
  });

  test('handles move and stretch the function', () {
    final g = graph();
    expect(g.vertices, hasLength(2));
    // Drag the move handle to the page point for (1, 2)
    final moved = g.withVertex(0, g.toPage(const Offset(1, 2))) as GraphStroke;
    expect(moved.spec.h, closeTo(1, 1e-9));
    expect(moved.spec.k, closeTo(2, 1e-9));
    expect(moved.spec.verticalAsymptotes().single, closeTo(1, 1e-9));
  });

  test('formula graphs have no handles', () {
    expect(graph(spec: const GraphSpec(formula: 'x^2')).vertices, isEmpty);
  });

  test('the eraser erases the graph from its curve, whole', () {
    final g = graph();
    // On the curve at x = 1, y = 1
    final onCurve = g.toPage(const Offset(1, 1));
    expect(Eraser().checkForOverlappingStrokes(onCurve, [g]), [g]);
    expect(g.eraseAround(onCurve, 5), isEmpty);
    // An empty corner of the frame (x = -4, y = 4) is not the curve
    expect(
      Eraser().checkForOverlappingStrokes(g.toPage(const Offset(-4, 4)), [g]),
      isEmpty,
    );
  });

  test('lassoing inside the graph selects it', () {
    final g = graph();
    final select = Select.currentSelect;
    select.onDragStart(const Offset(150, 150), 0);
    select.onDragUpdate(const Offset(160, 150));
    select.onDragUpdate(const Offset(160, 160));
    select.onDragUpdate(const Offset(150, 160));
    select.onDragEnd([g], const []);
    expect(select.selectResult.strokes, [g]);
  });
}
