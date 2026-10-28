import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/core/file_type.dart' show sniffLength;
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<int> _zip({bool complete = true}) => [
  ...latin1.encode('PK\x03\x04'),
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  ...latin1.encode('mimetypeapplication/epub+zip'),
  ...List.filled(70000, 1),
  if (complete) ...latin1.encode('PK\x05\x06${'\x00' * 18}'),
];

List<int> _pdf({bool complete = true}) => [
  ...latin1.encode('%PDF-1.7\n'),
  ...List.filled(100000, 0x20),
  if (complete) ...latin1.encode('%%EOF\n'),
];

/// A Palm database with records at [offsets].
List<int> _mobi(List<int> offsets, int size) {
  final head = List.filled(78 + offsets.length * 8, 0);
  head.setAll(60, latin1.encode('BOOKMOBI'));
  head[76] = offsets.length >> 8;
  head[77] = offsets.length & 0xff;
  for (var i = 0; i < offsets.length; i++) {
    final o = offsets[i];
    head.setAll(78 + i * 8, [o >> 24, o >> 16 & 0xff, o >> 8 & 0xff, o & 0xff]);
  }
  return [...head, ...List.filled(size - head.length, 0)];
}

void main() {
  final files = <String, List<int>>{
    'good': _zip(),
    'cut': _zip(complete: false),
    'pdf': _pdf(),
    'cutpdf': _pdf(complete: false),
    'html': utf8.encode('<!DOCTYPE html><html><body>Sign in</body></html>'),
    'mobi': _mobi([100, 2000], 4000),
    'cutmobi': _mobi([100, 2000, 9000], 4000),
    'text': utf8.encode('Chapter 1\n\nIt was a dark and stormy night.'),
  };
  late List<String> requests;

  BookHealth health() => BookHealth(
    drive.DriveApi(
      MockClient((request) async {
        final id = request.url.pathSegments.last;
        final range = request.headers['range'];
        requests.add('$id ${range ?? 'all'}');
        if (id == 'offline') throw http.ClientException('no network');
        if (id == 'locked') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'This file cannot be downloaded.',
                'errors': [
                  {'reason': 'cannotDownloadAbusiveFile'},
                ],
              },
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        final bytes = files[id];
        if (bytes == null) {
          return http.Response(
            jsonEncode({
              'error': {'code': 404, 'message': 'File not found'},
            }),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        if (range == null) {
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        final [start, end] = range
            .substring('bytes='.length)
            .split('-')
            .map(int.parse)
            .toList();
        return http.Response.bytes(
          bytes.sublist(start, end + 1),
          206,
          headers: {
            'content-type': 'application/octet-stream',
            'content-range': 'bytes $start-$end/${bytes.length}',
            'content-length': '${end + 1 - start}',
          },
        );
      }),
    ),
    null,
  );

  setUp(() => requests = []);

  Book book(String id, BookFormat format, {int? size, int minute = 0}) => Book(
    driveFileId: id,
    fileName: '$id${format.extensions.first}',
    format: format,
    folderPath: '',
    sizeBytes: size ?? files[id]?.length ?? 1000,
    modifiedTime: DateTime.utc(2026, 1, 1, 0, minute),
  );

  Future<ProblemKind?> kindOf(String id, BookFormat format) async =>
      (await health().check(book(id, format)))?.kind;

  test('complete books pass', () async {
    expect(await kindOf('good', BookFormat.epub), isNull);
    expect(await kindOf('pdf', BookFormat.pdf), isNull);
    expect(await kindOf('mobi', BookFormat.mobi), isNull);
    expect(await kindOf('text', BookFormat.txt), isNull);
  });

  test('only the start and end of a large book are read', () async {
    await health().check(book('pdf', BookFormat.pdf));
    final size = files['pdf']!.length;
    expect(requests, [
      'pdf all',
      'pdf bytes=${size - sniffLength}-${size - 1}',
    ]);
  });

  test('books cut short are damaged', () async {
    expect(await kindOf('cut', BookFormat.epub), ProblemKind.damaged);
    expect(await kindOf('cutpdf', BookFormat.pdf), ProblemKind.damaged);
    expect(await kindOf('cutmobi', BookFormat.mobi), ProblemKind.damaged);
  });

  test('a web page named as a book is not a book', () async {
    final problem = await health().check(book('html', BookFormat.epub));
    expect(problem?.kind, ProblemKind.notABook);
    expect(problem?.message, contains('a web page (HTML), not an EPUB'));
  });

  test('a misnamed book that opens as another format passes', () async {
    expect(await kindOf('pdf', BookFormat.epub), isNull);
  });

  test('missing, refused and empty files', () async {
    expect(await kindOf('nothing', BookFormat.epub), ProblemKind.gone);
    expect(await kindOf('locked', BookFormat.pdf), ProblemKind.noAccess);
    final empty = await health().check(book('good', BookFormat.epub, size: 0));
    expect(empty?.kind, ProblemKind.empty);
  });

  test('a scan lists problems and skips books already checked', () async {
    final h = health();
    final books = [
      book('good', BookFormat.epub),
      book('cut', BookFormat.epub),
      book('html', BookFormat.pdf),
    ];
    await h.scan(books);
    expect(h.problemsIn(books).map((p) => p.$1.driveFileId), ['cut', 'html']);
    expect(h.lastScan, isNotNull);
    expect(h.scanning, isFalse);

    requests.clear();
    final changed = book('good', BookFormat.epub, minute: 5);
    expect(h.unchecked([changed, ...books.skip(1)]), [changed]);
    await h.scan([changed, ...books.skip(1)]);
    expect(requests.map((r) => r.split(' ').first).toSet(), {'good'});

    // A book removed from the library is forgotten.
    await h.scan([changed]);
    expect(h.problemsIn(books), isEmpty);
  });

  test('a scan stops when Drive cannot be reached', () async {
    final h = health();
    final books = [
      book('offline', BookFormat.epub),
      for (var i = 0; i < 20; i++) book('good', BookFormat.epub, minute: i),
    ];
    await h.scan(books);
    expect(h.scanError, contains('could not be reached'));
    expect(h.problemsIn(books), isEmpty);
    expect(h.done, lessThan(books.length));
  });

  test('failures in the reader are kept until the book opens', () async {
    final h = health();
    final b = book('good', BookFormat.epub);
    await h.readerFailed(b, 'foliate: no spine');
    expect(h.problemOf(b)?.kind, ProblemKind.reader);

    // The check cannot see this failure, so it does not clear it.
    await h.scan([b]);
    expect(h.problemOf(b)?.message, 'foliate: no spine');

    await h.readerFailed(b, const SocketException('offline'));
    expect(h.problemOf(b)?.message, 'foliate: no spine');

    await h.opened(b);
    expect(h.problemOf(b), isNull);
  });

  test('results survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('health');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/h.json');
    final b = book('cut', BookFormat.epub);
    final first = BookHealth(null, file);
    await first.readerFailed(b, 'broken');
    final second = BookHealth(null, file);
    await second.load();
    expect(second.problemOf(b)?.message, 'broken');
  });
}
