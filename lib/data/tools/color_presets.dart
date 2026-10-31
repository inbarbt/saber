import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:stow_plain/stow_plain.dart';

/// Which set of preset colors a tool uses.
enum PresetKind { pen, highlighter, shape }

/// The five colors shown next to the active tool in the toolbar.
/// Each kind of tool has its own five.
abstract final class ColorPresets {
  static const count = 5;

  static const defaults = <PresetKind, List<Color>>{
    .pen: [
      Colors.black,
      Color(0xFF1565C0), // blue
      Color(0xFFC62828), // red
      Color(0xFF2E7D32), // green
      Color(0xFF6A1B9A), // purple
    ],
    .highlighter: [
      Color(0xFFFFEB3B), // yellow
      Color(0xFF76FF03), // green
      Color(0xFFFF80AB), // pink
      Color(0xFF40C4FF), // blue
      Color(0xFFFFAB40), // orange
    ],
    .shape: [
      Colors.black,
      Color(0xFF1565C0),
      Color(0xFFC62828),
      Color(0xFF2E7D32),
      Color(0xFFEF6C00), // orange
    ],
  };

  /// The preset kind for [tool], or null if it has no colors
  /// (eraser, laser pointer, text).
  /// The lasso uses the pen's colors to recolor a selection.
  static PresetKind? kindFor(Tool tool) => switch (tool) {
    Highlighter() => .highlighter,
    ShapePen() => .shape,
    Pen() => .pen,
    Select() => .pen,
    _ => null,
  };

  static PlainStow<List<String>> _stowFor(PresetKind kind) => switch (kind) {
    .pen => stows.presetColorsPen,
    .highlighter => stows.presetColorsHighlighter,
    .shape => stows.presetColorsShape,
  };

  /// The colors for [kind], always [count] of them, fully opaque.
  static List<Color> colorsFor(PresetKind kind) {
    final saved = _stowFor(kind).value;
    final defaults = ColorPresets.defaults[kind]!;
    return [
      for (int i = 0; i < count; i++)
        if (i < saved.length && int.tryParse(saved[i]) != null)
          Color(int.parse(saved[i]))
        else
          defaults[i],
    ];
  }

  /// Replaces the preset at [index] of [kind] with [color].
  static void replace(PresetKind kind, int index, Color color) {
    assert(index >= 0 && index < count);
    final colors = colorsFor(kind);
    colors[index] = color.withValues(alpha: 1);
    _stowFor(kind).value = [for (final c in colors) c.toARGB32().toString()];
  }

  /// The index of [color] among the presets of [kind], ignoring
  /// transparency (the highlighter adds its own), or null.
  static int? indexOf(PresetKind kind, Color? color) {
    if (color == null) return null;
    final opaque = color.withValues(alpha: 1).toARGB32();
    final colors = colorsFor(kind);
    for (int i = 0; i < colors.length; i++) {
      if (colors[i].toARGB32() == opaque) return i;
    }
    return null;
  }
}
