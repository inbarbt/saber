import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/tools/selection_transform.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final VoidCallback? copySelection;
  final VoidCallback? cutSelection;

  /// Null hides the paste button (nothing to paste).
  final VoidCallback? pasteSelection;

  /// The selection's current thickness, or null if nothing is selected.
  final double? Function()? getSelectionSize;
  final ValueChanged<double>? setSelectionSize;

  /// Which styles the whole selection has, or null if nothing is selected.
  final ({bool dashed, bool filled, bool arrow})? Function()? getSelectionStyle;
  final void Function({bool? dashed, bool? filled, bool? arrow})?
  setSelectionStyle;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    this.copySelection,
    this.cutSelection,
    this.pasteSelection,
    this.getSelectionSize,
    this.setSelectionSize,
    this.getSelectionStyle,
    this.setSelectionStyle,
  });

  /// Thicknesses offered by the picker.
  static const minThickness = 1.0;
  static const maxThickness = 25.0;

  void _showStylePicker(BuildContext context) {
    var style = getSelectionStyle!();
    if (style == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setState) {
            void refresh() => setState(() => style = getSelectionStyle!());
            return Column(
              mainAxisSize: .min,
              children: [
                SwitchListTile(
                  title: Text(t.editor.shapeStyle.dashed),
                  secondary: const Icon(Icons.line_style),
                  value: style!.dashed,
                  onChanged: (v) {
                    setSelectionStyle!(dashed: v);
                    refresh();
                  },
                ),
                SwitchListTile(
                  title: Text(t.editor.shapeStyle.fill),
                  secondary: const Icon(Icons.format_color_fill),
                  value: style!.filled,
                  onChanged: (v) {
                    setSelectionStyle!(filled: v);
                    refresh();
                  },
                ),
                SwitchListTile(
                  title: Text(t.editor.shapeStyle.arrow),
                  secondary: const Icon(Icons.arrow_right_alt),
                  value: style!.arrow,
                  onChanged: (v) {
                    setSelectionStyle!(arrow: v);
                    refresh();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showThicknessPicker(BuildContext context) {
    final initial = getSelectionSize!();
    if (initial == null) return;
    var value = initial.clamp(minThickness, maxThickness);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const .all(16),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: .min,
              children: [
                Text(
                  '${t.editor.selectionBar.thickness}: ${value.toStringAsFixed(1)}',
                ),
                Slider(
                  value: value,
                  min: minThickness,
                  max: maxThickness,
                  divisions: ((maxThickness - minThickness) * 2).round(),
                  onChanged: (v) => setState(() => value = v),
                  // Apply once when the finger lifts, so undo is one step.
                  onChangeEnd: setSelectionSize,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: .center,
      children: [
        if (copySelection != null)
          _SelectionBarButton(
            onPressed: copySelection!,
            tooltip: t.editor.selectionBar.copy,
            icon: Icons.copy_all,
          ),
        if (cutSelection != null)
          _SelectionBarButton(
            onPressed: cutSelection!,
            tooltip: t.editor.selectionBar.cut,
            icon: Icons.content_cut,
          ),
        if (pasteSelection != null)
          _SelectionBarButton(
            onPressed: pasteSelection!,
            tooltip: t.editor.selectionBar.paste,
            icon: Icons.content_paste,
          ),
        if (getSelectionStyle != null && setSelectionStyle != null)
          _SelectionBarButton(
            onPressed: () => _showStylePicker(context),
            tooltip: t.editor.shapeStyle.title,
            icon: Icons.line_style,
          ),
        if (getSelectionSize != null && setSelectionSize != null)
          _SelectionBarButton(
            onPressed: () => _showThicknessPicker(context),
            tooltip: t.editor.selectionBar.thickness,
            icon: Icons.line_weight,
          ),
        IconButton(
          onPressed: duplicateSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.duplicate,
          icon: const AdaptiveIcon(
            icon: Icons.content_copy,
            cupertinoIcon: CupertinoIcons.doc_on_clipboard,
          ),
        ),
        const _KeepAspectRatioToggle(),
        IconButton(
          onPressed: deleteSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.delete,
          icon: const AdaptiveIcon(
            icon: Icons.delete,
            cupertinoIcon: CupertinoIcons.delete,
          ),
        ),
      ],
    );
  }
}

/// Toggles whether the corner handles keep the selection's proportions.
class _KeepAspectRatioToggle extends StatefulWidget {
  const new();

  @override
  State<_KeepAspectRatioToggle> createState() => _KeepAspectRatioToggleState();
}

class _KeepAspectRatioToggleState extends State<_KeepAspectRatioToggle> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final enabled = SelectionTransform.keepAspectRatio;
    return IconButton(
      onPressed: () => setState(() {
        SelectionTransform.keepAspectRatio = !enabled;
      }),
      isSelected: enabled,
      style: TextButton.styleFrom(
        foregroundColor: enabled ? colorScheme.primary : colorScheme.secondary,
        backgroundColor: enabled
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: t.editor.selectionBar.keepAspectRatio,
      icon: const Icon(Icons.aspect_ratio),
    );
  }
}

class _SelectionBarButton extends StatelessWidget {
  const new({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ColorScheme.of(context).secondary,
        backgroundColor: Colors.transparent,
        shape: const CircleBorder(),
      ),
      tooltip: tooltip,
      icon: Icon(icon),
    );
  }
}
