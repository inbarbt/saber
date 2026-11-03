import 'dart:io';
import 'dart:math';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/components/toolbar/color_grid.dart';
import 'package:saber/components/toolbar/eraser_bar.dart';
import 'package:saber/components/toolbar/floating_panel.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/data/editor/annotations.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/color_presets.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// The editor's toolbar: one row of tools, the active tool's colors,
/// and a "more" menu. A tool's settings open in a floating panel when
/// the tool is tapped a second time.
class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.undo,
    required this.isUndoPossible,
    required this.redo,
    required this.isRedoPossible,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.paste,
    this.pasteStrokes,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
    this.onLayersChanged,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback undo;
  final bool isUndoPossible;
  final VoidCallback redo;
  final bool isRedoPossible;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  /// Pastes from the system clipboard.
  final VoidCallback paste;

  /// Pastes copied handwriting, or null if nothing was copied.
  final VoidCallback? pasteStrokes;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  /// Called after a kind of writing is shown or hidden, to redraw.
  final VoidCallback? onLayersChanged;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 4);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 4);

  /// Taps inside this group don't close an open panel.
  static const tapGroup = #saberToolbar;
}

/// Which floating panel is open.
enum ToolPanel { none, pen, highlighter, shape, eraser, colors }

class _ToolbarState extends State<Toolbar> {
  final panel = ValueNotifier(ToolPanel.none);
  final _panelController = OverlayPortalController();
  final _panelLink = LayerLink();

  /// When the colors panel was opened from a long press on a preset,
  /// the index of that preset: the chosen color replaces it.
  int? _replacePreset;

  /// The pen the pen button stands for: fountain, ballpoint or pencil.
  static Pen? _writingPen;

  /// The shape pen the shapes button stands for.
  static ShapePen? _shapePen;

  static bool _isWritingPen(Tool tool) =>
      tool is Pen && tool is! Highlighter && tool is! ShapePen;

  @override
  void initState() {
    _assignKeybindings();
    DynamicMaterialApp.addFullscreenListener(_setState);
    panel.addListener(_onPanelChanged);
    super.initState();
  }

  void _setState() => setState(() {});

