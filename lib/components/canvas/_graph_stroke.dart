import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:sbn/has_size.dart';

/// The lines a graph is drawn with, in page coordinates.
class GraphDrawing {
  const new({
    required this.curve,
    required this.axes,
    required this.asymptotes,
  });

  final List<List<Offset>> curve;

  /// Each axis as (from, to), drawn with an arrowhead at `to`.
  final List<(Offset, Offset)> axes;
  final List<(Offset, Offset)> asymptotes;
}

/// A graph of a function, drawn inside [frame] on the page.
///
/// What it shows is described by [spec]: a template with parameters, or a
/// typed formula, over a range of x and y. Resizing the frame changes how
/// big the graph is, not the function, so asymptotes stay asymptotes.
class GraphStroke extends Stroke {
  Rect frame;
  GraphSpec spec;

  new({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required super.page,
    required super.toolId,
    required this.frame,
    required this.spec,
  }) {
    options.isComplete = true;
  }

  factory fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    final Color color = switch (json['c']) {
      (final int value) => Color(value),
      (final Int64 value) => Color(value.toInt()),
      _ => Stroke.defaultColor,
    };
    double d(String key) => switch (json[key]) {
      (final num v) => v.toDouble(),
      _ => 0,
    };
    return GraphStroke(
      color: color,
      pressureEnabled: false,
      options: StrokeOptions.fromJson(json),
      pageIndex: pageIndex,
      page: page,
      toolId: .parsePenType(json['ty'], fallback: .shapePen),
      frame: Rect.fromLTWH(d('fl'), d('ft'), d('fw'), d('fh')),
      spec: GraphSpec.fromJson(json),
    )..readStyle(json);
  }

  @override
  Map<String, dynamic> toJson() =>
      {
          'shape': 'graph',
          'i': pageIndex,
          'ty': toolId.id,
          'pe': false,
          'c': color.toARGB32(),
          'fl': frame.left,
          'ft': frame.top,
          'fw': frame.width,
          'fh': frame.height,
          ...spec.toJson(),
        }
        ..addAll(options.toJson())
        ..addAll(styleJson);

  // --- Coordinates ---

  /// A point of the graph (x, y) on the page.
  Offset toPage(Offset graphPoint) => Offset(
    frame.left + (graphPoint.dx - spec.xMin) / spec.xSpan * frame.width,
    frame.top + (spec.yMax - graphPoint.dy) / spec.ySpan * frame.height,
  );

  /// A page point in the graph's (x, y).
  Offset toGraph(Offset pagePoint) => Offset(
    spec.xMin + (pagePoint.dx - frame.left) / frame.width * spec.xSpan,
    spec.yMax - (pagePoint.dy - frame.top) / frame.height * spec.ySpan,
  );

  GraphDrawing? _drawing;
  Rect? _drawingFrame;
  GraphSpec? _drawingSpec;

  /// What to draw, worked out once per frame and spec.
  GraphDrawing get drawing {
    if (_drawing != null && _drawingFrame == frame && _drawingSpec == spec) {
      return _drawing!;
    }
    final curve = [
      for (final piece in spec.curvePieces())
        [for (final p in piece) toPage(p)],
    ];
    final axes = <(Offset, Offset)>[
      if (spec.showAxes && spec.yMin < 0 && spec.yMax > 0)
        (toPage(Offset(spec.xMin, 0)), toPage(Offset(spec.xMax, 0))),
      if (spec.showAxes && spec.xMin < 0 && spec.xMax > 0)
        (toPage(Offset(0, spec.yMin)), toPage(Offset(0, spec.yMax))),
    ];
    final asymptotes = <(Offset, Offset)>[
      if (spec.showAsymptotes) ...[
        // An asymptote lying on a drawn axis is already shown by the axis.
        for (final x in spec.verticalAsymptotes())
          if (!(spec.showAxes && x.abs() < spec.xSpan * 1e-6))
            (toPage(Offset(x, spec.yMin)), toPage(Offset(x, spec.yMax))),
        for (final y in spec.horizontalAsymptotes())
          if (!(spec.showAxes && y.abs() < spec.ySpan * 1e-6))
            (toPage(Offset(spec.xMin, y)), toPage(Offset(spec.xMax, y))),
      ],
    ];
    _drawingFrame = frame;
    _drawingSpec = spec;
    return _drawing = GraphDrawing(
      curve: curve,
      axes: axes,
      asymptotes: asymptotes,
    );
  }

  // --- Stroke behaviour ---

  @override
  bool get isShape => true;

  /// Lassoing anywhere inside the graph selects it.
  @override
  bool get pickedFromInside => true;

  @override
  bool get isEmpty => frame.isEmpty;

  @override
  int get length => 64;

  List<Offset> get _frameCorners => [
    frame.topLeft,
    frame.topRight,
    frame.bottomRight,
    frame.bottomLeft,
    frame.topLeft,
  ];

  @override
  List<PointVector> get erasablePoints => [
    for (final corner in _frameCorners) PointVector(corner.dx, corner.dy),
  ];

  @override
  List<Offset> getPolygon({required StrokeQuality quality}) => _frameCorners;

  @override
  Path getPath(List<Offset> polygon, {bool smooth = true}) =>
      Path()..addRect(frame);

  /// Close to the curve or an axis counts as touching the graph.
  @override
  double distanceTo(Offset point) {
    final d = drawing;
    var best = double.infinity;
    for (final piece in d.curve) {
      final distance = ShapeGeometry.distanceToPolyline(point, piece);
      if (distance < best) best = distance;
    }
    for (final (from, to) in d.axes) {
      final distance = ShapeGeometry.distanceToPolyline(point, [from, to]);
      if (distance < best) best = distance;
    }
    return best;
  }

  /// A graph can't be cut into pieces: touching it erases all of it.
  @override
  List<Stroke>? eraseAround(Offset center, double radius) =>
      distanceTo(center) <= radius + options.size / 2 ? const [] : null;

  /// The move and stretch handles of a template graph, on the page.
  @override
  List<Offset> get vertices => [
    for (final point in spec.handlePoints()) toPage(point),
  ];

  @override
  Stroke withVertex(int index, Offset position) =>
      copy()..spec = spec.withHandle(index, toGraph(position));

  @override
  Stroke transformed(Matrix4 m) {
    final Rect newFrame;
    if (SelectionTransform.isAxisAligned(m)) {
      newFrame = MatrixUtils.transformRect(m, frame);
    } else {
      // A graph stays upright: when turned, only its centre moves.
      newFrame = Rect.fromCenter(
        center: MatrixUtils.transformPoint(m, frame.center),
        width: frame.width,
        height: frame.height,
      );
    }
    return copy()..frame = newFrame;
  }

  @override
  void shift(Offset offset) {
    frame = frame.shift(offset);
    super.shift(offset);
  }

  @override
  double get maxY => frame.bottom;

  @override
  String toSvgPath() =>
      'M${frame.left},${frame.top} '
      'L${frame.right},${frame.top} '
      'L${frame.right},${frame.bottom} '
      'L${frame.left},${frame.bottom} Z';

  @override
  GraphStroke copy() => GraphStroke(
    color: color,
    pressureEnabled: false,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
    frame: frame,
    spec: spec,
  ).withStyleOf(this);
}
