import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/settings/settings_directory_selector.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/flavor_config.dart';

void main() {
  group('androidTreeUriToPath:', () {
    test('folder on primary storage', () {
      expect(
        androidTreeUriToPath(
          'content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FSaber',
        ),
        '/storage/emulated/0/Documents/Saber',
      );
    });

    test('root of primary storage', () {
      expect(
        androidTreeUriToPath(
          'content://com.android.externalstorage.documents/tree/primary%3A',
        ),
        '/storage/emulated/0',
      );
    });

    test('folder on an SD card', () {
      expect(
        androidTreeUriToPath(
          'content://com.android.externalstorage.documents/tree/1234-ABCD%3ANotes',
        ),
        '/storage/1234-ABCD/Notes',
      );
    });

    test('plain path is unchanged', () {
      expect(androidTreeUriToPath('/home/user/notes'), '/home/user/notes');
    });

    test('other providers are rejected', () {
      expect(
        androidTreeUriToPath(
          'content://com.google.android.apps.docs.storage/tree/abc',
        ),
        isNull,
      );
    });
  });

  group('Note timestamps:', () {
    FlavorConfig.setup();

    test('new note gets a creation time', () {
      final before = DateTime.now().toUtc().millisecondsSinceEpoch;
      final note = EditorCoreInfo(filePath: '');
      final after = DateTime.now().toUtc().millisecondsSinceEpoch;
      expect(note.createdAt, inInclusiveRange(before, after));
      expect(note.modifiedAt, isNull);
    });

    test('saving sets the modified time', () {
      final note = EditorCoreInfo(filePath: '');
      note.saveToBinary(currentPageIndex: null);
      expect(note.modifiedAt, isNotNull);
      expect(note.modifiedAt, greaterThanOrEqualTo(note.createdAt!));
    });

    test('timestamps survive a save and load', () async {
      final note = EditorCoreInfo(filePath: '');
      final (bson, _) = note.saveToBinary(currentPageIndex: null);

      final loaded = await EditorCoreInfo.loadFromFileContents(
        bsonBytes: bson,
        path: '/tests/timestamps',
        onlyFirstPage: false,
      );
      expect(loaded.createdAt, note.createdAt);
      expect(loaded.modifiedAt, note.modifiedAt);
    });

    test('old notes without timestamps still load', () {
      final note = EditorCoreInfo.fromJson(
        {'v': 19},
        filePath: '',
        onlyFirstPage: false,
      );
      expect(note.createdAt, isNull);
      expect(note.modifiedAt, isNull);
    });
  });
}
