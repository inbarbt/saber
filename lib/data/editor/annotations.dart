import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

/// What a piece of writing is: ordinary writing, a note to yourself
/// (questions, things to check, reminders), or a general note
/// (an explanation of the material).
enum NoteKind {
  regular,
  toSelf,
  general;

  static NoteKind fromIndex(int? index) =>
      index != null && index >= 0 && index < values.length
      ? values[index]
      : regular;
}

/// The name of a kind of writing, for the user.
String noteKindLabel(NoteKind kind) => switch (kind) {
  NoteKind.regular => t.editor.notes.regular,
  NoteKind.toSelf => t.editor.notes.toSelf,
  NoteKind.general => t.editor.notes.general,
};

/// A group of strokes of one [kind] on a page, written together.
/// Strokes point to it by [id] (see [Stroke.noteGroup]).
class Annotation {
  new({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.name,
  });

  final int id;
  NoteKind kind;

  /// Milliseconds since the epoch, UTC.
  final int createdAt;

  /// A name given in the app, or null.
  String? name;

  /// When its last stroke was added, for grouping. Not saved.
  var lastStrokeAt = 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'k': kind.index,
    't': createdAt,
    if (name != null) 'n': name,
  };

  factory fromJson(Map<String, dynamic> json) => Annotation(
    id: (json['id'] as num).toInt(),
    kind: NoteKind.fromIndex((json['k'] as num?)?.toInt()),
    createdAt: (json['t'] as num?)?.toInt() ?? 0,
    name: json['n'] as String?,
  );
}

/// Grouping strokes into annotations, and which kinds are shown.
abstract final class Annotations {
  /// The kind new writing gets. Not saved: every session starts regular.
  static final current = ValueNotifier(NoteKind.regular);

  /// A stroke joins the last annotation of its kind on the page if it
  /// comes within this long of it...
  static const joinTime = Duration(seconds: 20);

  /// ...and within this distance (page units) of its strokes.
  static const joinDistance = 200.0;

  /// Whether strokes of [kind] are shown (and can be selected or erased).
  static bool isShown(NoteKind kind) =>
      !stows.hiddenNoteKinds.value.contains(kind.index.toString());

  static bool isStrokeShown(Stroke stroke) => isShown(stroke.noteKind);

  static void setShown(NoteKind kind, bool shown) {
    final hidden = {...stows.hiddenNoteKinds.value};
    if (shown) {
      hidden.remove(kind.index.toString());
    } else {
      hidden.add(kind.index.toString());
    }
    stows.hiddenNoteKinds.value = hidden.toList()..sort();
  }

  /// Gives [stroke] the [kind] and puts it in an annotation on the page:
  /// the last one of that kind if [stroke] is close to it in time and
  /// place, otherwise a new one added to [annotations].
  static void assign(
    Stroke stroke,
    NoteKind kind, {
    required List<Annotation> annotations,
    required List<Stroke> pageStrokes,
    required int now,
  }) {
    stroke.noteKind = kind;
    if (kind == NoteKind.regular) {
      stroke.noteGroup = null;
      return;
    }
    final last = annotations.lastWhereOrNull((a) => a.kind == kind);
    if (last != null &&
        now - last.lastStrokeAt <= joinTime.inMilliseconds &&
        _isNear(stroke, pageStrokes.where((s) => s.noteGroup == last.id))) {
      stroke.noteGroup = last.id;
      last.lastStrokeAt = now;
      return;
    }
    final annotation = Annotation(
      id: nextId(annotations),
      kind: kind,
      createdAt: now,
    )..lastStrokeAt = now;
    annotations.add(annotation);
    stroke.noteGroup = annotation.id;
  }

  /// Gives all of [strokes] the [kind], as one new annotation (or none,
  /// for regular writing). Used to classify a selection afterwards.
  static Annotation? classify(
    List<Stroke> strokes,
    NoteKind kind, {
    required List<Annotation> annotations,
    required int now,
  }) {
    Annotation? annotation;
    if (kind != NoteKind.regular) {
      annotation = Annotation(
        id: nextId(annotations),
        kind: kind,
        createdAt: now,
      );
      annotations.add(annotation);
    }
    for (final stroke in strokes) {
      stroke.noteKind = kind;
      stroke.noteGroup = annotation?.id;
    }
    return annotation;
  }

  /// Annotations that still have strokes on the page.
  static List<Annotation> inUse(
    List<Annotation> annotations,
    List<Stroke> pageStrokes,
  ) {
    final used = {for (final s in pageStrokes) s.noteGroup};
    return [
      for (final a in annotations)
        if (used.contains(a.id)) a,
    ];
  }

  static int nextId(List<Annotation> annotations) =>
      annotations.fold(0, (m, a) => max(m, a.id)) + 1;

  static bool _isNear(Stroke stroke, Iterable<Stroke> group) {
    final bounds = _boundsOf(group);
    if (bounds == null) return false;
    final mine = _boundsOf([stroke]);
    if (mine == null) return false;
    return bounds.inflate(joinDistance).overlaps(mine);
  }

  static Rect? _boundsOf(Iterable<Stroke> strokes) {
    Rect? bounds;
    for (final stroke in strokes) {
      for (final p in stroke.lowQualityPolygon) {
        if (!p.isFinite) continue;
        final r = Rect.fromLTWH(p.dx, p.dy, 0, 0);
        bounds = bounds == null ? r : bounds.expandToInclude(r);
      }
    }
    return bounds;
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (int i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
