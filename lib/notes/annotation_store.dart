import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../reader/progress_store.dart' show ProgressRemote;

enum HighlightColor { yellow, green, blue, pink }

/// A highlight, a note, or a page bookmark in one book.
///
/// [location] is an EPUB CFI range for highlighted text, or `page:N` for a
/// bookmarked page in a PDF. Deleted annotations stay as tombstones so the
/// deletion syncs to other devices.
@immutable
class Annotation {
  const Annotation({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.location,
    required this.text,
    required this.note,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String location;

  /// The highlighted passage, empty for a page bookmark.
  final String text;
  final String note;
  final HighlightColor color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  /// A bookmark marks a place without highlighted text.
  bool get isBookmark => text.isEmpty;

  /// The page number of a PDF bookmark, if this is one.
  int? get page =>
      location.startsWith('page:') ? int.tryParse(location.substring(5)) : null;

  Annotation copyWith({String? note, HighlightColor? color, bool? deleted}) =>
      Annotation(
        id: id,
        bookId: bookId,
        bookTitle: bookTitle,
        location: location,
        text: text,
        note: note ?? this.note,
        color: color ?? this.color,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deleted: deleted ?? this.deleted,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'bookId': bookId,
    'bookTitle': bookTitle,
    'location': location,
    'text': text,
    'note': note,
    'color': color.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static Annotation? fromJson(Object? json) {
    if (json is! Map) return null;
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    final id = json['id'], bookId = json['bookId'], location = json['location'];
    if (id is! String ||
        bookId is! String ||
        location is! String ||
        createdAt == null ||
        updatedAt == null) {
      return null;
    }
    return Annotation(
      id: id,
      bookId: bookId,
      bookTitle: '${json['bookTitle'] ?? ''}',
      location: location,
      text: '${json['text'] ?? ''}',
      note: '${json['note'] ?? ''}',
      color:
          HighlightColor.values.asNameMap()[json['color']] ??
          HighlightColor.yellow,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: json['deleted'] == true,
    );
  }
}

/// Merges two annotation sets by id; the most recently updated copy wins,
/// including deletions.
Map<String, Annotation> mergeAnnotations(
  Map<String, Annotation> a,
  Map<String, Annotation> b,
) {
  final merged = {...a};
  b.forEach((id, theirs) {
    final ours = merged[id];
    if (ours == null || theirs.updatedAt.isAfter(ours.updatedAt)) {
      merged[id] = theirs;
    }
  });
  return merged;
}

Map<String, Annotation> decodeAnnotations(String text) {
  final json = jsonDecode(text);
  final list = json is Map ? json['annotations'] : null;
  if (list is! List) return {};
  final out = <String, Annotation>{};
  for (final item in list) {
    final a = Annotation.fromJson(item);
    if (a != null) out[a.id] = a;
  }
  return out;
}

String encodeAnnotations(Iterable<Annotation> annotations) => jsonEncode({
  'version': 1,
  'annotations': [for (final a in annotations) a.toJson()],
});

/// Highlights and notes for every book, kept locally and synced to Drive's
/// hidden app data folder like reading progress.
class AnnotationStore extends ChangeNotifier {
  AnnotationStore(this._localFile, this._remote);

  final File _localFile;
  final ProgressRemote? _remote;
  Map<String, Annotation> _all = {};
  Timer? _pushTimer;
  int _counter = 0;

  /// Live annotations, newest first.
  List<Annotation> get all =>
      _all.values.where((a) => !a.deleted).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Live annotations of one book, in creation order.
  List<Annotation> forBook(String bookId) =>
      all.where((a) => a.bookId == bookId).toList().reversed.toList();

  Annotation? byLocation(String bookId, String location) => all
      .where((a) => a.bookId == bookId && a.location == location)
      .firstOrNull;

  Future<void> load() async {
    if (await _localFile.exists()) {
      try {
        _all = decodeAnnotations(await _localFile.readAsString());
      } on FormatException {
        _all = {};
      }
    }
    notifyListeners();
    await sync();
  }

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    try {
      final text = await remote.read();
      if (text != null) {
        _all = mergeAnnotations(_all, decodeAnnotations(text));
        notifyListeners();
      }
      await _saveLocal();
      await remote.write(encodeAnnotations(_all.values));
    } catch (_) {
      // Offline: kept locally and pushed on the next sync.
    }
  }

  Future<Annotation> add({
    required String bookId,
    required String bookTitle,
    required String location,
    String text = '',
    String note = '',
    HighlightColor color = HighlightColor.yellow,
  }) async {
    final now = DateTime.now();
    final annotation = Annotation(
      id: '${now.microsecondsSinceEpoch.toRadixString(36)}-${_counter++}',
      bookId: bookId,
      bookTitle: bookTitle,
      location: location,
      text: text,
      note: note,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await _put(annotation);
    return annotation;
  }

  Future<void> update(Annotation annotation) => _put(annotation);

  Future<void> remove(Annotation annotation) =>
      _put(annotation.copyWith(deleted: true));

  Future<void> _put(Annotation annotation) async {
    _all[annotation.id] = annotation;
    notifyListeners();
    await _saveLocal();
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), sync);
  }

  Future<void> flush() async {
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await sync();
    }
  }

  Future<void> _saveLocal() async {
    await _localFile.parent.create(recursive: true);
    await _localFile.writeAsString(encodeAnnotations(_all.values));
  }
}

/// All annotations as Markdown, grouped by book.
String annotationsToMarkdown(List<Annotation> annotations) {
  final byBook = <String, List<Annotation>>{};
  for (final a in annotations) {
    (byBook[a.bookTitle] ??= []).add(a);
  }
  final out = StringBuffer();
  for (final MapEntry(key: title, value: items) in byBook.entries) {
    out.writeln('## $title\n');
    for (final a in items.reversed) {
      if (a.text.isNotEmpty) {
        out.writeln('> ${a.text.replaceAll('\n', '\n> ')}\n');
      } else {
        out.writeln(
          a.page != null ? 'Bookmark, page ${a.page}\n' : 'Bookmark\n',
        );
      }
      if (a.note.isNotEmpty) out.writeln('${a.note}\n');
    }
  }
  return out.toString().trimRight();
}
