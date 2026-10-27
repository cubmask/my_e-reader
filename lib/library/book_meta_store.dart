import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../reader/progress_store.dart' show ProgressRemote;
import 'book.dart';

/// Details the user, the book itself or an online source gives a book,
/// beyond what Drive knows: a proper title and author, collections, and the
/// descriptive details Calibre would fetch (description, publisher, ISBN...).
@immutable
class BookMeta {
  const BookMeta({
    this.title = '',
    this.author = '',
    this.collections = const [],
    this.series = '',
    this.seriesIndex,
    this.tags = const [],
    this.myRating,
    this.description = '',
    this.publisher = '',
    this.published = '',
    this.isbn = '',
    this.subjects = const [],
    this.pageCount,
    this.rating,
    this.source = '',
    this.lookedUpAt,
    required this.updatedAt,
  });

  /// Empty means "use the file name".
  final String title;
  final String author;
  final List<String> collections;

  /// The series the book belongs to, and its number in it (which may be
  /// fractional, like Calibre's 2.5 for a novella between books).
  final String series;
  final double? seriesIndex;

  /// The user's own tags.
  final List<String> tags;

  /// The user's own rating, 1 to 5 stars.
  final int? myRating;
  final String description;
  final String publisher;

  /// Publication date as the source gives it, often just a year.
  final String published;
  final String isbn;
  final List<String> subjects;
  final int? pageCount;

  /// Average reader rating out of 5.
  final double? rating;

  /// Where the online details came from, such as "Google Books".
  final String source;

  /// When the details were last looked up online, matched or not, so the
  /// automatic lookup doesn't repeat for every refresh.
  final DateTime? lookedUpAt;
  final DateTime updatedAt;

  BookMeta copyWith({
    String? title,
    String? author,
    List<String>? collections,
    String? series,
    double? Function()? seriesIndex,
    List<String>? tags,
    int? Function()? myRating,
    String? description,
    String? publisher,
    String? published,
    String? isbn,
    List<String>? subjects,
    int? pageCount,
    double? rating,
    String? source,
    DateTime? lookedUpAt,
  }) => BookMeta(
    title: (title ?? this.title).trim(),
    author: (author ?? this.author).trim(),
    collections: collections ?? this.collections,
    series: (series ?? this.series).trim(),
    seriesIndex: seriesIndex != null ? seriesIndex() : this.seriesIndex,
    tags: tags ?? this.tags,
    myRating: myRating != null ? myRating() : this.myRating,
    description: description ?? this.description,
    publisher: publisher ?? this.publisher,
    published: published ?? this.published,
    isbn: isbn ?? this.isbn,
    subjects: subjects ?? this.subjects,
    pageCount: pageCount ?? this.pageCount,
    rating: rating ?? this.rating,
    source: source ?? this.source,
    lookedUpAt: lookedUpAt ?? this.lookedUpAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object> toJson() => {
    if (title.isNotEmpty) 'title': title,
    if (author.isNotEmpty) 'author': author,
    if (collections.isNotEmpty) 'collections': collections,
    if (series.isNotEmpty) 'series': series,
    'seriesIndex': ?seriesIndex,
    if (tags.isNotEmpty) 'tags': tags,
    'myRating': ?myRating,
    if (description.isNotEmpty) 'description': description,
    if (publisher.isNotEmpty) 'publisher': publisher,
    if (published.isNotEmpty) 'published': published,
    if (isbn.isNotEmpty) 'isbn': isbn,
    if (subjects.isNotEmpty) 'subjects': subjects,
    'pageCount': ?pageCount,
    'rating': ?rating,
    if (source.isNotEmpty) 'source': source,
    if (lookedUpAt != null) 'lookedUpAt': lookedUpAt!.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static BookMeta? fromJson(Object? json) {
    if (json is! Map) return null;
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (updatedAt == null) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    List<String> list(String key) => [
      if (json[key] case final List items)
        for (final c in items)
          if (c is String && c.isNotEmpty) c,
    ];
    final pages = json['pageCount'];
    final rating = json['rating'];
    final index = json['seriesIndex'];
    final mine = json['myRating'];
    return BookMeta(
      title: text('title'),
      author: text('author'),
      collections: list('collections'),
      series: text('series'),
      seriesIndex: index is num ? index.toDouble() : null,
      tags: list('tags'),
      myRating: mine is int && mine >= 1 && mine <= 5 ? mine : null,
      description: text('description'),
      publisher: text('publisher'),
      published: text('published'),
      isbn: text('isbn'),
      subjects: list('subjects'),
      pageCount: pages is int ? pages : null,
      rating: rating is num ? rating.toDouble() : null,
      source: text('source'),
      lookedUpAt: DateTime.tryParse('${json['lookedUpAt']}'),
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

  /// Every tag in use, sorted.
  List<String> get tags =>
      {for (final m in _meta.values) ...m.tags}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Every series name in use, sorted.
  List<String> get series => {
    for (final m in _meta.values)
      if (m.series.isNotEmpty) m.series,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

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
    String? series,
    double? Function()? seriesIndex,
    List<String>? tags,
    int? Function()? myRating,
  }) async {
    await put(
      driveFileId,
      (_meta[driveFileId] ?? BookMeta(updatedAt: DateTime.now())).copyWith(
        title: title,
        author: author,
        collections: collections,
        series: series,
        seriesIndex: seriesIndex,
        tags: tags,
        myRating: myRating,
      ),
    );
  }

  /// Stores [meta] for the book as a whole, for example online details.
  Future<void> put(String driveFileId, BookMeta meta) async {
    _meta[driveFileId] = meta;
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
