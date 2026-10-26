import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/duplicates.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(
  String id,
  String name, {
  String? md5,
  int day = 1,
  BookFormat format = BookFormat.epub,
}) => Book(
  driveFileId: id,
  fileName: name,
  format: format,
  folderPath: '',
  md5: md5,
  createdTime: DateTime.utc(2026, 1, day),
);

List<DuplicateGroup> _find(
  List<Book> books, {
  Map<String, String> authors = const {},
  Set<String> opened = const {},
}) => findDuplicates(
  books,
  titleOf: (b) => b.displayTitle,
  authorOf: (b) => authors[b.driveFileId] ?? '',
  opened: (b) => opened.contains(b.driveFileId),
);

void main() {
  test('identical files are grouped, keeping the oldest', () {
    final groups = _find([
      _book('new', 'Circe (1).epub', md5: 'abc', day: 5),
      _book('old', 'Circe.epub', md5: 'abc', day: 2),
      _book('other', 'Dune.epub', md5: 'def'),
    ]);
    final g = groups.single;
    expect(g.identical, isTrue);
    expect(g.books.map((b) => b.driveFileId), ['old', 'new']);
    expect(g.suggested.map((b) => b.driveFileId), ['new']);
  });

  test('the copy being read is kept', () {
    final g = _find(
      [
        _book('old', 'Circe.epub', md5: 'abc', day: 2),
        _book('read', 'Circe copy.epub', md5: 'abc', day: 5),
      ],
      opened: {'read'},
    ).single;
    expect(g.books.first.driveFileId, 'read');
  });

  test('the same title in two formats is grouped but not suggested', () {
    final g = _find([
      _book('e', 'The Hobbit.epub', md5: '1'),
      _book('p', 'Hobbit (Illustrated).pdf', md5: '2', format: BookFormat.pdf),
    ]).single;
    expect(g.identical, isFalse);
    expect(g.suggested, isEmpty);
  });

  test('the same title by different authors is not a duplicate', () {
    final groups = _find(
      [_book('a', 'Collected Poems.epub'), _book('b', 'Collected Poems.pdf')],
      authors: {'a': 'Sylvia Plath', 'b': 'Philip Larkin'},
    );
    expect(groups, isEmpty);
  });

  test('normalizeTitle ignores case, subtitles, brackets and articles', () {
    expect(normalizeTitle('The Hobbit: There and Back Again'), 'hobbit');
    expect(normalizeTitle('hobbit (Retail) [2012]'), 'hobbit');
    expect(normalizeTitle('A'), 'a');
  });
}
