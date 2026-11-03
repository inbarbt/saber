/// An entry in a note's own table of contents (also used as a bookmark).
///
/// Entries are kept on the page they point to, so they move with the page
/// when pages are moved, and go away with it when it's deleted.
class OutlineEntry {
  new({required this.title, this.level = 0});

  String title;

  /// How deep it's nested: 0 is the top level.
  int level;

  static const maxLevel = 3;

  Map<String, dynamic> toJson() => {'t': title, if (level != 0) 'l': level};

  factory fromJson(Map<String, dynamic> json) => OutlineEntry(
    title: json['t'] as String? ?? '',
    level: ((json['l'] as num?)?.toInt() ?? 0).clamp(0, maxLevel),
  );

  OutlineEntry copy() => OutlineEntry(title: title, level: level);
}
