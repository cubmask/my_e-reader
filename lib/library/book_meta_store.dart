import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../reader/progress_store.dart' show ProgressRemote;
import 'book.dart';

/// Details the user (or the book's own metadata) gives a book, beyond what
/// Drive knows: a proper title, an author and the collections it is in.
@immutable
class BookMeta {
  const BookMeta({
    this.title = '',
    this.author = '',
    this.collections = const [],
    required this.updatedAt,
  });

  /// Empty means "use the file name".
  final String title;
  final String author;
  final List<String> collections;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    if (title.isNotEmpty) 'title': title,
    if (author.isNotEmpty) 'author': author,
    if (collections.isNotEmpty) 'collections': collections,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static BookMeta? fromJson(Object? json) {
    if (json is! Map) return null;
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (updatedAt == null) return null;
    final title = json['title'];
    final author = json['author'];
    final collections = json['collections'];
    return BookMeta(
      title: title is String ? title : '',
      author: author is String ? author : '',
      collections: [
        if (collections is List)
          for (final c in collections)
            if (c is String && c.isNotEmpty) c,
      ],
      updatedAt: updatedAt,
    );
  }
}

/// Merges two maps keyed by Drive file id; the newer entry wins.
Map<String, BookMeta> mergeMeta(
  Map<String, BookMeta> a,
  Map<String, BookMeta> b,
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

Map<String, BookMeta> decodeMeta(String text) {
  final json = jsonDecode(text);
  if (json is! Map) return {};
  final books = json['books'];
  if (books is! Map) return {};
  return {
    for (final MapEntry(:key, :value) in books.entries)
      '$key': ?BookMeta.fromJson(value),
  };
}

String encodeMeta(Map<String, BookMeta> meta) => jsonEncode({
  'version': 1,
  'books': {for (final e in meta.entries) e.key: e.value.toJson()},
});

/// Titles, authors and collections, kept in a local file and synced to a
/// hidden `library.json` in Drive like reading progress.
class BookMetaStore extends ChangeNotifier {
  BookMetaStore(this._localFile, this._remote);

  final File _localFile;
  final ProgressRemote? _remote;
  Map<String, BookMeta> _meta = {};
  Timer? _pushTimer;

  BookMeta? operator [](String driveFileId) => _meta[driveFileId];

  String titleOf(Book book) {
    final title = _meta[book.driveFileId]?.title ?? '';
    return title.isEmpty ? book.displayTitle : title;
  }

  String authorOf(Book book) => _meta[book.driveFileId]?.author ?? '';

  List<String> collectionsOf(Book book) =>
      _meta[book.driveFileId]?.collections ?? const [];

  /// Every collection name in use, sorted.
  List<String> get collections =>
      {for (final m in _meta.values) ...m.collections}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  Future<void> load() async {
    if (await _localFile.exists()) {
      try {
        _meta = decodeMeta(await _localFile.readAsString());
      } on FormatException {
        _meta = {};
      }
    }
    await sync();
  }

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    try {
      final text = await remote.read();
      if (text != null) _meta = mergeMeta(_meta, decodeMeta(text));
      await _saveLocal();
      notifyListeners();
      await remote.write(encodeMeta(_meta));
    } catch (_) {
      // Offline: the local copy is kept and pushed on the next sync.
    }
  }

  Future<void> set(
    String driveFileId, {
    String? title,
    String? author,
    List<String>? collections,
  }) async {
    final old = _meta[driveFileId];
    _meta[driveFileId] = BookMeta(
      title: (title ?? old?.title ?? '').trim(),
      author: (author ?? old?.author ?? '').trim(),
      collections: collections ?? old?.collections ?? const [],
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _saveLocal();
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), sync);
  }

  /// Fills in the title and author read from the book itself, unless the
  /// user has already set them.
  Future<void> fillIn(String driveFileId, {String? title, String? author}) {
    final old = _meta[driveFileId];
    final newTitle = (old?.title.isEmpty ?? true) ? title?.trim() : null;
    final newAuthor = (old?.author.isEmpty ?? true) ? author?.trim() : null;
    if ((newTitle ?? '').isEmpty && (newAuthor ?? '').isEmpty) {
      return Future.value();
    }
    return set(driveFileId, title: newTitle, author: newAuthor);
  }

  Future<void> renameCollection(String from, String to) async {
    final name = to.trim();
    for (final MapEntry(:key, :value) in [..._meta.entries]) {
      if (!value.collections.contains(from)) continue;
      final renamed = <String>{
        for (final c in value.collections) c == from ? name : c,
      }.where((c) => c.isNotEmpty).toList();
      await set(key, collections: renamed);
    }
  }

  Future<void> deleteCollection(String name) => renameCollection(name, '');

  Future<void> flush() async {
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await sync();
    }
  }

  Future<void> _saveLocal() async {
    await _localFile.parent.create(recursive: true);
    await _localFile.writeAsString(encodeMeta(_meta));
  }
}
