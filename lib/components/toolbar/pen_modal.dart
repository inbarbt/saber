import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/toolbar/graph_editor.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/graph/graph_spec.dart';
import 'package:saber/data/graph/new_graph.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_library.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:stow_plain/stow_plain.dart';

class PenModal<T extends Pen> extends StatefulWidget {
  const new({super.key, required this.getTool, required this.setTool});

  /// Gets the current/last-used tool of type [T],
  /// e.g. [Pen.currentPen] or [Highlighter.currentHighlighter].
  final T Function() getTool;

  /// Sets a pen to be the current pen.
  final void Function(Pen) setTool;

  @override
  State<PenModal<T>> createState() => _PenModalState<T>();
}

class _PenModalState<T extends Pen> extends State<PenModal<T>> {
  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final pen = widget.getTool();

    final isWritingPen = pen is! Highlighter && pen is! ShapePen;
    final row = Flex(
      direction: axis,
      mainAxisAlignment: .center,
      spacing: 8,
      children: [
        SizePicker(axis: axis, pen: pen),

        if (isWritingPen) ...[
          _PenSelector(
            isSelected: pen is! Pencil && pen.icon == Pen.fountainPenIcon,
            onPressed: () => setState(() {
              widget.setTool(Pen.fountainPen());
            }),
            tooltip: t.editor.pens.fountainPen,
            icon: SvgPicture.asset(
              'assets/images/scribble_fountain.svg',
              width: 32,
              height: 32 / 508 * 374,
              theme: SvgTheme(
                currentColor: pen is! Pencil && pen.icon == Pen.fountainPenIcon
                    ? ColorScheme.of(context).secondary
                    : ColorScheme.of(context).onSurface,
              ),
            ),
          ),
          _PenSelector(
            isSelected: pen is! Pencil && pen.icon == Pen.ballpointPenIcon,
            onPressed: () => setState(() {
              widget.setTool(Pen.ballpointPen());
            }),
            tooltip: t.editor.pens.ballpointPen,
            icon: SvgPicture.asset(
              'assets/images/scribble_ballpoint.svg',
              width: 32,
              height: 32 / 508 * 374,
              theme: SvgTheme(
                currentColor: pen is! Pencil && pen.icon == Pen.ballpointPenIcon
                    ? ColorScheme.of(context).secondary
                    : ColorScheme.of(context).onSurface,
              ),
            ),
          ),
          _PenSelector(
            isSelected: pen is Pencil,
            onPressed: () => setState(() {
              widget.setTool(Pencil.currentPencil);
            }),
            tooltip: t.editor.pens.pencil,
            icon: const FaIcon(Pencil.pencilIcon),
          ),
        ],

        if (pen is ShapePen) ...[
          _ShapePicker(onChanged: () => setState(() {})),
          _StyleToggle(
            value: stows.shapeDashed.value,
            onPressed: () => setState(
              () => stows.shapeDashed.value = !stows.shapeDashed.value,
            ),
            tooltip: t.editor.shapeStyle.dashed,
            icon: Icons.line_style,
          ),
          _StyleToggle(
            value: stows.shapeFilled.value,
            onPressed: () => setState(
              () => stows.shapeFilled.value = !stows.shapeFilled.value,
            ),
            tooltip: t.editor.shapeStyle.fill,
            icon: Icons.format_color_fill,
          ),
          _StyleToggle(
            value: stows.shapeArrow.value,
            onPressed: () => setState(
              () => stows.shapeArrow.value = !stows.shapeArrow.value,
            ),
            tooltip: t.editor.shapeStyle.arrow,
            icon: Icons.arrow_right_alt,
          ),
        ],

        if (pen is! Highlighter && pen is! ShapePen)
          _StyleToggle(
            value: stows.penDashed.value,
            onPressed: () =>
                setState(() => stows.penDashed.value = !stows.penDashed.value),
            tooltip: t.editor.shapeStyle.dashed,
            icon: Icons.line_style,
          ),

        if (pen is! Highlighter && pen is! ShapePen)
          IconButton(
            onPressed: () => _showPenFeelSettings(context, pen),
            tooltip: t.editor.penFeel.title,
            icon: const Icon(Icons.tune),
          ),
      ],
    );

