import 'dart:math';

import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_graph_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/data/tools/shape_constraints.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

class Stroke {
  static final log = Logger('Stroke');

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  /// The path the pen took, without thickness.
  List<Offset> get centerline => [
    for (final point in points) Offset(point.x, point.y),
  ];

  int pageIndex;
  HasSize page;
  final ToolId toolId;

  static const defaultColor = Colors.black;
  static const defaultPressureEnabled = true;

  Color color;
  bool pressureEnabled;
  final StrokeOptions options;

  /// Drawn as a dashed line along its path.
  var dashed = false;

  /// Fill colour for closed shapes, or null for no fill.
  Color? fillColor;

  /// An arrowhead at the end of the stroke.
  var arrowEnd = false;

  /// Drawn as a clean line of constant thickness through its points,
  /// instead of as handwriting. Used for shapes made of straight sides
  /// (turned rectangles, triangles, stars, stretched circles).
  var crisp = false;

  /// Which library shape this is, so dragging a corner keeps it that
  /// kind of shape (see [ShapeConstraints]). Null for handwriting and
  /// for hand-drawn shapes other than rectangles.
  LibraryShape? libraryKind;

  /// Whether this is a drawn shape rather than handwriting.
  /// Shapes keep their line thickness when resized.
  bool get isShape => crisp;

  bool get hasStyle => dashed || fillColor != null || arrowEnd || crisp;

  /// Whether lassoing inside this shape (not only across its outline)
  /// selects it.
  bool get pickedFromInside => fillColor != null;

  /// Distance from [point] to the drawn line, for erasing shapes.
  double distanceTo(Offset point) => ShapeGeometry.distanceToPolyline(point, [
    for (final p in erasablePoints) p,
  ]);

  /// Saved form of [dashed], [fillColor] and [arrowEnd].
  Map<String, dynamic> get styleJson => {
    if (dashed) 'dsh': true,
    if (fillColor != null) 'fil': fillColor!.toARGB32(),
    if (arrowEnd) 'arw': true,
    if (crisp) 'crp': true,
    if (libraryKind != null) 'lsh': libraryKind!.name,
  };

  void readStyle(Map<String, dynamic> json) {
    dashed = json['dsh'] == true;
    fillColor = switch (json['fil']) {
      (final int value) => Color(value),
      (final Int64 value) => Color(value.toInt()),
      _ => null,
    };
    arrowEnd = json['arw'] == true;
    crisp = json['crp'] == true;
    final kind = json['lsh'];
    libraryKind = kind is String ? LibraryShape.fromName(kind) : null;
    if (libraryKind == LibraryShape.auto) libraryKind = null;
  }

  /// Copies this stroke's style onto [other] and returns it.
  T withStyleOf<T extends Stroke>(Stroke source) => this as T
    ..dashed = source.dashed
    ..fillColor = source.fillColor
    ..arrowEnd = source.arrowEnd
    ..crisp = source.crisp
    ..libraryKind = source.libraryKind;

  List<Offset>? _lowQualityPolygon, _highQualityPolygon;
  List<Offset> get lowQualityPolygon =>
      _lowQualityPolygon ??= getPolygon(quality: .low);
  List<Offset> get highQualityPolygon =>
      _highQualityPolygon ??= getPolygon(quality: .high);

  Path? _lowQualityPath, _highQualityPath;
  Path get lowQualityPath =>
      _lowQualityPath ??= getPath(lowQualityPolygon, smooth: false);
  Path get highQualityPath => _highQualityPath ??= getPath(highQualityPolygon);

  void shift(Offset offset) {
    if (offset == .zero) return;

    points.shift(offset);
    _lowQualityPolygon?.shift(offset);
    _highQualityPolygon?.shift(offset);
    _lowQualityPath = _lowQualityPath?.shift(offset);
    _highQualityPath = _highQualityPath?.shift(offset);
  }

  void markPolygonNeedsUpdating() {
    _lowQualityPolygon = null;
    _highQualityPolygon = null;
    _lowQualityPath = null;
    _highQualityPath = null;
  }

  new({
    required this.color,
    required this.pressureEnabled,
    required this.options,
    required this.pageIndex,
    required this.page,
    required this.toolId,
  });

