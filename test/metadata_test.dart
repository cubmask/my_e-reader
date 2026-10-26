import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_meta_store.dart';
import 'package:ebook_reader/library/cover_store.dart';
import 'package:ebook_reader/library/metadata_sources.dart';
import 'package:ebook_reader/library/metadata_updater.dart';
import 'package:ebook_reader/library/new_books.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _google = {
  'items': [
    {
      'volumeInfo': {
        'title': 'Piranesi',
        'authors': ['Susanna Clarke'],
        'publisher': 'Bloomsbury',
        'publishedDate': '2020-09-15',
        'description': '<p>Piranesi lives in the <b>House</b>.</p>',
        'industryIdentifiers': [
          {'type': 'ISBN_10', 'identifier': '1526622424'},
          {'type': 'ISBN_13', 'identifier': '9781526622426'},
        ],
        'pageCount': 272,
        'categories': ['Fiction'],
        'averageRating': 4.5,
        'imageLinks': {
          'thumbnail':
              'http://books.google.com/books/content?id=x&zoom=1&edge=curl',
        },
      },
    },
    {
      'volumeInfo': {
        'title': 'Jonathan Strange & Mr Norrell',
        'authors': ['Susanna Clarke'],
      },
    },
  ],
};

const _openLibrary = {
  'docs': [
    {
      'key': '/works/OL1W',
      'title': 'Piranesi',
      'author_name': ['Susanna Clarke'],
      'cover_i': 123,
      'isbn': ['1526622424', '9781526622426'],
      'first_publish_year': 2020,
      'subject': ['Fantasy', 'Labyrinths'],
    },
  ],
};