    if (pen is Highlighter) {
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          row,
          Text(
            t.editor.highlighterStraight.title,
            style: TextTheme.of(context).labelMedium,
          ),
          ValueListenableBuilder(
            valueListenable: stows.highlighterStraight,
            builder: (context, mode, _) => SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'hold',
                  label: Text(t.editor.highlighterStraight.hold),
                ),
                ButtonSegment(
                  value: 'always',
                  label: Text(t.editor.highlighterStraight.always),
                ),
                ButtonSegment(
                  value: 'never',
                  label: Text(t.editor.highlighterStraight.never),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  stows.highlighterStraight.value = s.single,
            ),
          ),
        ],
      );
    }
    if (pen is ShapePen) {
      return Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          row,
          _GestureChip(
            label: t.settings.prefLabels.snapToShapes,
            stow: stows.snapToShapes,
          ),
        ],
      );
    }
    if (!isWritingPen) return row;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        row,
        Wrap(
          spacing: 8,
          children: [
            _GestureChip(
              label: t.settings.prefLabels.holdToDrawShape,
              stow: stows.holdToDrawShape,
            ),
            _GestureChip(
              label: t.settings.prefLabels.circleToLasso,
              stow: stows.circleToLasso,
            ),
            _GestureChip(
              label: t.settings.prefLabels.scribbleToErase,
              stow: stows.scribbleToErase,
            ),
          ],
        ),
      ],
    );
  }

  /// Pressure sensitivity and stabilization for [pen], as levels 0 to 5.
  /// Level 3 is Saber's default (0.5).
  void _showPenFeelSettings(BuildContext context, Pen pen) {
    double toLevel(double value) => (value * PenFeel.levelsPerUnit)
        .clamp(0, PenFeel.maxLevel)
        .roundToDouble();

    var pressure = toLevel(pen.options.thinning);
    var stabilization = toLevel(pen.options.streamline);

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const .all(16),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Text('${t.editor.penFeel.pressure}: ${pressure.round()}'),
                Slider(
                  value: pressure,
                  max: PenFeel.maxLevel,
                  divisions: PenFeel.maxLevel.round(),
                  onChanged: (level) {
                    setSheetState(() => pressure = level);
                    pen.options.thinning = PenFeel.toValue(level);
                  },
                ),
                Text(
                  '${t.editor.penFeel.stabilization}: ${stabilization.round()}',
                ),
                Slider(
                  value: stabilization,
                  max: PenFeel.maxLevel,
                  divisions: PenFeel.maxLevel.round(),
                  onChanged: (level) {
                    setSheetState(() => stabilization = level);
                    pen.options.streamline = PenFeel.toValue(level);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps the pen feel levels shown to the user onto stroke options.
abstract final class PenFeel {
  static const maxLevel = 5.0;
  static const levelsPerUnit = 6.0;

  static double toValue(double level) => level / levelsPerUnit;
}

class const _PenSelector({
  required final bool isSelected,
  required final void Function() onPressed,
  required final String tooltip,
  required final Widget icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      isSelected: isSelected,
      style: IconButton.styleFrom(
        foregroundColor: isSelected
            ? ColorScheme.of(context).secondary
            : ColorScheme.of(context).onSurface,
        backgroundColor: isSelected
            ? ColorScheme.of(context).secondary.withValues(alpha: 0.1)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: tooltip,
      icon: icon,
    );
  }
}

class const _StyleToggle({
  required final bool value,
  required final VoidCallback onPressed,
  required final String tooltip,
  required final IconData icon,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return IconButton(
      onPressed: onPressed,
      isSelected: value,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: value ? colorScheme.secondary : colorScheme.onSurface,
        backgroundColor: value
            ? colorScheme.secondary.withValues(alpha: 0.1)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon),
    );
  }
}

/// Chooses what the shape pen draws: a recognised shape, or a shape from
/// the library dragged out as a box.
class _ShapePicker extends StatelessWidget {
  const new({required this.onChanged});

  final VoidCallback onChanged;

  static String label(LibraryShape shape) {
    final s = t.editor.shapeLibrary;
    return switch (shape) {
      .auto => s.auto,
      .line => s.line,
      .arrow => s.arrow,
      .rectangle => s.rectangle,
      .ellipse => s.ellipse,
      .triangle => s.triangle,
      .rightTriangle => s.rightTriangle,
      .rhombus => s.rhombus,
      .parallelogram => s.parallelogram,
      .trapezoid => s.trapezoid,
      .polygon => s.polygon,
      .star => s.star,
      .graph => s.graph,
    };
  }

  @override
  Widget build(BuildContext context) {
    final current = ShapePen.libraryShape;
    return IconButton(
      tooltip: label(current),
      onPressed: () => _showPicker(context),
      icon: _ShapeIcon(shape: current),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      // Tall enough for the graph editor, and clear of the keyboard
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final current = ShapePen.libraryShape;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: .min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: .center,
                    children: [
                      for (final shape in LibraryShape.values)
                        _ShapeOption(
                          shape: shape,
                          selected: shape == current,
                          onTap: () {
                            stows.shapeKind.value = shape.name;
                            setSheetState(() {});
                            onChanged();
                          },
                        ),
                    ],
                  ),
                  if (current == .graph) ...[
                    const SizedBox(height: 12),
                    GraphSpecEditor(
                      initial: NewGraph.spec,
                      onChanged: (spec) => NewGraph.spec = spec,
                    ),
                  ],
                  if (current == .polygon) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${t.editor.shapeLibrary.corners}: '
                      '${stows.shapeCorners.value}',
                    ),
                    Slider(
                      value: stows.shapeCorners.value.toDouble(),
                      min: ShapeLibrary.minCorners.toDouble(),
                      max: ShapeLibrary.maxCorners.toDouble(),
                      divisions:
                          ShapeLibrary.maxCorners - ShapeLibrary.minCorners,
                      onChanged: (v) {
                        stows.shapeCorners.value = v.round();
                        setSheetState(() {});
                        onChanged();
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShapeOption extends StatelessWidget {
  const new({required this.shape, required this.selected, required this.onTap});

  final LibraryShape shape;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Tooltip(
      message: _ShapePicker.label(shape),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          alignment: .center,
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.secondary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: _ShapeIcon(shape: shape),
        ),
      ),
    );
  }
}

/// A small drawing of a library shape, made from the same outline the
/// shape pen draws.
class _ShapeIcon extends StatelessWidget {
  const new({required this.shape});

  final LibraryShape shape;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? ColorScheme.of(context).onSurface;
    if (shape == .auto) return Icon(Icons.auto_awesome, color: color);
    if (shape == .graph) {
      return CustomPaint(
        size: const Size.square(24),
        painter: GraphPreviewPainter(
          const GraphSpec(
            template: GraphTemplate.hyperbola,
            xMin: -3,
            xMax: 3,
            yMin: -3,
            yMax: 3,
          ),
          color,
          strokeWidth: 1.6,
        ),
      );
    }
    return CustomPaint(
      size: const Size.square(24),
      painter: _ShapeIconPainter(shape, color, stows.shapeCorners.value),
    );
  }
}

class _ShapeIconPainter extends CustomPainter {
  new(this.shape, this.color, this.corners);

  final LibraryShape shape;
  final Color color;
  final int corners;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * 0.12;
    final start = Offset(inset, inset);
    final end = Offset(size.width - inset, size.height - inset);
    final points = shape == .line || shape == .arrow
        ? [
            Offset(inset, size.height / 2),
            Offset(size.width - inset, size.height / 2),
          ]
        : ShapeLibrary.outline(shape, start, end, corners: corners);
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = .stroke
      ..strokeWidth = 1.8
      ..strokeJoin = .round
      ..strokeCap = .round;
    canvas.drawPath(Path()..addPolygon(points, false), paint);
    if (shape == .arrow) {
      final tip = points.last;
      canvas.drawLine(tip, tip + const Offset(-6, -5), paint);
      canvas.drawLine(tip, tip + const Offset(-6, 5), paint);
    }
  }

  @override
  bool shouldRepaint(_ShapeIconPainter old) =>
      old.shape != shape || old.color != color || old.corners != corners;
}

/// Turns a pen gesture on or off. The same setting is in the app settings.
class _GestureChip extends StatelessWidget {
  const new({required this.label, required this.stow});

  final String label;
  final PlainStow<bool> stow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: stow,
      builder: (context, value, _) => FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (selected) => stow.value = selected,
      ),
    );
  }
}
