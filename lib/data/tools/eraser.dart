import 'dart:ui';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;
double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

/// What kind of thing a stroke is, for the eraser's filter.
enum EraserTarget {
  pen,
  highlighter,
  shapes;

  static EraserTarget of(Stroke stroke) {
    if (stroke is RectangleStroke || stroke is CircleStroke) return shapes;
    return switch (stroke.toolId) {
      .highlighter => highlighter,
      .shapePen => shapes,
      _ => pen,
    };
  }
}

class Eraser extends Tool {
  /// The eraser's radius, in page units.
  double size;
  double get sqrSize => square(size);

  List<Stroke> _erased = [];

  /// Partial erasing: strokes that existed before this drag and were cut,
  /// and the pieces made during this drag that are still on the page.
  final List<Stroke> _cutOriginals = [];
  final Set<Stroke> _pieces = {};

  /// Whether erasing removes only the part of a stroke under the eraser.
  bool partial;

  /// What this eraser may erase.
  Set<EraserTarget> targets;

  new({this.size = 10, this.partial = false, Set<EraserTarget>? targets})
    : targets = targets ?? EraserTarget.values.toSet();

  /// An eraser set up from the user's eraser settings.
  factory fromPrefs() => Eraser(
    size: stows.eraserSize.value.toDouble(),
    partial: stows.eraserPartial.value,
    targets: {
      if (stows.eraserErasesPen.value) .pen,
      if (stows.eraserErasesHighlighter.value) .highlighter,
      if (stows.eraserErasesShapes.value) .shapes,
    },
  );

  @override
  ToolId get toolId => .eraser;

  /// Whether this eraser's filter lets it erase [stroke].
  bool canErase(Stroke stroke) => targets.contains(EraserTarget.of(stroke));

  /// Returns any [strokes] that are close to the given [eraserPos].
  List<Stroke> checkForOverlappingStrokes(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    final List<Stroke> overlapping = [];
    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (!canErase(stroke)) continue;
      if (_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) {
        overlapping.add(stroke);
        _erased.add(stroke);
      }
    }
    return overlapping;
  }

  /// Partial erasing at [eraserPos]: returns, for each stroke that was cut,
  /// the pieces that replace it (possibly none).
  Map<Stroke, List<Stroke>> erasePartially(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    final replacements = <Stroke, List<Stroke>>{};
    for (final stroke in strokes) {
      if (!canErase(stroke)) continue;
      if (!_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) continue;
      final pieces = stroke.eraseAround(eraserPos, size);
      if (pieces == null) continue;
      if (!_pieces.remove(stroke)) _cutOriginals.add(stroke);
      _pieces.addAll(pieces);
      replacements[stroke] = pieces;
    }
    return replacements;
  }

  /// Returns the strokes that have been erased during this drag.
  List<Stroke> onDragEnd() {
    final List<Stroke> erased = _erased;
    _erased = [];
    return erased;
  }

  /// Ends a partial-erasing drag: the strokes that were cut, and the
  /// pieces that replaced them.
  ({List<Stroke> removed, List<Stroke> added}) onPartialDragEnd() {
    final result = (removed: List.of(_cutOriginals), added: List.of(_pieces));
    _cutOriginals.clear();
    _pieces.clear();
    return result;
  }

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.length <= 3) {
      if (stroke.lowQualityPath.contains(eraserPos)) return true;
    }

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }
}
