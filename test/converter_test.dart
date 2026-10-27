import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('offers every other text format, and none for comics', () {
    expect(
      ConvertTarget.forFormat(BookFormat.epub),
      isNot(contains(ConvertTarget.epub)),
    );
    expect(
      ConvertTarget.forFormat(BookFormat.pdf),
      contains(ConvertTarget.epub),
    );
    expect(ConvertTarget.forFormat(BookFormat.cbz), isEmpty);
    expect(ConvertTarget.forFormat(BookFormat.djvu), isEmpty);
    expect(
      convertedName('Dune: Messiah', ConvertTarget.pdf),
      'Dune_ Messiah.pdf',
    );
  });

  test('PDF lines become paragraphs, hyphenated words are joined', () {
    const text =
        'It was a bright cold day in April, and the clocks were\n'
        'striking thirteen. Winston Smith, his chin nuzzled into his\n'
        'breast in an effort to escape the vile wind, slipped quick-\n'
        'ly through the glass doors.\n'
        '\n'
        'Chapter <2>';
    expect(
      textToHtml(text),
      '<p>It was a bright cold day in April, and the clocks were striking '
      'thirteen. Winston Smith, his chin nuzzled into his breast in an effort '
      'to escape the vile wind, slipped quickly through the glass doors.</p>\n'
      '<p>Chapter &lt;2&gt;</p>\n',
    );
  });

  test('the page carries the title and author', () {
    final page = htmlPage(
      title: 'Emma',
      author: 'Jane Austen',
      body: '<p>x</p>',
    );
    expect(page, contains('<h1>Emma</h1>'));
    expect(page, contains('<i>Jane Austen</i>'));
  });

  test(
    'an office document is exported by Google Docs and cleaned up',
    () async {
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.url.path.endsWith('/copy')) {
          return http.Response(
            '{"id":"tmp"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.endsWith('/export')) {
          expect(req.url.queryParameters['mimeType'], 'application/pdf');
          return http.Response.bytes(
            [1, 2, 3],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }
        return http.Response('', 204);
      });
      final dir = await Directory.systemTemp.createTemp('convert');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/out.pdf');
      const book = Book(
        driveFileId: 'doc1',
        fileName: 'Report.docx',
        format: BookFormat.docx,
        folderPath: '',
      );
      await BookConverter(drive.DriveApi(client))
          .convert(book, null, BookFormat.docx, ConvertTarget.pdf, out);
      expect(await out.readAsBytes(), [1, 2, 3]);
      expect(calls, [
        'POST /drive/v3/files/doc1/copy',
        'GET /drive/v3/files/tmp/export',
        'DELETE /drive/v3/files/tmp',
      ]);
    },
  );
}
