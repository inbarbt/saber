import 'dart:math';

import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/shape_geometry.dart';
import 'package:sbn/tool_id.dart';

class Select extends Tool {
  new _();

  static final _currentSelect = Select._();
  static Select get currentSelect => _currentSelect;

  /// The minimum ratio of points inside a stroke or image
  /// for it to be selected, when [selectTouched] is off.
  static const minPercentInside = 0.7;

  /// Select anything the lasso touches, not only what it mostly encloses.
  /// On in Saber+: circling part of a long line selects the whole line.
  static var selectTouched = true;

  var selectResult = SelectResult(
    pageIndex: -1,
    strokes: const [],
    images: const [],
    path: Path(),
    pageIndexStart: null,
  );
  var doneSelecting = false;

  /// The points of the lasso being drawn.
  final List<Offset> _lassoPoints = [];

  @override
  ToolId get toolId => .select;

  void unselect() {
    doneSelecting = false;
    selectResult.pageIndex = -1;
  }

  Color? getDominantStrokeColor() {
    if (!doneSelecting) return null;
    if (selectResult.strokes.isEmpty) return null;

    final colorDistribution = <Color, int>{};
    for (final stroke in selectResult.strokes) {
      colorDistribution.update(
        stroke.color,
        (value) => value + stroke.length,
        ifAbsent: () => stroke.length,
      );
    }
    assert(colorDistribution.isNotEmpty);

    return colorDistribution.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
  }

  void onDragStart(Offset position, int pageIndex) {
    doneSelecting = false;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [],
      images: [],
      path: Path(),
      pageIndexStart: pageIndex,
    );
    selectResult.path.moveTo(position.dx, position.dy);
    _lassoPoints.clear();
    onDragUpdate(position);
  }

  void onDragUpdate(Offset position) {
    selectResult.path.lineTo(position.dx, position.dy);
    _lassoPoints.add(position);
  }

  /// Adds the indices of any [strokes] that are inside the selection area
  /// to [selectResult.indices].
  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (selectTouched) {
        if (_lassoTouches(stroke)) selectResult.strokes.add(stroke);
        continue;
      }
      final percentInside = polygonPercentInside(
        selectResult.path,
        stroke.lowQualityPolygon,
      );
      if (percentInside > minPercentInside) {
        selectResult.strokes.add(stroke);
      }
    }

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final percentInside = rectPercentInside(selectResult.path, image.dstRect);
      if (selectTouched
          ? percentInside > 0
          : percentInside >= minPercentInside) {
        selectResult.images.add(image);
      }
    }

    selectResult.frameAngle = naturalFrameAngle(
      selectResult.strokes,
      selectResult.images,
    );
  }

  /// The angle the selection box should start at: the shape's own angle
  /// when a single straight-sided shape is selected (e.g. a turned
  /// rectangle), so its handles stretch it along its sides. Otherwise 0.
  static double naturalFrameAngle(
    List<Stroke> strokes,
    List<EditorImage> images,
  ) {
    if (strokes.length != 1 || images.isNotEmpty) return 0;
    final shape = strokes.single;
    if (!shape.crisp) return 0;
    final corners = ShapeGeometry.minAreaRect(shape.centerline);
    if (corners.isEmpty) return 0;
    return ShapeGeometry.rectTurnDegrees(corners) * pi / 180;
  }

  /// Whether the lasso touches [stroke]: some of the line itself (not its
  /// thick outline, so strokes that only brush the lasso's edge stay out)
  /// is inside the lasso, or for a filled shape, the lasso is drawn on its
  /// fill. (An unfilled box around some writing isn't picked up by
  /// lassoing the writing inside it.)
  bool _lassoTouches(Stroke stroke) {
    final path = selectResult.path;
    if (stroke.outlinePoints().any(path.contains)) return true;
    if (_lassoPoints.isEmpty || !stroke.pickedFromInside) return false;
    if (!stroke.isClosedShape) return false;
    final area = Path()..addPolygon(stroke.outlinePoints(), true);
    return _lassoPoints.any(area.contains);
  }

  static double rectPercentInside(Path selection, Rect rect) {
    const int gridSize = 5;
    final gridCellWidth = rect.width / (gridSize - 1);
    final gridCellHeight = rect.height / (gridSize - 1);

    int pointsInside = 0;
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        if (selection.contains(
          Offset(rect.left + gridCellWidth * x, rect.top + gridCellHeight * y),
        )) {
          pointsInside++;
        }
      }
    }

    // times 1.25 because the grid is not very accurate
    return pointsInside / (gridSize * gridSize) * 1.25;
  }

  static double polygonPercentInside(Path selection, List<Offset> polygon) {
    int pointsInside = 0;
    for (final point in polygon) {
      if (selection.contains(point)) {
        pointsInside++;
      }
    }
    return pointsInside / polygon.length;
  }
}

class SelectResult {
  int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  Path path;
  int? pageIndexStart;

  /// The current angle while the selection is being rotated, for display.
  double? rotationDegrees;

  /// How far the selection box is turned (radians, clockwise on screen).
  /// The box turns with the content when it is rotated.
  double frameAngle = 0;

  /// Whether a single selected shape shows its corner and side handles
  /// (shape editing) instead of the box that stretches it as a whole.
  /// Lines always show their two ends.
  var editShape = false;

  /// While a corner is being dragged: the angle to show and where.
  ({Offset at, double degrees})? vertexAngle;

  new({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.path,
    required this.pageIndexStart,
  });

  bool get isEmpty {
    return strokes.isEmpty && images.isEmpty;
  }

  SelectResult copyWith({
    int? pageIndex,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    Path? path,
    int? pageIndexStart,
  }) {
    return SelectResult(
      pageIndex: pageIndex ?? this.pageIndex,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      path: path ?? this.path,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
    )..frameAngle = frameAngle;
  }
}
