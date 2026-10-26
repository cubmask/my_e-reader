import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book.dart';
import 'book_meta_store.dart';
import 'cover_store.dart';
import 'metadata_sources.dart';

/// Keeps book details and covers up to date from online sources, the way
/// Calibre's "Download metadata" does.
///
/// New books are looked up once, in the background, and only confident
/// matches are used; they fill in what is missing and never replace what
/// the user typed. From a book's details, the user can also search by hand
/// and pick a match, which replaces everything.
class MetadataUpdater extends ChangeNotifier {
  MetadataUpdater(this._service, this._meta, this._covers);

  final MetadataService _service;
  final BookMetaStore _meta;
  final CoverStore _covers;

  static const _autoKey = 'metadata.auto';
  bool _auto = true;
  bool _running = false;
  int _done = 0, _total = 0;

  /// Whether new books are looked up automatically.
  bool get auto => _auto;
  bool get running => _running;

  /// Progress of the current background run.
  (int done, int total) get progress => (_done, _total);

  Future<void> load() async {
    _auto = (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;
    notifyListeners();
  }

  Future<void> setAuto(bool value) async {
    _auto = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_autoKey, value);
  }

  /// What to search for: the title and author we already know, else a guess
  /// from the file name.
  MetadataQuery queryFor(Book book) {
    final meta = _meta[book.driveFileId];
    if (meta != null && meta.title.isNotEmpty) {
      return MetadataQuery(
        title: meta.title,
        author: meta.author,
        isbn: meta.isbn,
      );
    }
    final guess = MetadataQuery.fromFileName(book.displayTitle);
    return meta == null || meta.author.isEmpty
        ? guess
        : MetadataQuery(title: guess.title, author: meta.author);
  }

  /// Looks up every book not looked up before, one at a time.
  Future<void> lookUpNew(List<Book> books) async {
    if (!_auto || _running) return;
    final pending = [
      for (final b in books)
        if (_meta[b.driveFileId]?.lookedUpAt == null) b,
    ];
    if (pending.isEmpty) return;
    _running = true;
    _done = 0;
    _total = pending.length;
    notifyListeners();
    try {
      for (final book in pending) {
        if (!_auto) break;
        try {
          final result = await _service.best(queryFor(book));
          await _apply(book, result, replace: false);
        } catch (_) {
          // Offline or rate limited: stop and try again next refresh.
          break;
        }
        _done++;
        notifyListeners();
        // Be gentle with the free services.
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Candidates for the user to choose from, best first.
  Future<List<(MetadataResult, double)>> search(MetadataQuery query) =>
      _service.search(query);

  /// Uses [result] for [book], replacing its title, author, details and
  /// cover, as when the user picks a match.
  Future<void> choose(
    Book book,
    MetadataResult result,
    List<MetadataResult> others,
  ) async {
    final full = await _service.complete(result, others);
    await _apply(book, full, replace: true);
  }

  Future<void> _apply(
    Book book,
    MetadataResult? result, {
    required bool replace,
  }) async {
    final id = book.driveFileId;
    final old = _meta[id] ?? BookMeta(updatedAt: DateTime.now());
    if (result == null) {
      await _meta.put(id, old.copyWith(lookedUpAt: DateTime.now()));
      return;
    }
    String pick(String mine, String theirs) =>
        replace || mine.isEmpty ? theirs : mine;
    await _meta.put(
      id,
      old.copyWith(
        title: pick(old.title, result.title),
        author: pick(old.author, result.author),
        description: pick(old.description, result.description),
        publisher: pick(old.publisher, result.publisher),
        published: pick(old.published, result.published),
        isbn: pick(old.isbn, result.isbn),
        subjects: replace || old.subjects.isEmpty
            ? result.subjects
            : old.subjects,
        pageCount: replace
            ? result.pageCount
            : old.pageCount ?? result.pageCount,
        rating: replace ? result.rating : old.rating ?? result.rating,
        source: result.source,
        lookedUpAt: DateTime.now(),
      ),
    );
    final cover = result.coverUrl;
    if (cover != null) {
      await _covers.saveFromUrl(
        id,
        replace ? CoverKind.chosen : CoverKind.online,
        cover,
      );
    }
  }
}