  void _onPanelChanged() {
    if (panel.value == .none) {
      _panelController.hide();
      _replacePreset = null;
    } else {
      _panelController.show();
    }
    if (mounted) setState(() {});
  }

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, () => _togglePanel(.colors));
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void _togglePanel(ToolPanel which) {
    panel.value = panel.value == which ? .none : which;
  }

  /// Selects [tool], or opens its panel if it is already selected.
  void _onToolButton(Tool tool, ToolPanel? toolPanel) {
    if (identical(widget.currentTool, tool)) {
      if (toolPanel != null) _togglePanel(toolPanel);
    } else {
      panel.value = .none;
      _setTool(tool);
    }
  }

  void _setTool(Tool tool) {
    if (_isWritingPen(tool)) _writingPen = tool as Pen;
    if (tool is ShapePen) _shapePen = tool;
    widget.setTool(tool);
  }

  void toggleEraser() {
    panel.value = .none;
    widget.setTool(Eraser.fromPrefs()); // this toggles the eraser
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  /// Closes the panel on a tap elsewhere, unless the tap is on a sheet
  /// or dialog that the panel opened.
  void _onTapOutsidePanel(PointerDownEvent _) {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    panel.value = .none;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final alignment = stows.editorToolbarAlignment.value;
    final isToolbarVertical =
        alignment == AxisDirection.left || alignment == AxisDirection.right;
    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final tool = widget.currentTool;
    if (_isWritingPen(tool)) _writingPen = tool as Pen;
    if (tool is ShapePen) _shapePen = tool;
    final writingPen = _writingPen ??= Pen.currentPen is ShapePen
        ? Pen.fountainPen()
        : Pen.currentPen;
    final shapePen = _shapePen ??= ShapePen();

    // The eraser and laser have no settings to keep open
    if ((panel.value == .pen && !identical(tool, writingPen)) ||
        (panel.value == .highlighter && tool is! Highlighter) ||
        (panel.value == .shape && tool is! ShapePen) ||
        (panel.value == .eraser && tool is! Eraser) ||
        (panel.value == .colors && ColorPresets.kindFor(tool) == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) panel.value = .none;
      });
    }

    final currentColor = switch (tool) {
      final Pen pen => pen.color,
      final Select select => select.getDominantStrokeColor(),
      _ => null,
    };
    final presetKind = ColorPresets.kindFor(tool);

    final toolButtons = <Widget>[
      ToolbarIconButton(
        tooltip: t.editor.toolbar.undo,
        enabled: !widget.readOnly && widget.isUndoPossible,
        onPressed: widget.undo,
        padding: buttonPadding,
        child: const AdaptiveIcon(
          icon: Icons.undo,
          cupertinoIcon: CupertinoIcons.arrow_uturn_left,
        ),
      ),
      ToolbarIconButton(
        tooltip: t.editor.toolbar.redo,
        enabled: !widget.readOnly && widget.isRedoPossible,
        onPressed: widget.redo,
        padding: buttonPadding,
        child: const AdaptiveIcon(
          icon: Icons.redo,
          cupertinoIcon: CupertinoIcons.arrow_uturn_right,
        ),
      ),
      _divider(isToolbarVertical, colorScheme),
      ToolbarIconButton(
        tooltip: t.editor.toolbar.pen,
        selected: identical(tool, writingPen),
        enabled: !widget.readOnly,
        onPressed: () => _onToolButton(writingPen, .pen),
        padding: buttonPadding,
        child: UniIcon(writingPen.icon, size: 16),
      ),
      ToolbarIconButton(
        tooltip: t.editor.pens.highlighter,
        selected: tool is Highlighter,
        enabled: !widget.readOnly,
        onPressed: () =>
            _onToolButton(Highlighter.currentHighlighter, .highlighter),
        padding: buttonPadding,
        child: const FaIcon(Highlighter.highlighterIcon, size: 16),
      ),
      ToolbarIconButton(
        tooltip: t.editor.toolbar.toggleEraser,
        selected: tool is Eraser,
        enabled: !widget.readOnly,
        onPressed: () {
          if (tool is Eraser) {
            _togglePanel(.eraser);
          } else {
            panel.value = .none;
            widget.setTool(Eraser.fromPrefs());
          }
        },
        padding: buttonPadding,
        child: const FaIcon(FontAwesomeIcons.eraser, size: 16),
      ),
      ToolbarIconButton(
        tooltip: t.editor.toolbar.select,
        selected: tool is Select,
        enabled: !widget.readOnly,
        onPressed: () => _onToolButton(Select.currentSelect, null),
        padding: buttonPadding,
        child: const Icon(CupertinoIcons.lasso),
      ),
      ToolbarIconButton(
        tooltip: t.editor.toolbar.shapes,
        selected: tool is ShapePen,
        enabled: !widget.readOnly,
        onPressed: () => _onToolButton(shapePen, .shape),
        padding: buttonPadding,
        child: const FaIcon(ShapePen.shapePenIcon, size: 16),
      ),
      _InsertMenu(
        enabled: !widget.readOnly,
        padding: buttonPadding,
        textEditing: widget.textEditing,
        toggleTextEditing: () {
          panel.value = .none;
          widget.toggleTextEditing();
        },
        pickPhoto: widget.pickPhoto,
        insertGraph: () {
          stows.shapeKind.value = 'graph';
          panel.value = .none;
          _setTool(shapePen);
        },
        paste: widget.pasteStrokes ?? widget.paste,
      ),
      _NoteKindButton(enabled: !widget.readOnly, padding: buttonPadding),
    ];

    final presets = presetKind == null
        ? const <Widget>[]
        : [
            _divider(isToolbarVertical, colorScheme),
            for (final (index, color) in ColorPresets.colorsFor(
              presetKind,
            ).indexed)
              _PresetColorButton(
                color: color.withInversion(invert),
                selected:
                    ColorPresets.indexOf(presetKind, currentColor) == index,
                enabled: !widget.readOnly,
                onTap: () {
                  if (ColorPresets.indexOf(presetKind, currentColor) == index) {
                    _togglePanel(.colors);
                  } else {
                    widget.setColor(color);
                  }
                },
                onLongPress: () {
                  _replacePreset = index;
                  panel.value = .colors;
                  setState(() {});
                },
              ),
          ];

    final moreMenu = _MoreMenu(
      padding: buttonPadding,
      readOnly: widget.readOnly,
      laserSelected: tool == LaserPointer.currentLaserPointer,
      selectLaser: () {
        panel.value = .none;
        widget.setTool(LaserPointer.currentLaserPointer);
      },
      toggleFingerDrawing: widget.toggleFingerDrawing,
      toggleFullscreen: toggleFullscreen,
      onLayersChanged: () {
        widget.onLayersChanged?.call();
        setState(() {});
      },
      exportAsSba: widget.exportAsSba,
      exportAsPdf: widget.exportAsPdf,
      exportAsPng: widget.exportAsPng,
    );

    final direction = isToolbarVertical ? Axis.vertical : Axis.horizontal;
    final mainRow = TapRegion(
      groupId: Toolbar.tapGroup,
      child: CompositedTransformTarget(
        link: _panelLink,
        child: Padding(
          padding: const .all(6),
          // Buttons wrap onto a second row on narrow screens
          // (e.g. a tablet held upright) instead of being cut off.
          child: Wrap(
            direction: direction,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [...toolButtons, ...presets, moreMenu],
          ),
        ),
      ),
    );

    final panelChild = switch (panel.value) {
      .none => const SizedBox.shrink(),
      .pen => PenModal(getTool: () => writingPen, setTool: _setTool),
      .highlighter => PenModal(
        getTool: () => Highlighter.currentHighlighter,
        setTool: _setTool,
      ),
      .shape => PenModal(getTool: () => shapePen, setTool: _setTool),
      .eraser => EraserBar(
        getEraser: () => switch (widget.currentTool) {
          final Eraser eraser => eraser,
          _ => null,
        },
      ),
      .colors => ColorGrid(
        currentColor: currentColor,
        invert: invert,
        onColor: (color) {
          final replace = _replacePreset;
          if (replace != null && presetKind != null) {
            ColorPresets.replace(presetKind, replace, color);
          }
          widget.setColor(color);
          panel.value = .none;
        },
      ),
    };

    final (targetAnchor, followerAnchor, offset) = switch (alignment) {
      AxisDirection.up => (
        Alignment.bottomCenter,
        Alignment.topCenter,
        const Offset(0, 4),
      ),
      AxisDirection.left => (
        Alignment.centerRight,
        Alignment.centerLeft,
        const Offset(4, 0),
      ),
      AxisDirection.right => (
        Alignment.centerLeft,
        Alignment.centerRight,
        const Offset(-4, 0),
      ),
      AxisDirection.down => (
        Alignment.topCenter,
        Alignment.bottomCenter,
        const Offset(0, -4),
      ),
    };

    final toolbarWithPanel = OverlayPortal(
      controller: _panelController,
      overlayChildBuilder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _panelLink,
          showWhenUnlinked: false,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: offset,
          child: TapRegion(
            groupId: Toolbar.tapGroup,
            onTapOutside: _onTapOutsidePanel,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: min(MediaQuery.sizeOf(context).width - 16, 640),
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: FloatingPanel(child: panelChild),
            ),
          ),
        ),
      ),
      child: mainRow,
    );

    return Flex(
      direction: isToolbarVertical ? Axis.horizontal : Axis.vertical,
      textDirection: switch (alignment) {
        AxisDirection.left => .rtl,
        AxisDirection.right => .ltr,
        _ => null,
      },
      verticalDirection: switch (alignment) {
        AxisDirection.down => VerticalDirection.down,
        AxisDirection.up => VerticalDirection.up,
        _ => VerticalDirection.down,
      },
      children: [_quillToolbar(context, isToolbarVertical), toolbarWithPanel],
    );
  }

  Widget _divider(bool vertical, ColorScheme colorScheme) {
    final color = colorScheme.outlineVariant;
    return vertical
        ? Container(
            width: 24,
            height: 1,
            margin: const .symmetric(vertical: 6),
            color: color,
          )
        : Container(
            width: 1,
            height: 24,
            margin: const .symmetric(horizontal: 6),
            color: color,
          );
  }

  Widget _quillToolbar(BuildContext context, bool isToolbarVertical) {
    final colorScheme = ColorScheme.of(context);
    return ValueListenableBuilder(
      valueListenable: widget.quillFocus,
      builder: (context, quill, _) {
        final baseButtonStyle =
            IconButtonTheme.of(context).style ?? const ButtonStyle();

        final iconTheme = QuillIconTheme(
          iconButtonUnselectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(Colors.transparent),
              foregroundColor: WidgetStateProperty.all(colorScheme.primary),
            ),
          ),
          iconButtonSelectedData: IconButtonData(
            style: baseButtonStyle.copyWith(
              backgroundColor: WidgetStateProperty.all(colorScheme.primary),
              foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
            ),
          ),
        );
        return Collapsible(
          axis: isToolbarVertical
              ? CollapsibleAxis.horizontal
              : CollapsibleAxis.vertical,
          maintainState: false,
          collapsed: !widget.textEditing || quill == null,
          child: quill != null
              ? QuillSimpleToolbar(
                  controller: quill.controller,
                  config: QuillSimpleToolbarConfig(
                    axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                    buttonOptions: QuillSimpleToolbarButtonOptions(
                      base: QuillToolbarBaseButtonOptions(iconTheme: iconTheme),
                    ),
                    // scrollable on Android and iOS
                    multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                    showUndo: false,
                    showRedo: false,
                    showFontSize: false,
                    showFontFamily: false,
                    showClearFormat: false,
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  void dispose() {
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);
    panel.dispose();
    _removeKeybindings();
    super.dispose();
  }
}

/// One of the five colors next to the active tool.
class _PresetColorButton extends StatelessWidget {
  const new({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      hint: t.editor.toolbar.changePreset,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        radius: 20,
        child: Padding(
          padding: const .all(5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 1),
              shape: .circle,
              border: Border.all(
                color: selected ? colorScheme.primary : colorScheme.outline,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text, images, graphs and paste.
class _InsertMenu extends StatelessWidget {
  const new({
    required this.enabled,
    required this.padding,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.pickPhoto,
    required this.insertGraph,
    required this.paste,
  });

  final bool enabled;
  final EdgeInsets padding;
  final bool textEditing;
  final VoidCallback toggleTextEditing;
  final VoidCallback pickPhoto;
  final VoidCallback insertGraph;
  final VoidCallback paste;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.text_fields),
          trailingIcon: textEditing ? const Icon(Icons.check) : null,
          onPressed: toggleTextEditing,
          child: Text(t.editor.toolbar.text),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.photo),
          onPressed: pickPhoto,
          child: Text(t.editor.toolbar.photo),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.functions),
          onPressed: insertGraph,
          child: Text(t.editor.toolbar.graph),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.content_paste),
          onPressed: paste,
          child: Text(t.editor.toolbar.paste),
        ),
      ],
      builder: (context, controller, _) => ToolbarIconButton(
        tooltip: t.editor.toolbar.insert,
        selected: textEditing,
        enabled: enabled,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        padding: padding,
        child: const Icon(Icons.add_box_outlined),
      ),
    );
  }
}

