import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/duplicates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('extras are every copy but the one kept', () {
    final g = _find([
      _book('e', 'Dune.epub', md5: '1', day: 1),
      _book('p', 'Dune.pdf', md5: '2', day: 2, format: BookFormat.pdf),
    ]).single;
    expect(g.suggested, isEmpty);
    expect(g.extras.map((b) => b.driveFileId), ['p']);
  });

  test('dismissed duplicates stay quiet until a new one turns up', () async {
    SharedPreferences.setMockInitialValues({});
    final first = _find([
      _book('a', 'Circe.epub', md5: 'x'),
      _book('b', 'Circe (1).epub', md5: 'x', day: 2),
    ]);
    final alerts = DuplicateAlerts();
    expect(alerts.unseen(first), hasLength(1));
    await alerts.dismiss(first);

    final reloaded = DuplicateAlerts();
    await reloaded.load();
    expect(reloaded.unseen(first), isEmpty);
    // A third copy makes it a different group, so it's raised again.
    final more = _find([
      _book('a', 'Circe.epub', md5: 'x'),
      _book('b', 'Circe (1).epub', md5: 'x', day: 2),
      _book('c', 'Circe (2).epub', md5: 'x', day: 3),
    ]);
    expect(reloaded.unseen(more), hasLength(1));
  });
}
