import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/reader/reader_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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
}
