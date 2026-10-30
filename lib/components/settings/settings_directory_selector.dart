import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/font_fallbacks.dart';

class SettingsDirectorySelector extends StatelessWidget {
  const new({
    super.key,
    required this.title,
    required this.icon,
    this.afterChange,
    this.isUnsupported = true,
  });

  final String title;
  final IconData icon;
  final ValueChanged<Color?>? afterChange;
  final bool isUnsupported;

  void onPressed(BuildContext context) async {
    final oldDir = Directory(FileManager.documentsDirectory);
    final oldDirIsEmpty = oldDir.existsSync()
        ? oldDir.listSync().isEmpty
        : true;
    await showAdaptiveDialog(
      context: context,
      builder: (context) => DirectorySelector(
        title: title,
        initialDirectory: FileManager.documentsDirectory,
        mustBeEmpty: !oldDirIsEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onPressed(context),
      child: ListTile(
        contentPadding: const .symmetric(vertical: 4, horizontal: 16),
        leading: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          child: Icon(icon, key: ValueKey(icon)),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontStyle:
                stows.customDataDir.value != stows.customDataDir.defaultValue
                ? FontStyle.italic
                : null,
          ),
        ),
        subtitle: ValueListenableBuilder(
          valueListenable: stows.customDataDir,
          builder: (context, _, _) => Text(
            FileManager.documentsDirectory,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class DirectorySelector extends StatefulWidget {
  const new({
    super.key,
    required this.title,
    required this.initialDirectory,
    this.mustBeEmpty = true,
    this.mustBeDoneSyncing = true,
  });

  final String title;
  final String initialDirectory;
  final bool mustBeEmpty;
  final bool mustBeDoneSyncing;

  @override
  State<DirectorySelector> createState() => _DirectorySelectorState();
}

class _DirectorySelectorState extends State<DirectorySelector> {
  late String _directory = widget.initialDirectory;
  late var _isEmpty = true;

  Future<void> _pickDir() async {
    // A folder in shared storage needs "All files access" on Android 11+,
    // otherwise dart:io can't read or write it.
    if (defaultTargetPlatform == .android) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) return;
    }

    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: widget.title,
      initialDirectory: _directory,
      androidOptions: defaultTargetPlatform == .android
          ? const FilePickerAndroidOptions(
              safOptions: .new(
                grant: .lifetime,
                accessMode: .readWrite,
                persistGrant: true,
              ),
            )
          : const .new(),
    );

    if (picked == null) return;

    // The Android picker returns a content:// URI, which dart:io can't use.
    final directory = androidTreeUriToPath(picked);
    if (directory == null) return;
    if (directory == _directory) return;

    final dir = Directory(directory);
    _directory = directory;
    _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _pickDefaultDir() async {
    final directory = await FileManager.getDefaultDocumentsDirectory();

    final dir = Directory(directory);
    _directory = directory;
    _isEmpty = dir.existsSync() ? dir.listSync().isEmpty : true;

    if (!mounted) return;
    setState(() {});
  }

  void _onConfirm() {
    stows.customDataDir.value = _directory;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final emptyError = widget.mustBeEmpty && !_isEmpty;
    final syncingError =
        widget.mustBeDoneSyncing &&
        (syncer.uploader.numPending > 0 || syncer.downloader.numPending > 0);
    final anyErrors = emptyError || syncingError;

    return AdaptiveAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: .min,
        children: [
          Text(
            t.settings.customDataDir.unsupported,
            style: TextStyle(color: colorScheme.error),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _directory,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'FiraMono',
                    fontFamilyFallback: saberMonoFontFallbacks,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.folder), onPressed: _pickDir),
              if (stows.customDataDir.value != null)
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _pickDefaultDir,
                ),
            ],
          ),
          if (emptyError)
            Text(
              t.settings.customDataDir.mustBeEmpty,
              style: TextStyle(color: colorScheme.error),
            ),
          if (syncingError)
            Text(
              t.settings.customDataDir.mustBeDoneSyncing,
              style: TextStyle(color: colorScheme.error),
            ),
        ],
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => context.pop(),
          child: Text(t.settings.customDataDir.cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: anyErrors ? null : _onConfirm,
          child: Text(t.settings.customDataDir.select),
        ),
      ],
    );
  }
}

/// Converts an Android folder picker result into a normal file path.
///
/// For example
/// `content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FSaber`
/// becomes `/storage/emulated/0/Documents/Saber`.
/// Anything that is already a path is returned unchanged.
/// Returns null for URIs that don't map to local storage.
String? androidTreeUriToPath(String picked) {
  if (!picked.startsWith('content://')) return picked;

  final uri = Uri.parse(picked);
  if (uri.host != 'com.android.externalstorage.documents') return null;

  final segments = uri.pathSegments;
  final treeIndex = segments.indexOf('tree');
  if (treeIndex == -1 || treeIndex + 1 >= segments.length) return null;

  // e.g. "primary:Documents/Saber" (already percent-decoded)
  final documentId = segments[treeIndex + 1];
  final colon = documentId.indexOf(':');
  if (colon == -1) return null;

  final volume = documentId.substring(0, colon);
  final relative = documentId.substring(colon + 1);
  final root = volume == 'primary' ? '/storage/emulated/0' : '/storage/$volume';
  return relative.isEmpty ? root : '$root/$relative';
}