  factory fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['i'] == pageIndex || json['i'] == null);
    switch (json['shape'] as String?) {
      case null:
        break;
      case 'circle':
        return CircleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'rect':
        return RectangleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'graph':
        return GraphStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      default:
        log.severe('Unknown shape: ${json['shape']}');
    }

    final ToolId toolId = .parsePenType(json['ty'], fallback: .fountainPen);

    final options = StrokeOptions.fromJson(json);
    final pressureEnabled = json['pe'] ?? defaultPressureEnabled;
    if (toolId == .shapePen) {
      // Set smoothing and streamline to 0 for ShapePen
      // to mitigate https://github.com/saber-notes/saber/issues/1587
      options.smoothing = 0;
      options.streamline = 0;
    }

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = defaultColor;
      default:
        throw Exception(
          'Invalid color value: (${json['c'].runtimeType}) ${json['c']}',
        );
    }

    final offset = Offset(json['ox'] ?? 0, json['oy'] ?? 0);
    final pointsJson = json['p'] as List<dynamic>;
    final Iterable<PointVector> points;
    if (fileVersion >= 13) {
      points = pointsJson.map(
        (point) => PointExtensions.fromBsonBinary(json: point, offset: offset),
      );
    } else {
      points = pointsJson.map(
        // ignore: deprecated_member_use_from_same_package
        (point) => PointExtensions.fromJson(
          json: Map<String, dynamic>.from(point),
          offset: offset,
        ),
      );
    }

    return Stroke(
        color: color,
        pressureEnabled: pressureEnabled,
        options: options,
        pageIndex: pageIndex,
        page: page,
        toolId: toolId,
      )
      ..points.addAll(points)
      ..readStyle(json);
  }
  Map<String, dynamic> toJson() {
    // these json keys should not be the same as the ones in [StrokeOptions.toJson]
    return {
        'shape': null,
        'p': points
            .where((point) => point.isFinite)
            .map((PointVector point) => point.toBsonBinary())
            .toList(),
        'i': pageIndex,
        'ty': toolId.id,
        'pe': pressureEnabled,
        'c': color.toARGB32(),
      }
      ..addAll(options.toJson())
      ..addAll(styleJson);
  }

  void addPoint(Offset point, [double? pressure]) {
    if (!pressureEnabled) {
      pressure = null;
    } else if (pressure != null) {
      options.simulatePressure = false;
    }

    points.add(PointVector(point.dx, point.dy, pressure));
    markPolygonNeedsUpdating();
  }

  void addPoints(List<Offset> points) {
    for (final point in points) {
      addPoint(point);
    }
  }

  void popFirstPoint() {
    points.removeAt(0);
    markPolygonNeedsUpdating();
  }

  /// Points that are closer than this
  /// threshold multiplied by the stroke's size
  /// will be counted as duplicates.
  static const _optimisePointsThreshold = 0.1;

  /// Removes points that are too close together. See [_optimisePointsThreshold].
  ///
  /// This function is idempotent, so running it multiple times
  /// will not change the result.
  ///
  /// This function does not change [_polygonNeedsUpdating].
  void optimisePoints({double thresholdMultiplier = _optimisePointsThreshold}) {
    if (points.length <= 3) return;

    final minDistance = options.size * thresholdMultiplier;

    // Remove points with null pressure because they were duplicates
    points.removeWhere((point) => point.pressure == null);

    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final prev = points[i - 1];
      final next = points[i + 1];

      if (prev.distanceSquaredTo(point) < minDistance * minDistance &&
          point.distanceSquaredTo(next) < minDistance * minDistance) {
        points.removeAt(i);
        i--;
      }
    }
  }

  @protected
  List<Offset> getPolygon({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }
    final rememberSimulatedPressure =
        quality == .high && options.simulatePressure && options.isComplete;

    final polygon = getStroke(
      skipPoints(points, quality.N),
      options: quality.isLowQuality
          ? options.copyWith(
              simulatePressure: false,
              smoothing: 0,
              streamline: 0,
            )
          : options,
      rememberSimulatedPressure: rememberSimulatedPressure,
    );

    if (rememberSimulatedPressure) {
      // Ensure we don't simulate pressure again
      options.simulatePressure = false;
      // Remove points that are too close together
      optimisePoints();
    }

    return polygon;
  }

  /// Returns a [Path] that represents the stroke.
  ///
  /// If [smooth] is true, and the stroke is complete,
  /// the path will be a smooth curve between the points in [polygon].
  ///
  /// Otherwise, the path will use straight lines between each point
  /// in [polygon] for performance.
  @protected
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    if (smooth && options.isComplete) {
      return smoothPathFromPolygon(polygon);
    }

    return Path()..addPolygon(polygon, true);
  }

  /// Returns a list with every Nth point in [points].
  static List<PointVector> skipPoints(List<PointVector> points, int N) {
    // Nothing is being skipped, just return [points].
    if (N <= 1) return points;

    // If we have too few points, skip less points
    final divided = points.length / N;
    const minDivided = 8;
    if (divided < minDivided) {
      N = (N * divided / minDivided).floor();
      if (N <= 1) return points;
    }

    return [
      for (int i = 0; i < points.length - 1; i += N) points[i],
      points.last,
    ];
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    final path = Path();
    path.moveTo(polygon.first.dx, polygon.first.dy);
    for (int i = 1; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      final mid = (p1 + p2) / 2;
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  String toSvgPath() {
    String toSvgPoint(Offset point) {
      return '${point.dx} '
          '${page.size.height - point.dy}';
    }

    // Remove NaN points, and convert to SVG coordinates
    final svgPoints = highQualityPolygon
        .where((offset) => offset.isFinite)
        .map(toSvgPoint);

    return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(max);
  }

  RecognizedUnistroke? detectShape() {
    if (points.length < 3) return null;
    // The recognizer scores a path that ends exactly where it started
    // as NaN and calls it a line, so drop a repeated end point.
    final input = points.length > 3 && points.first == points.last
        ? points.sublist(0, points.length - 1)
        : points;
    final recognized = recognizeUnistroke(input);
    if (recognized == null || recognized.score.isNaN) return null;
    return recognized;
  }

  /// Uses the one_dollar_unistroke_recognizer package
  /// only to recognize straight lines.
  ///
  /// In addition, the line must be sufficiently long
  /// relative to [options.size].
  bool isStraightLine([int minLength = 5]) {
    if (points.length < 3) return false;

    final recognized = recognizeUnistroke(
      points,
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null) return false;
    assert(recognized.name == DefaultUnistrokeNames.line);
    if (recognized.score < 0.7) return false;

    final sqrLength = points.first.distanceSquaredTo(points.last);
    final sqrMinLength = minLength * minLength * options.size * options.size;
    return sqrLength >= sqrMinLength;
  }

  /// Replaces the points in this stroke with a straight line.
  ///
  /// If the resulting line is close to horizontal or vertical,
  /// it will be snapped to be exactly horizontal or vertical.
  void convertToLine() {
    assert(points.length >= 2);

    // Use the average pressure
    final pressure = points.map((point) => point.pressure ?? 0.5).average;
    var firstPoint = PointVector.fromOffset(
      offset: points.first,
      pressure: pressure,
    );
    var lastPoint = PointVector.fromOffset(
      offset: points.last,
      pressure: pressure,
    );

    // Snap to the horizontal or vertical axis
    (firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);

    points.clear();
    points.add(firstPoint);
    points.add(lastPoint);
    points.add(lastPoint);
    options.isComplete = true;
    options.start.taperEnabled = false;
    options.end.taperEnabled = false;
  }

  /// Snaps a line to either horizontal or vertical
  /// if the angle is close enough.
  static (PointVector firstPoint, PointVector lastPoint) snapLine(
    PointVector firstPoint,
    PointVector lastPoint,
  ) {
    final dx = (lastPoint.dx - firstPoint.dx).abs();
    final dy = (lastPoint.dy - firstPoint.dy).abs();
    final angle = atan2(dy, dx);

    const snapAngle = 5 * pi / 180; // 5 degrees
    if (angle < snapAngle) {
      // snap to horizontal
      return (
        firstPoint,
        PointVector(lastPoint.dx, firstPoint.dy, lastPoint.pressure),
      );
    } else if (angle > pi / 2 - snapAngle) {
      // snap to vertical
      return (
        firstPoint,
        PointVector(firstPoint.dx, lastPoint.dy, lastPoint.pressure),
      );
    } else {
      return (firstPoint, lastPoint);
    }
  }

  Stroke copy() => (Stroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
  )..points.addAll(points)).withStyleOf(this);

  /// A copy of this stroke with [m] applied to every point.
  /// The thickness scales with the overall size change.
  Stroke transformed(Matrix4 m) {
    final result = copy();
    result.points
      ..clear()
      ..addAll(
        points.map((point) {
          final moved = MatrixUtils.transformPoint(m, Offset(point.x, point.y));
          return PointVector(moved.dx, moved.dy, point.pressure);
        }),
      );
    // Handwriting scales its thickness with its size; shapes keep theirs.
    if (!isShape) result.options.size *= SelectionTransform.lengthScale(m);
    result.markPolygonNeedsUpdating();
    return result;
  }

  /// The points along this stroke for erasing part of it.
  /// Shapes return their outline.
  List<PointVector> get erasablePoints => points;

  /// The corners of a straight-sided shape, which can be dragged to
  /// reshape it. Empty for handwriting.
  /// A closed shape's repeated end point is left out.
  List<Offset> get vertices {
    if (!crisp || !ShapeConstraints.hasVertices(libraryKind)) return const [];
    final line = centerline;
    if (line.length >= 3 && (line.first - line.last).distance < 0.5) {
      return line.sublist(0, line.length - 1);
    }
    return line;
  }

  /// Where all the corners go when vertex [index] (see [vertices]) is
  /// dragged to [position], keeping this kind of shape.
  VertexMove vertexMove(int index, Offset position) =>
      ShapeConstraints.move(libraryKind, vertices, index, position);

  /// A copy of this shape with vertex [index] (see [vertices]) dragged
  /// to [position].
  Stroke withVertex(int index, Offset position) =>
      withVertices(vertexMove(index, position).vertices);

  /// A copy of this shape with these [corners] (in [vertices] order).
  Stroke withVertices(List<Offset> corners) {
    final result = copy();
    final closed =
        points.length >= 3 && (points.first - points.last).distance < 0.5;
    result.points
      ..clear()
      ..addAll([
        for (final c in corners) PointVector(c.dx, c.dy),
        if (closed) PointVector(corners.first.dx, corners.first.dy),
      ]);
    result.markPolygonNeedsUpdating();
    return result;
  }

  /// Points along the stroke no more than [step] apart, for hit tests.
  /// Shapes are stored as a few corners; this fills in their sides.
  List<Offset> outlinePoints({double step = 4}) {
    final source = erasablePoints;
    final result = <Offset>[];
    for (int i = 0; i < source.length; i++) {
      final point = source[i];
      if (i > 0) {
        final prev = source[i - 1];
        final extra = ((point - prev).distance / step).floor();
        for (int k = 1; k <= extra; k++) {
          result.add(Offset.lerp(prev, point, k / (extra + 1))!);
        }
      }
      result.add(point);
    }
    return result;
  }

  /// Whether this stroke encloses an area (it ends where it starts).
  bool get isClosedShape {
    final source = erasablePoints;
    if (source.length < 3) return false;
    return (source.first - source.last).distance <= max(options.size * 2, 4);
  }

  /// Erases the part of this stroke within [radius] of [center]
  /// (plus half the stroke's thickness).
  ///
  /// Returns null if nothing was erased. Otherwise returns the pieces that
  /// are left, as new strokes: empty if the whole stroke was erased.
  List<Stroke>? eraseAround(Offset center, double radius) {
    final reach = radius + options.size / 2;
    final reachSquared = reach * reach;

    // Fill in long gaps so the eraser can't slip between two points.
    final step = max(1.0, radius / 3);
    final dense = <PointVector>[];
    final source = erasablePoints;
    for (int i = 0; i < source.length; i++) {
      final point = source[i];
      if (i > 0) {
        final prev = source[i - 1];
        final gap = (point - prev).distance;
        final extra = (gap / step).floor();
        for (int k = 1; k <= extra; k++) {
          final t = k / (extra + 1);
          dense.add(
            PointVector(
              prev.x + (point.x - prev.x) * t,
              prev.y + (point.y - prev.y) * t,
              point.pressure,
            ),
          );
        }
      }
      dense.add(point);
    }

    var touched = false;
    final pieces = <List<PointVector>>[];
    var current = <PointVector>[];
    for (final point in dense) {
      if ((point - center).distanceSquared <= reachSquared) {
        touched = true;
        if (current.isNotEmpty) pieces.add(current);
        current = <PointVector>[];
      } else {
        current.add(point);
      }
    }
    if (current.isNotEmpty) pieces.add(current);
    if (!touched) return null;

    return [
      for (final piece in pieces)
        if (piece.length >= 2) _pieceWith(piece),
    ];
  }

  // A piece is an open line: it keeps dashes but not fill or arrowhead.
  Stroke _pieceWith(List<PointVector> piecePoints) =>
      Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: options.copyWith(isComplete: true),
          pageIndex: pageIndex,
          page: page,
          toolId: toolId,
        )
        ..points.addAll(piecePoints)
        ..dashed = dashed
        ..crisp = isShape;

  /// A plain stroke through [corners] after applying [m],
  /// keeping this stroke's look. Used for shapes that can no longer be
  /// described by their own class, e.g. a rotated rectangle.
  @protected
  Stroke polylineThrough(List<Offset> corners, Matrix4 m) {
    final result = Stroke(
      color: color,
      pressureEnabled: false,
      options: options.copyWith(
        smoothing: 0,
        streamline: 0,
        simulatePressure: false,
      ),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    result.addPoints([
      for (final corner in corners) MatrixUtils.transformPoint(m, corner),
    ]);
    result.options.isComplete = true;
    return result.withStyleOf(this)..crisp = true;
  }
}

class StrokeQuality {
  @visibleForTesting
  const new(this.N);

  /// We use every Nth point for this quality level.
  final int N;

  static const low = StrokeQuality(4);
  static const high = StrokeQuality(1);

  bool get isLowQuality => N > 1;
}