/// Laser pointer, finger drawing, fullscreen and export.
class _MoreMenu extends StatelessWidget {
  const new({
    required this.padding,
    required this.readOnly,
    required this.laserSelected,
    required this.selectLaser,
    required this.toggleFingerDrawing,
    required this.toggleFullscreen,
    required this.onLayersChanged,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final EdgeInsets padding;
  final bool readOnly;
  final bool laserSelected;
  final VoidCallback selectLaser;
  final VoidCallback toggleFingerDrawing;
  final VoidCallback toggleFullscreen;
  final VoidCallback onLayersChanged;
  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  @override
  Widget build(BuildContext context) {
    const check = Icon(Icons.check);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Symbols.stylus_laser_pointer),
          trailingIcon: laserSelected ? check : null,
          onPressed: selectLaser, // works in read-only mode too
          child: Text(t.editor.pens.laserPointer),
        ),
        if (!stows.hideFingerDrawingToggle.value)
          MenuItemButton(
            leadingIcon: const Icon(CupertinoIcons.hand_draw),
            trailingIcon: stows.editorFingerDrawing.value ? check : null,
            onPressed: readOnly ? null : toggleFingerDrawing,
            child: Text(t.editor.toolbar.toggleFingerDrawing),
          ),
        MenuItemButton(
          leadingIcon: Icon(
            DynamicMaterialApp.isFullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
          ),
          onPressed: toggleFullscreen,
          child: Text(t.editor.toolbar.fullscreen),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.layers_outlined),
          menuChildren: [
            for (final kind in NoteKind.values)
              CheckboxMenuButton(
                value: Annotations.isShown(kind),
                closeOnActivate: false,
                onChanged: (shown) {
                  Annotations.setShown(kind, shown ?? true);
                  onLayersChanged();
                },
                child: Text(noteKindLabel(kind)),
              ),
          ],
          child: Text(t.editor.notes.layers),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.share),
          menuChildren: [
            if (exportAsPdf != null)
              MenuItemButton(
                onPressed: () => exportAsPdf!(context),
                child: const Text('PDF'),
              ),
            if (exportAsPng != null)
              MenuItemButton(
                onPressed: () => exportAsPng!(context),
                child: const Text('PNG'),
              ),
            if (exportAsSba != null)
              MenuItemButton(
                onPressed: () => exportAsSba!(context),
                child: const Text('SBA'),
              ),
          ],
          child: Text(t.editor.toolbar.exportAs),
        ),
      ],
      builder: (context, controller, _) => ToolbarIconButton(
        tooltip: t.editor.toolbar.more,
        selected: laserSelected,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        padding: padding,
        child: const Icon(Icons.more_horiz),
      ),
    );
  }
}

IconData noteKindIcon(NoteKind kind) => switch (kind) {
  NoteKind.regular => Icons.edit_note,
  NoteKind.toSelf => Icons.contact_support_outlined,
  NoteKind.general => Icons.lightbulb_outline,
};

/// Switches what new writing counts as: regular, a note to self, or a
/// general note. Tapping goes to the next kind.
class _NoteKindButton extends StatelessWidget {
  const new({required this.enabled, required this.padding});

  final bool enabled;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Annotations.current,
      builder: (context, kind, _) => ToolbarIconButton(
        tooltip: t.editor.notes.writingAs(kind: noteKindLabel(kind)),
        selected: kind != NoteKind.regular,
        enabled: enabled,
        onPressed: () => Annotations.current.value =
            NoteKind.values[(kind.index + 1) % NoteKind.values.length],
        padding: padding,
        child: Icon(noteKindIcon(kind)),
      ),
    );
  }
}
