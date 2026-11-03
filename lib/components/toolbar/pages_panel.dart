import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/outline.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/i18n/strings.g.dart';

/// A line of a table of contents, ready to show.
typedef OutlineLine = ({String title, int level, int? pageIndex});

/// The side panel of a note: its pages, and its table of contents.
class PagesPanel extends StatelessWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.pageManager,
    required this.goToPage,
    required this.onOutlineChanged,
  });

  final EditorCoreInfo coreInfo;
  final int currentPageIndex;

  /// The page thumbnails, with moving, copying and deleting pages.
  final Widget pageManager;

  final ValueChanged<int> goToPage;

  /// Called after a page's entries in the table of contents change,
  /// with what they were before.
  final void Function(int pageIndex, List<OutlineEntry> before)
  onOutlineChanged;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 340,
      child: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: t.editor.pages),
                  Tab(text: t.editor.outline.title),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    pageManager,
                    OutlineView(
                      coreInfo: coreInfo,
                      currentPageIndex: currentPageIndex,
                      goToPage: goToPage,
                      onChanged: onOutlineChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The note's own table of contents (its bookmarks), and the table of
/// contents of an imported PDF.
class OutlineView extends StatefulWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.goToPage,
    required this.onChanged,
  });

  final EditorCoreInfo coreInfo;
  final int currentPageIndex;
  final ValueChanged<int> goToPage;
  final void Function(int pageIndex, List<OutlineEntry> before) onChanged;

  /// The entries of all [pages], in page order.
  static List<({int pageIndex, OutlineEntry entry})> entriesOf(
    List<EditorPage> pages,
  ) => [
    for (final (pageIndex, page) in pages.indexed)
      for (final entry in page.outline) (pageIndex: pageIndex, entry: entry),
  ];

  /// [nodes] as lines with their depth, each pointing at the note page
  /// that shows that PDF page (if any).
  static List<OutlineLine> flattenPdfOutline(
    List<PdfOutlineNode> nodes,
    int? Function(int pdfPageNumber) notePageFor, [
    int level = 0,
  ]) => [
    for (final node in nodes) ...[
      (
        title: node.title,
        level: level,
        pageIndex: node.dest == null
            ? null
            : notePageFor(node.dest!.pageNumber),
      ),
      ...flattenPdfOutline(node.children, notePageFor, level + 1),
    ],
  ];

  /// The first note page whose background is page [pdfPageNumber]
  /// (counting from 1) of the PDF at [pdfPath].
  static int? notePageForPdfPage(
    List<EditorPage> pages,
    String pdfPath,
    int pdfPageNumber,
  ) {
    for (final (index, page) in pages.indexed) {
      final background = page.backgroundImage;
      if (background is PdfEditorImage &&
          background.pdfFile?.path == pdfPath &&
          background.pdfPage == pdfPageNumber - 1) {
        return index;
      }
    }
    return null;
  }

  @override
  State<OutlineView> createState() => _OutlineViewState();
}

class _OutlineViewState extends State<OutlineView> {
  late final Future<List<OutlineLine>> _pdfOutline = _loadPdfOutline();

  Future<List<OutlineLine>> _loadPdfOutline() async {
    final pages = widget.coreInfo.pages;
    final pdfPath = pages
        .map((page) => page.backgroundImage)
        .whereType<PdfEditorImage>()
        .map((image) => image.pdfFile?.path)
        .whereType<String>()
        .firstOrNull;
    if (pdfPath == null) return const [];
    try {
      final document = await widget.coreInfo.assetCache.pdfDocumentCache.load(
        pdfPath,
      );
      final nodes = await document.loadOutline();
      return OutlineView.flattenPdfOutline(
        nodes,
        (number) => OutlineView.notePageForPdfPage(pages, pdfPath, number),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _askTitle(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.editor.outline.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _addBookmark() async {
    final pageIndex = widget.currentPageIndex.clamp(
      0,
      widget.coreInfo.pages.length - 1,
    );
    final title = await _askTitle(
      t.editor.outline.pageN(n: '${pageIndex + 1}'),
    );
    if (title == null || title.trim().isEmpty) return;
    _edit(pageIndex, () {
      widget.coreInfo.pages[pageIndex].outline.add(
        OutlineEntry(title: title.trim()),
      );
    });
  }

  void _edit(int pageIndex, void Function() change) {
    final before = [
      for (final entry in widget.coreInfo.pages[pageIndex].outline)
        entry.copy(),
    ];
    setState(change);
    widget.onChanged(pageIndex, before);
  }

  Widget _line({
    required String title,
    required int level,
    required int? pageIndex,
    Widget? menu,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(
        start: 16.0 + level * 20,
        end: 4,
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: pageIndex == null
          ? null
          : Text(t.editor.outline.pageN(n: '${pageIndex + 1}')),
      onTap: pageIndex == null ? null : () => widget.goToPage(pageIndex),
      trailing: menu,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = OutlineView.entriesOf(widget.coreInfo.pages);
    return ListView(
      children: [
        Padding(
          padding: const .all(12),
          child: FilledButton.tonalIcon(
            onPressed: _addBookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
            label: Text(t.editor.outline.addBookmark),
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const .symmetric(horizontal: 16, vertical: 8),
            child: Text(
              t.editor.outline.empty,
              style: TextTheme.of(context).bodySmall,
            ),
          ),
        for (final (:pageIndex, :entry) in entries)
          _line(
            title: entry.title,
            level: entry.level,
            pageIndex: pageIndex,
            menu: PopupMenuButton<String>(
              onSelected: (action) async {
                final page = widget.coreInfo.pages[pageIndex];
                switch (action) {
                  case 'rename':
                    final title = await _askTitle(entry.title);
                    if (title != null && title.trim().isNotEmpty) {
                      _edit(pageIndex, () => entry.title = title.trim());
                    }
                  case 'in':
                    _edit(
                      pageIndex,
                      () => entry.level = (entry.level + 1).clamp(
                        0,
                        OutlineEntry.maxLevel,
                      ),
                    );
                  case 'out':
                    _edit(
                      pageIndex,
                      () => entry.level = (entry.level - 1).clamp(
                        0,
                        OutlineEntry.maxLevel,
                      ),
                    );
                  case 'delete':
                    _edit(pageIndex, () => page.outline.remove(entry));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(t.editor.outline.rename),
                ),
                if (entry.level < OutlineEntry.maxLevel)
                  PopupMenuItem(
                    value: 'in',
                    child: Text(t.editor.outline.indent),
                  ),
                if (entry.level > 0)
                  PopupMenuItem(
                    value: 'out',
                    child: Text(t.editor.outline.outdent),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(t.editor.outline.delete),
                ),
              ],
            ),
          ),
        FutureBuilder(
          future: _pdfOutline,
          builder: (context, snapshot) {
            final lines = snapshot.data ?? const <OutlineLine>[];
            if (lines.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: .stretch,
              children: [
                const Divider(),
                Padding(
                  padding: const .fromLTRB(16, 8, 16, 4),
                  child: Text(
                    t.editor.outline.fromPdf,
                    style: TextTheme.of(context).titleSmall,
                  ),
                ),
                for (final line in lines)
                  _line(
                    title: line.title,
                    level: line.level,
                    pageIndex: line.pageIndex,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
