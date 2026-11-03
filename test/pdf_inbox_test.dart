import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/file_manager/pdf_inbox.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  FlavorConfig.setup();
  setupMockPathProvider();

  late Directory root;
  final made = <String>[];
  final old = DateTime.now().subtract(const Duration(hours: 1));

  setUp(() {
    root = Directory.systemTemp.createTempSync('pdf_inbox_');
    FileManager.documentsDirectory = root.path;
    stows.autoImportPdfs.value = true;
    made.clear();
    // Instead of reading the PDF (not possible in tests), write a stub note
    PdfInbox.writeNote = (notePath, pdfFile) async {
      made.add(notePath);
      FileManager.getFile(notePath + Editor.extension)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('note from ${pdfFile.path}');
      return true;
    };
  });
  tearDown(() => root.deleteSync(recursive: true));

  File put(String path, {DateTime? modified}) {
    final file = File('${root.path}$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('%PDF-1.4');
    file.setLastModifiedSync(modified ?? old);
    return file;
  }

  test('a PDF becomes a note with the same name, in the same folder', () async {
    put('/Fourier/booklet.pdf');
    final created = await PdfInbox.importAll();
    expect(created, ['/Fourier/booklet']);
    expect(File('${root.path}/Fourier/booklet.sbn2').existsSync(), isTrue);
  });

  test('the original moves to the hidden imported folder', () async {
    put('/Fourier/booklet.pdf');
    await PdfInbox.importAll();
    expect(File('${root.path}/Fourier/booklet.pdf').existsSync(), isFalse);
    expect(
      File('${root.path}/.imported/Fourier/booklet.pdf').existsSync(),
      isTrue,
    );
  });

  test('a PDF at the top of the folder works too', () async {
    put('/exam.PDF');
    expect(await PdfInbox.importAll(), ['/exam']);
  });

  test('hidden folders are left alone, so nothing is imported twice', () async {
    put('/.imported/old.pdf');
    put('/.trash/x.pdf');
    expect(await PdfInbox.importAll(), isEmpty);
  });

  test('a PDF that may still be syncing waits for the next check', () async {
    put('/fresh.pdf', modified: DateTime.now());
    expect(await PdfInbox.importAll(), isEmpty);
    expect(File('${root.path}/fresh.pdf').existsSync(), isTrue);
  });

  test("an existing note with the same name isn't overwritten", () async {
    File('${root.path}/notes.sbn2')
      ..createSync()
      ..writeAsStringSync('mine');
    put('/notes.pdf');
    final created = await PdfInbox.importAll();
    expect(created.single, isNot('/notes'));
    expect(File('${root.path}/notes.sbn2').readAsStringSync(), 'mine');
  });

  test('a failed import keeps the PDF where it was', () async {
    PdfInbox.writeNote = (_, _) async => false;
    put('/broken.pdf');
    expect(await PdfInbox.importAll(), isEmpty);
    expect(File('${root.path}/broken.pdf').existsSync(), isTrue);
  });

  test('turned off in settings, nothing happens', () async {
    stows.autoImportPdfs.value = false;
    put('/a.pdf');
    expect(await PdfInbox.importAll(), isEmpty);
  });

  test("the hidden imported folder doesn't show in the notes list", () async {
    put('/Fourier/booklet.pdf');
    await PdfInbox.importAll();
    final children = await FileManager.getChildrenOfDirectory('/');
    expect(children!.directories, contains('Fourier'));
    expect(children.directories, isNot(contains('.imported')));
  });
}
