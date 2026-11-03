import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

/// Turns PDF files that arrive in the notes folder (for example by
/// uploading them to the synced Google Drive folder) into notes.
///
/// A PDF anywhere in the notes folder becomes a note with the same name,
/// in the same folder. The original PDF is then moved to [importedFolder],
/// so nothing is lost and it isn't imported twice. Folders whose names
/// start with a dot are skipped.
abstract final class PdfInbox {
  static final log = Logger('PdfInbox');

  /// Where imported PDFs are kept, mirroring their original folders.
  static const importedFolder = '/.imported';

  /// A PDF changed more recently than this may still be syncing, so it
  /// waits for the next check.
  static const settleTime = Duration(seconds: 20);

  /// How often to check while the app is open.
  static const checkInterval = Duration(minutes: 2);

  /// Makes a note at [notePath] (no extension) from the PDF at
  /// [pdfFile]. Returns whether it worked. Replaceable in tests, where
  /// PDFs can't be read.
  @visibleForTesting
  static Future<bool> Function(String notePath, File pdfFile) writeNote =
      _writeNote;

  static var _running = false;
  static Timer? _timer;
  static AppLifecycleListener? _lifecycle;

  /// Starts checking: soon after launch, whenever the app comes back to
  /// the foreground, and every [checkInterval] while it's open.
  static void start() {
    if (_lifecycle != null) return;
    Future.delayed(const Duration(seconds: 3), importAll);
    _timer = Timer.periodic(checkInterval, (_) => importAll());
    _lifecycle = AppLifecycleListener(
      onResume: () {
        importAll();
        _timer ??= Timer.periodic(checkInterval, (_) => importAll());
      },
      onPause: () {
        _timer?.cancel();
        _timer = null;
      },
    );
  }

  /// Imports every PDF waiting in the notes folder.
  /// Returns the paths (no extension) of the notes it made.
  static Future<List<String>> importAll({DateTime? now}) async {
    if (_running || !stows.autoImportPdfs.value) return const [];
    _running = true;
    try {
      final root = FileManager.getRootDirectory();
      if (!root.existsSync()) return const [];
      final waiting = <String>[];
      final settledBefore = (now ?? DateTime.now()).subtract(settleTime);
      await for (final entity in root.list(recursive: true)) {
        if (entity is! File) continue;
        final path = relativePath(entity.path, root.path);
        if (!isWaitingPdf(path)) continue;
        if (entity.lastModifiedSync().isAfter(settledBefore)) continue;
        waiting.add(path);
      }
      final created = <String>[];
      for (final path in waiting) {
        final note = await importOne(path);
        if (note != null) created.add(note);
      }
      if (created.isNotEmpty) log.info('Imported ${created.length} PDFs');
      return created;
    } catch (e, st) {
      log.severe('Checking for PDFs failed: $e', e, st);
      return const [];
    } finally {
      _running = false;
    }
  }

  /// [absolute] relative to [root], starting with a slash.
  @visibleForTesting
  static String relativePath(String absolute, String root) {
    var path = absolute.substring(root.length).replaceAll('\\', '/');
    if (!path.startsWith('/')) path = '/$path';
    return path;
  }

  /// Whether [path] (relative to the notes folder) is a PDF to import:
  /// not in a hidden folder, and not already imported.
  static bool isWaitingPdf(String path) {
    if (!path.toLowerCase().endsWith('.pdf')) return false;
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    // Hidden folders (including [importedFolder]) and hidden files
    return !parts.any((part) => part.startsWith('.'));
  }

  /// Imports the PDF at [pdfPath] (relative to the notes folder) and moves
  /// it into [importedFolder]. Returns the new note's path, or null.
  static Future<String?> importOne(String pdfPath) async {
    final folder = pdfPath.substring(0, pdfPath.lastIndexOf('/') + 1);
    final name = p.basenameWithoutExtension(pdfPath);
    final notePath = await FileManager.suffixFilePathToMakeItUnique(
      '$folder$name',
    );
    final pdfFile = FileManager.getFile(pdfPath);
    final ok = await writeNote(notePath, pdfFile);
    if (!ok) {
      log.warning('Could not import $pdfPath');
      return null;
    }
    await _moveToImported(pdfPath);
    return notePath;
  }

  static Future<void> _moveToImported(String pdfPath) async {
    final from = FileManager.getFile(pdfPath);
    var target = '$importedFolder$pdfPath';
    final extension = p.extension(target);
    final stem = target.substring(0, target.length - extension.length);
    for (var i = 1; FileManager.getFile(target).existsSync(); i++) {
      target = '$stem ($i)$extension';
    }
    final to = FileManager.getFile(target);
    await to.parent.create(recursive: true);
    await from.rename(to.path);
  }

  static Future<bool> _writeNote(String notePath, File pdfFile) async {
    final coreInfo = await EditorCoreInfo.loadFromFilePath(notePath);
    try {
      final pdfDocument = await coreInfo.assetCache.pdfDocumentCache.load(
        pdfFile.path,
      );
      if (pdfDocument.pages.isEmpty) return false;
      coreInfo.pages.clear();
      for (final pdfPage in pdfDocument.pages) {
        // Same page width as other notes, so pen sizes match
        final pageSize = Size(
          EditorPage.defaultWidth,
          EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
        );
        coreInfo.pages.add(
          EditorPage(
            size: pageSize,
            backgroundImage: PdfEditorImage(
              id: coreInfo.nextImageId++,
              pdfBytes: null,
              pdfFile: pdfFile,
              pdfPage: pdfPage.pageNumber - 1,
              pageIndex: coreInfo.pages.length,
              pageSize: pageSize,
              naturalSize: pdfPage.size,
              onMoveImage: null,
              onDeleteImage: null,
              onMiscChange: null,
              assetCache: coreInfo.assetCache,
            ),
          ),
        );
      }
      coreInfo.pages.add(EditorPage());

      final filePath = coreInfo.filePath + Editor.extension;
      final (bson, assets) = coreInfo.saveToBinary(currentPageIndex: 0);
      await Future.wait([
        FileManager.writeFile(filePath, bson, awaitWrite: true),
        for (int i = 0; i < assets.length; ++i)
          assets
              .getBytes(i)
              .then(
                (bytes) => FileManager.writeFile(
                  '$filePath.$i',
                  bytes,
                  awaitWrite: true,
                ),
              ),
      ]);
      return true;
    } catch (e, st) {
      log.severe('Importing ${pdfFile.path} failed: $e', e, st);
      return false;
    } finally {
      coreInfo.dispose();
    }
  }
}