/// Answers like Google Books and Open Library, counting requests.
MockClient _fake({bool offline = false, List<Uri>? log}) =>
    MockClient((r) async {
      log?.add(r.url);
      if (offline) throw const SocketException('offline');
      return switch (r.url.host) {
        'www.googleapis.com' => http.Response(jsonEncode(_google), 200),
        'openlibrary.org' when r.url.path == '/search.json' => http.Response(
          jsonEncode(_openLibrary),
          200,
        ),
        'openlibrary.org' => http.Response(
          jsonEncode({
            'description': {'value': 'From Open Library.'},
          }),
          200,
        ),
        _ => http.Response.bytes(
          Uint8List(2000),
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      };
    });

Book _book(String id, String name, {DateTime? created}) => Book(
  driveFileId: id,
  fileName: name,
  format: BookFormat.epub,
  folderPath: '',
  createdTime: created,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataQuery.fromFileName', () {
    test('reads "Title - Author" names', () {
      final q = MetadataQuery.fromFileName('Piranesi - Susanna Clarke');
      expect(q.title, 'Piranesi');
      expect(q.author, 'Susanna Clarke');
    });

    test('drops brackets and underscores and finds an ISBN', () {
      final q = MetadataQuery.fromFileName(
        'Dune_(Retail)_[Frank Herbert] 9780441013593',
      );
      expect(q.title, 'Dune');
      expect(q.isbn, '9780441013593');
    });

    test('reads "Title by Author" names', () {
      final q = MetadataQuery.fromFileName('Dune by Frank Herbert');
      expect(q.title, 'Dune');
      expect(q.author, 'Frank Herbert');
    });
  });

  group('matchScore', () {
    const piranesi = MetadataResult(
      source: 'x',
      title: 'Piranesi',
      authors: ['Susanna Clarke'],
    );
    test('is high for the same title and author', () {
      expect(
        matchScore(
          const MetadataQuery(title: 'Piranesi', author: 'Susanna Clarke'),
          piranesi,
        ),
        greaterThanOrEqualTo(MetadataService.confident),
      );
    });

    test('is low for a different book', () {
      expect(
        matchScore(const MetadataQuery(title: 'Dune'), piranesi),
        lessThan(MetadataService.confident),
      );
    });
  });

  group('sources', () {
    test('Google Books results are parsed and cleaned', () async {
      final results = await GoogleBooksSource(_fake())
          .search(const MetadataQuery(title: 'Piranesi'));
      final r = results.first;
      expect(r.title, 'Piranesi');
      expect(r.author, 'Susanna Clarke');
      expect(r.isbn, '9781526622426');
      expect(r.description, 'Piranesi lives in the House.');
      expect(r.pageCount, 272);
      expect(r.coverUrl!.scheme, 'https');
      expect(r.coverUrl.toString(), isNot(contains('edge=curl')));
    });

    test('Open Library results are parsed', () async {
      final results = await OpenLibrarySource(_fake())
          .search(const MetadataQuery(title: 'Piranesi'));
      final r = results.single;
      expect(r.isbn, '9781526622426');
      expect(r.published, '2020');
      expect(
        r.coverUrl.toString(),
        'https://covers.openlibrary.org/b/id/123-L.jpg',
      );
    });

    test('the best match is completed from both sources', () async {
      final best = await MetadataService(
        _fake(),
      ).best(const MetadataQuery(title: 'Piranesi', author: 'Susanna Clarke'));
      expect(best, isNotNull);
      expect(best!.title, 'Piranesi');
      expect(best.publisher, isNotEmpty);
      expect(best.subjects, isNotEmpty);
      expect(best.description, isNotEmpty);
    });

    test('no confident match gives null', () async {
      final best = await MetadataService(_fake())
          .best(const MetadataQuery(title: 'Some Unrelated Book'));
      expect(best, isNull);
    });

    test('being offline is an error, not "no match"', () async {
      expect(
        MetadataService(_fake(offline: true))
            .search(const MetadataQuery(title: 'Piranesi')),
        throwsStateError,
      );
    });
  });

  group('MetadataUpdater', () {
    late Directory dir;
    late BookMetaStore meta;
    late CoverStore covers;
    late List<Uri> log;
    late MetadataUpdater updater;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('meta');
      meta = BookMetaStore(File('${dir.path}/m.json'), null);
      log = [];
      final client = _fake(log: log);
      covers = CoverStore(Directory('${dir.path}/covers'), null, web: client);
      updater = MetadataUpdater(MetadataService(client), meta, covers);
      await updater.load();
    });
    tearDown(() => dir.delete(recursive: true));

    test('fills in what is missing and keeps what the user typed', () async {
      await meta.set('p', title: 'Piranesi', author: 'Susanna Clarke');
      await meta.put('p', meta['p']!.copyWith(publisher: 'My edition'));
      await updater.lookUpNew([_book('p', 'piranesi.epub')]);

      final m = meta['p']!;
      expect(m.publisher, 'My edition');
      expect(m.isbn, '9781526622426');
      expect(m.description, isNotEmpty);
      expect(m.lookedUpAt, isNotNull);
      expect(covers.bestKind('p'), CoverKind.online);
    });

    test('looks each book up only once', () async {
      final book = _book('p', 'Piranesi - Susanna Clarke.epub');
      await updater.lookUpNew([book]);
      final count = log.length;
      await updater.lookUpNew([book]);
      expect(log.length, count);
    });

    test('does nothing when turned off', () async {
      await updater.setAuto(false);
      await updater.lookUpNew([_book('p', 'Piranesi.epub')]);
      expect(log, isEmpty);
    });

    test('a chosen match replaces everything', () async {
      await meta.set('p', title: 'My title', author: 'Me');
      final candidates = await updater.search(
        const MetadataQuery(title: 'Piranesi'),
      );
      await updater.choose(_book('p', 'p.epub'), candidates.first.$1, [
        for (final (r, _) in candidates) r,
      ]);
      expect(meta['p']!.title, 'Piranesi');
      expect(meta['p']!.author, 'Susanna Clarke');
      expect(covers.bestKind('p'), CoverKind.chosen);
    });
  });

  group('NewBooks', () {
    final now = DateTime(2026, 10, 26);

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('lists recent, unopened books newest first', () async {
      final books = [
        _book('old', 'a', created: now.subtract(const Duration(days: 30))),
        _book('one', 'b', created: now.subtract(const Duration(days: 3))),
        _book('two', 'c', created: now.subtract(const Duration(days: 1))),
        _book('read', 'd', created: now.subtract(const Duration(days: 1))),
        _book('none', 'e'),
      ];
      final fresh = NewBooks().of(
        books,
        opened: (b) => b.driveFileId == 'read',
        now: now,
      );
      expect(fresh.map((b) => b.driveFileId), ['two', 'one']);
    });

    test('dismissed books stay hidden after a restart', () async {
      final book = _book('x', 'x', created: now);
      final newBooks = NewBooks();
      await newBooks.dismiss([book]);
      final reloaded = NewBooks();
      await reloaded.load();
      expect(reloaded.of([book], opened: (_) => false, now: now), isEmpty);
    });
  });
}
