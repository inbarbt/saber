import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// A compact grid of colors for the floating colors panel:
/// recent colors, the standard colors, and a button for any color.
class ColorGrid extends StatelessWidget {
  const new({
    super.key,
    required this.currentColor,
    required this.invert,
    required this.onColor,
  });

  final Color? currentColor;
  final bool invert;
  final ValueChanged<Color> onColor;

  /// Swatches per row.
  static const perRow = 9;
  static const swatch = 28.0;
  static const gap = 6.0;
  static const width = perRow * swatch + (perRow - 1) * gap;

  static List<Color> get recentColors => [
    for (final value in stows.recentColorsPositioned.value)
      if (int.tryParse(value) case final int argb) Color(argb),
  ].take(perRow).toList();

  bool _isCurrent(Color color) =>
      currentColor != null &&
      currentColor!.withValues(alpha: 1).toARGB32() ==
          color.withValues(alpha: 1).toARGB32();

  Widget _swatch(BuildContext context, Color color, String? name) {
    final colorScheme = ColorScheme.of(context);
    final selected = _isCurrent(color);
    return Tooltip(
      message: name ?? '',
      child: InkResponse(
        onTap: () => onColor(color),
        radius: swatch / 2 + 4,
        child: Container(
          width: swatch,
          height: swatch,
          decoration: BoxDecoration(
            color: color.withInversion(invert).withValues(alpha: 1),
            shape: .circle,
            border: Border.all(
              color: selected ? colorScheme.primary : colorScheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAnyColor(BuildContext context) async {
    var picked = currentColor ?? Colors.black;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: Text(t.settings.accentColorPicker.pickAColor),
        content: SingleChildScrollView(
          child: ColorPicker(
            color: picked,
            pickersEnabled: const {ColorPickerType.wheel: true},
            onColorChanged: (color) => picked = color,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: Text(MaterialLocalizations.of(context).saveButtonLabel),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed ?? false) onColor(picked.withInversion(invert));
  }

  @override
  Widget build(BuildContext context) {
    final recent = recentColors;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: gap * 1.5,
        children: [
          if (recent.isNotEmpty)
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final c in recent) _swatch(context, c, null)],
            ),
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final named in ColorBar.colorPresets)
                _swatch(context, named.color, named.name),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => _pickAnyColor(context),
              icon: const Icon(Icons.palette_outlined),
              label: Text(t.editor.colors.colorPicker),
            ),
          ),
        ],
      ),
    );
  }
}
