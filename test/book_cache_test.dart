import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/reader/book_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Book _book(String id, int minute) => Book(
  driveFileId: id,
  fileName: '$id.epub',
  format: BookFormat.epub,
  folderPath: '',
  modifiedTime: DateTime.utc(2026, 1, 1, 0, minute),
);

void main() {
  late Directory dir;
  late int downloads;
  late BookCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('books');
    downloads = 0;
    final client = MockClient((request) async {
      downloads++;
      expect(request.url.queryParameters['alt'], 'media');
      return http.Response.bytes(
        List.filled(100, 7),
        200,
        headers: {
          'content-type': 'application/epub+zip',
          'content-length': '100',
        },
      );
    });
    cache = BookCache(drive.DriveApi(client), dir, streamMaxBytes: 250);
  });
  tearDown(() => dir.delete(recursive: true));

  test('downloads once, then serves the local copy', () async {
    final progress = <double>[];
    final first = await cache.open(_book('a', 1), onProgress: progress.add);
    final second = await cache.open(_book('a', 1));
    expect(downloads, 1);
    expect(second.path, first.path);
    expect(await first.length(), 100);
    expect(progress.last, 1.0);
  });

  test('a changed file in Drive replaces the old copy', () async {
    final old = await cache.open(_book('a', 1));
    final updated = await cache.open(_book('a', 2));
    expect(downloads, 2);
    expect(old.existsSync(), isFalse);
    expect(updated.existsSync(), isTrue);
  });

  test('evicts the least recently opened book past the size limit', () async {
    final a = await cache.open(_book('a', 1));
    await a.setLastModified(DateTime(2020));
    final b = await cache.open(_book('b', 1));
    await b.setLastModified(DateTime(2021));
    final c = await cache.open(_book('c', 1));
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isTrue);
    expect(c.existsSync(), isTrue);
  });

  test('a download is kept, survives trimming and can be removed', () async {
    final a = _book('a', 1);
    final streamed = await cache.open(a);
    expect(cache.isDownloaded(a), isFalse);

    await cache.download(a);
    expect(downloads, 1, reason: 'the streamed copy is moved, not refetched');
    expect(streamed.existsSync(), isFalse);
    expect(cache.isDownloaded(a), isTrue);
    expect(cache.isAvailableOffline(a), isTrue);
    final kept = await cache.open(a);
    expect(kept.parent.path, cache.downloads.path);

    for (final id in ['b', 'c', 'd']) {
      await cache.open(_book(id, 1));
    }
    expect(kept.existsSync(), isTrue);
    expect((await cache.usage()).downloads, 100);

    final reloaded = BookCache(
      drive.DriveApi(
        MockClient((_) async {
          throw StateError('no network');
        }),
      ),
      dir,
    );
    await reloaded.load();
    expect(reloaded.isDownloaded(a), isTrue);

    await cache.removeDownload(a);
    expect(cache.isDownloaded(a), isFalse);
    expect(kept.existsSync(), isFalse);
  });

  test('a book changed in Drive is fetched again on refresh', () async {
    await cache.download(_book('a', 1));
    final newer = _book('a', 2);
    expect(cache.isDownloaded(newer), isTrue);
    expect(cache.isAvailableOffline(newer), isFalse);
    await cache.refreshDownloads([newer]);
    expect(downloads, 2);
    expect(cache.isAvailableOffline(newer), isTrue);
    expect(cache.isAvailableOffline(_book('a', 1)), isFalse);
  });

  test('only PDFs that are not downloaded stream directly', () async {
    final pdf = Book(
      driveFileId: 'p',
      fileName: 'p.pdf',
      format: BookFormat.pdf,
      folderPath: '',
    );
    expect(cache.canStreamDirectly(pdf), isTrue);
    expect(cache.canStreamDirectly(_book('a', 1)), isFalse);
    await cache.download(pdf);
    expect(cache.canStreamDirectly(pdf), isFalse);
  });

  test('office documents are converted to EPUB by Drive', () async {
    final calls = <String>[];
    final client = MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/copy')) {
        expect(
          jsonDecode(request.body)['mimeType'],
          'application/vnd.google-apps.document',
        );
        return http.Response(
          '{"id":"tmp"}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/export')) {
        expect(request.url.queryParameters['mimeType'], 'application/epub+zip');
        return http.Response.bytes(
          List.filled(10, 1),
          200,
          headers: {'content-type': 'application/epub+zip'},
        );
      }
      return http.Response('', 204);
    });
    final office = BookCache(drive.DriveApi(client), dir);
    final file = await office.open(
      Book(
        driveFileId: 'w',
        fileName: 'Notes.docx',
        format: BookFormat.docx,
        folderPath: '',
      ),
    );
    expect(file.path, endsWith('.epub'));
    expect(await file.length(), 10);
    expect(calls, [
      'POST /drive/v3/files/w/copy',
      'GET /drive/v3/files/tmp/export',
      'DELETE /drive/v3/files/tmp',
    ]);
  });
}
