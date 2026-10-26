import 'book.dart';

/// Books that look like copies of one another.
class DuplicateGroup {
  const DuplicateGroup(this.books, {required this.identical});

  /// The copies, the one to keep first.
  final List<Book> books;

  /// Whether every file has the same contents, rather than only the same
  /// title (often the same book in two formats).
  final bool identical;

  /// The copies [findDuplicates] suggests deleting: for identical files,
  /// all but the first; for books that only share a title, none, since a
  /// second format may be wanted.
  List<Book> get suggested => identical ? books.sublist(1) : const [];
}

/// Groups the books in [books] that are duplicates: files with the same
/// contents, or the same title by the same author.
///
/// [titleOf] and [authorOf] give the best known title and author.
/// [opened] says whether a book has been read, so that copy is kept.
List<DuplicateGroup> findDuplicates(
  List<Book> books, {
  required String Function(Book) titleOf,
  required String Function(Book) authorOf,
  bool Function(Book)? opened,
}) {
  // Union-find over the two kinds of match.
  final parent = List<int>.generate(books.length, (i) => i);
  int root(int i) {
    while (parent[i] != i) {
      i = parent[i] = parent[parent[i]];
    }
    return i;
  }

  void join(int a, int b) => parent[root(a)] = root(b);

  final byChecksum = <String, int>{};
  final byTitle = <String, List<int>>{};
  for (var i = 0; i < books.length; i++) {
    if (books[i].md5 case final md5? when md5.isNotEmpty) {
      if (byChecksum[md5] case final j?) join(i, j);
      byChecksum[md5] = i;
    }
    final title = normalizeTitle(titleOf(books[i]));
    if (title.isNotEmpty) (byTitle[title] ??= []).add(i);
  }
  for (final same in byTitle.values) {
    for (var x = 0; x < same.length; x++) {
      for (var y = x + 1; y < same.length; y++) {
        // Two known, different authors mean two different books.
        final a = _surname(authorOf(books[same[x]]));
        final b = _surname(authorOf(books[same[y]]));
        if (a.isEmpty || b.isEmpty || a == b) join(same[x], same[y]);
      }
    }
  }

  final groups = <int, List<Book>>{};
  for (var i = 0; i < books.length; i++) {
    (groups[root(i)] ??= []).add(books[i]);
  }
  bool read(Book b) => opened?.call(b) ?? false;
  final result = [
    for (final copies in groups.values)
      if (copies.length > 1)
        DuplicateGroup(
          // Keep the copy being read, then the one that arrived first.
          copies..sort((a, b) {
            if (read(a) != read(b)) return read(a) ? -1 : 1;
            final at = a.createdTime ?? a.modifiedTime ?? DateTime(9999);
            final bt = b.createdTime ?? b.modifiedTime ?? DateTime(9999);
            return at.compareTo(bt);
          }),
          identical:
              copies.first.md5 != null &&
              copies.every((b) => b.md5 == copies.first.md5),
        ),
  ];
  result.sort(
    (a, b) =>
        titleOf(a.books.first)
            .toLowerCase()
            .compareTo(titleOf(b.books.first).toLowerCase()),
  );
  return result;
}

/// A title reduced to its words: no subtitle, brackets, punctuation, case
/// or leading article, so "The Hobbit (Illustrated)" matches "hobbit".
String normalizeTitle(String title) {
  final words = title
      .split(':')
      .first
      .toLowerCase()
      .replaceAll(RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length > 1 && const {'the', 'a', 'an'}.contains(words.first)) {
    words.removeAt(0);
  }
  return words.join(' ');
}

String _surname(String author) {
  final first = author.split(RegExp(r'[,;&]| and ')).first.trim();
  return first.split(RegExp(r'\s+')).last.toLowerCase();
}
