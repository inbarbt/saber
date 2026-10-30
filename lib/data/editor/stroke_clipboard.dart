import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';

/// Saber+'s own clipboard for handwriting.
///
/// Strokes are kept as their saved form, so they can be pasted on any page
/// of any note for as long as the app stays open. Images can only be pasted
/// back into the note they came from, because their files live with that
/// note.
abstract final class StrokeClipboard {
  static List<Map<String, dynamic>> _strokes = const [];
  static List<EditorImage> _images = const [];
  static String? _sourceFilePath;
  static int? _sourcePageIndex;

  static bool get isEmpty => _strokes.isEmpty && _images.isEmpty;
  static bool get isNotEmpty => !isEmpty;

  /// Whether pasting into [filePath] would include images.
  static bool hasImagesFor(String filePath) =>
      _images.isNotEmpty && filePath == _sourceFilePath;

  static void copy({
    required List<Stroke> strokes,
    required List<EditorImage> images,
    required String filePath,
    required int pageIndex,
  }) {
    _strokes = [for (final stroke in strokes) stroke.toJson()];
    _images = [for (final image in images) image.copy()];
    _sourceFilePath = filePath;
    _sourcePageIndex = pageIndex;
  }

  /// Where pasted content goes relative to where it was copied:
  /// shifted slightly when pasted onto the same page, so the copy is
  /// visible, and at the same spot anywhere else.
  static Offset pasteOffset({
    required String filePath,
    required int pageIndex,
  }) {
    final samePlace =
        filePath == _sourceFilePath && pageIndex == _sourcePageIndex;
    return samePlace ? const Offset(25, -25) : Offset.zero;
  }

  /// New strokes for [page], built from the clipboard.
  static List<Stroke> strokesFor({
    required int pageIndex,
    required EditorPage page,
    Offset offset = Offset.zero,
  }) => [
    for (final json in _strokes)
      Stroke.fromJson(
        Map<String, dynamic>.of(json)..['i'] = pageIndex,
        fileVersion: EditorCoreInfo.sbnVersion,
        pageIndex: pageIndex,
        page: page,
      )..shift(offset),
  ];

  /// New images for [pageIndex] of the note at [filePath].
  /// Empty unless that is the note they were copied from.
  /// [nextImageId] hands out ids for the new images.
  static List<EditorImage> imagesFor({
    required String filePath,
    required int pageIndex,
    required int Function() nextImageId,
    Offset offset = Offset.zero,
  }) {
    if (!hasImagesFor(filePath)) return const [];
    return [
      for (final image in _images)
        image.copy()
          ..id = nextImageId()
          ..pageIndex = pageIndex
          ..dstRect = image.dstRect.shift(offset),
    ];
  }

  @visibleForTesting
  static void clear() {
    _strokes = const [];
    _images = const [];
    _sourceFilePath = null;
    _sourcePageIndex = null;
  }
}
