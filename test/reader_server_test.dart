import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/reader/reader_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/reader/index.html') throw FlutterError('missing $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode('<html>')));
  }
}

void main() {
  test('serves the page and the book only under its secret path', () async {
    final dir = await Directory.systemTemp.createTemp('server');
    addTearDown(() => dir.delete(recursive: true));
    final book = File('${dir.path}/b.epub')..writeAsBytesSync([1, 2, 3]);
    final server = ReaderServer(bundle: _Bundle());
    addTearDown(server.close);

    final page = await server.serve(book);
    expect(page.host, '127.0.0.1');

    final html = await http.get(page);
    expect(html.statusCode, 200);
    expect(html.body, '<html>');
    expect(html.headers['content-type'], startsWith('text/html'));

    final bytes = await http.get(page.resolve(ReaderServer.bookPath));
    expect(bytes.bodyBytes, [1, 2, 3]);

    final guess = await http.get(page.replace(path: '/index.html'));
    expect(guess.statusCode, 404);
    final missing = await http.get(page.resolve('nope.js'));
    expect(missing.statusCode, 404);
  });

  test('relays byte ranges of Drive files', () async {
    final seen = <http.BaseRequest>[];
    final drive = MockClient((request) async {
      seen.add(request);
      return http.Response.bytes(
        [5, 6],
        206,
        headers: {
          'content-type': 'application/pdf',
          'content-range': 'bytes 4-5/100',
        },
      );
    });
    final server = ReaderServer(bundle: _Bundle(), drive: drive);
    addTearDown(server.close);

    final url = await server.driveUrl('abc_-1');
    final reply = await http.get(url, headers: {'range': 'bytes=4-5'});
    expect(reply.statusCode, 206);
    expect(reply.bodyBytes, [5, 6]);
    expect(reply.headers['content-range'], 'bytes 4-5/100');
    expect(seen.single.url.path, '/drive/v3/files/abc_-1');
    expect(seen.single.url.queryParameters['alt'], 'media');
    expect(seen.single.headers['range'], 'bytes=4-5');

    final bad = await http.get(url.resolve('a%2Fb'));
    expect(bad.statusCode, 404);
    expect(seen, hasLength(1));
  });

  test('passes Drive errors on without the error body', () async {
    final drive = MockClient(
      (request) async => http.Response(
        '{"error": {"code": 403}}',
        403,
        headers: {'content-type': 'application/json'},
      ),
    );
    final server = ReaderServer(bundle: _Bundle(), drive: drive);
    addTearDown(server.close);

    final reply = await http.get(await server.driveUrl('abc'));
    expect(reply.statusCode, 403);
    expect(reply.bodyBytes, isEmpty);
  });

  test('asks Drive for unencoded bytes', () async {
    final seen = <http.BaseRequest>[];
    final drive = MockClient((request) async {
      seen.add(request);
      return http.Response.bytes([1], 200);
    });
    final server = ReaderServer(bundle: _Bundle(), drive: drive);
    addTearDown(server.close);

    await http.get(await server.driveUrl('abc'));
    expect(seen.single.headers['accept-encoding'], 'identity');
  });
}
