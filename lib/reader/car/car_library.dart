import 'dart:io';

import '../../library/book.dart';

/// One book as the car lists it.
typedef CarBook = ({
  Book book,
  String title,
  String author,
  File? cover,
  double? fraction,
});

/// The library as Android Auto browses it: books in progress, books saved
/// for offline use, and collections. Only short lists, as the car allows.
class CarLibrary {
  CarLibrary({
    required this.books,
    required this.titleOf,
    required this.authorOf,
    required this.coverOf,
    required this.collectionsOf,
    required this.openedAt,
    required this.fractionOf,
    required this.isOffline,
  });

  final List<Book> books;
  final String Function(Book) titleOf;
  final String Function(Book) authorOf;
  final File? Function(Book) coverOf;
  final List<String> Function(Book) collectionsOf;

  /// When the book was last read, if ever.
  final DateTime? Function(Book) openedAt;
  final double? Function(Book) fractionOf;

  /// Whether the book's file is on the device, so it plays with no signal.
  final bool Function(Book) isOffline;

  /// The most the car is given in one list.
  static const maxItems = 30;

  CarBook _entry(Book b) => (
    book: b,
    title: titleOf(b),
    author: authorOf(b),
    cover: coverOf(b),
    fraction: fractionOf(b),
  );

  bool _finished(Book b) => (fractionOf(b) ?? 0) >= 0.995;

  /// Books started and not finished, most recently read first.
  List<CarBook> recent() {
    final started = [
      for (final b in books)
        if (openedAt(b) != null && !_finished(b)) b,
    ]..sort((a, b) => openedAt(b)!.compareTo(openedAt(a)!));
    return [for (final b in started.take(maxItems)) _entry(b)];
  }

  /// Books saved on the device, by title.
  List<CarBook> downloaded() {
    final saved = [
      for (final b in books)
        if (isOffline(b)) _entry(b),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return saved.take(maxItems).toList();
  }

  /// Every collection with at least one book, by name.
  List<String> collections() {
    final names = {for (final b in books) ...collectionsOf(b)}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.take(maxItems).toList();
  }

  /// The books in [collection], by title.
  List<CarBook> inCollection(String collection) {
    final found = [
      for (final b in books)
        if (collectionsOf(b).contains(collection)) _entry(b),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return found.take(maxItems).toList();
  }

  CarBook? byId(String driveFileId) {
    for (final b in books) {
      if (b.driveFileId == driveFileId) return _entry(b);
    }
    return null;
  }

  /// Books whose title or author matches every word of [query], such as
  /// "dune herbert", best first: title matches, then books in progress.
  List<CarBook> search(String query) {
    final words = _words(query);
    if (words.isEmpty) return recent();
    final scored = <(int, CarBook)>[];
    for (final b in books) {
      final title = _words(titleOf(b)).join(' ');
      final author = _words(authorOf(b)).join(' ');
      final all = '$title $author';
      if (!words.every(all.contains)) continue;
      var score = 0;
      if (title == words.join(' ')) score += 100;
      if (words.every(title.contains)) score += 10;
      if (openedAt(b) != null && !_finished(b)) score += 5;
      if (isOffline(b)) score += 1;
      scored.add((score, _entry(b)));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored.take(maxItems)) s.$2];
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
}
