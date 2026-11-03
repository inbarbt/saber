import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:stow_plain/stow_plain.dart';

/// Options shown in the toolbar while the eraser is active:
/// whole or partial erasing, eraser size, and what the eraser may erase.
class EraserBar extends StatefulWidget {
  const new({super.key, required this.getEraser});

  /// The eraser in use, so a new size applies straight away.
  final Eraser? Function() getEraser;

  /// Eraser sizes offered, in page units.
  static const sizes = [5, 10, 25];

  @override
  State<EraserBar> createState() => _EraserBarState();
}

class _EraserBarState extends State<EraserBar> {
  void _toggle(PlainStow<bool> pref) => setState(() {
    pref.value = !pref.value;
    _applyToCurrentEraser();
  });

  void _setSize(int size) => setState(() {
    stows.eraserSize.value = size;
    _applyToCurrentEraser();
  });

  /// Settings apply to the eraser in use straight away.
  void _applyToCurrentEraser() {
    final eraser = widget.getEraser();
    if (eraser == null) return;
    final fresh = Eraser.fromPrefs();
    eraser
      ..size = fresh.size
      ..partial = fresh.partial
      ..targets = fresh.targets;
  }

  @override
  Widget build(BuildContext context) {
    final strings = t.editor.eraserBar;
    final currentSize = stows.eraserSize.value;
    return Row(
      mainAxisAlignment: .center,
      children: [
        _OptionButton(
          selected: stows.eraserPartial.value,
          tooltip: stows.eraserPartial.value
              ? strings.partial
              : strings.wholeStroke,
          onPressed: () => _toggle(stows.eraserPartial),
          child: Icon(
            stows.eraserPartial.value ? Icons.content_cut : Icons.gesture,
          ),
        ),
        const SizedBox(width: 8),
        for (final (index, size) in EraserBar.sizes.indexed)
          _OptionButton(
            selected: size == currentSize,
            tooltip: '${strings.size} ${index + 1}',
            onPressed: () => _setSize(size),
            child: Container(
              width: 6.0 + index * 5,
              height: 6.0 + index * 5,
              decoration: BoxDecoration(
                color: ColorScheme.of(context).onSurface,
                shape: .circle,
              ),
            ),
          ),
        const SizedBox(width: 8),
        _OptionButton(
          selected: stows.eraserErasesPen.value,
          tooltip: strings.erasesPen,
          onPressed: () => _toggle(stows.eraserErasesPen),
          child: const FaIcon(FontAwesomeIcons.penFancy, size: 16),
        ),
        _OptionButton(
          selected: stows.eraserErasesHighlighter.value,
          tooltip: strings.erasesHighlighter,
          onPressed: () => _toggle(stows.eraserErasesHighlighter),
          child: const FaIcon(FontAwesomeIcons.highlighter, size: 16),
        ),
        _OptionButton(
          selected: stows.eraserErasesShapes.value,
          tooltip: strings.erasesShapes,
          onPressed: () => _toggle(stows.eraserErasesShapes),
          child: const FaIcon(FontAwesomeIcons.shapes, size: 16),
        ),
        _OptionButton(
          selected: stows.eraserErasesLocked.value,
          tooltip: strings.erasesLocked,
          onPressed: () => _toggle(stows.eraserErasesLocked),
          child: const Icon(Icons.lock_outline, size: 18),
        ),
      ],
    );
  }
}

class _OptionButton extends StatelessWidget {
  const new({
    required this.selected,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return IconButton(
      onPressed: onPressed,
      isSelected: selected,
      tooltip: tooltip,
      style: TextButton.styleFrom(
        foregroundColor: selected ? colorScheme.primary : colorScheme.secondary,
        backgroundColor: selected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: child,
    );
  }
}
