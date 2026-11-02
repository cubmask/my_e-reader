import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/reader/car/car_library.dart';
import 'package:ebook_reader/reader/car/car_player.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book(String id, [BookFormat format = BookFormat.epub]) => Book(
  driveFileId: id,
  fileName: '$id.${format.extensions.first.substring(1)}',
  format: format,
  folderPath: '',
);

void main() {
  final dune = _book('dune');
  final emma = _book('emma');
  final atlas = _book('atlas', BookFormat.pdf);
  final comic = _book('comic', BookFormat.cbz);
  const titles = {
    'dune': 'Dune',
    'emma': 'Emma',
    'atlas': 'Cloud Atlas',
    'comic': 'Comic',
  };
  const authors = {'dune': 'Frank Herbert', 'emma': 'Jane Austen'};
  final opened = {
    'dune': DateTime(2026, 10, 30),
    'atlas': DateTime(2026, 10, 31),
    'emma': DateTime(2026, 10, 1),
  };
  const fractions = {'dune': 0.42, 'atlas': 0.1, 'emma': 1.0};

  final library = CarLibrary(
    books: [dune, emma, atlas, comic],
    titleOf: (b) => titles[b.driveFileId]!,
    authorOf: (b) => authors[b.driveFileId] ?? '',
    coverOf: (_) => null,
    collectionsOf: (b) => b.driveFileId == 'dune' ? ['Sci-fi'] : const [],
    openedAt: (b) => opened[b.driveFileId],
    fractionOf: (b) => fractions[b.driveFileId],
    isOffline: (b) => b.driveFileId != 'atlas',
  );

  List<String> ids(List<CarBook> books) => [
    for (final b in books) b.book.driveFileId,
  ];

  test('continue lists unfinished books, latest first', () {
    expect(ids(library.recent()), ['atlas', 'dune']);
    expect(library.recent().last.fraction, 0.42);
  });

  test('downloaded lists books on the device by title', () {
    expect(ids(library.downloaded()), ['comic', 'dune', 'emma']);
  });

  test('collections and their books', () {
    expect(library.collections(), ['Sci-fi']);
    expect(ids(library.inCollection('Sci-fi')), ['dune']);
  });

  test('search matches title and author words', () {
    expect(ids(library.search('dune')), ['dune']);
    expect(ids(library.search('herbert DUNE')), ['dune']);
    expect(ids(library.search('austen')), ['emma']);
    expect(library.search('tolkien'), isEmpty);
    // No words: carry on with what was being read.
    expect(ids(library.search('  ')), ['atlas', 'dune']);
  });

  test('only books read aloud can play in the car', () {
    expect(canReadInCar(BookFormat.epub), isTrue);
    expect(canReadInCar(BookFormat.docx), isTrue);
    expect(canReadInCar(BookFormat.pdf), isTrue);
    expect(canReadInCar(BookFormat.cbz), isFalse);
    expect(canReadInCar(BookFormat.djvu), isFalse);
  });
}
