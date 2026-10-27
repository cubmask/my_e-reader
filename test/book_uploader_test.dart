import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  late List<http.Request> requests;
  late BookUploader uploader;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('upload');
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      // A resumable upload: the first request returns where to send the
      // bytes, the second sends them and returns the new file.
      if (request.url.queryParameters['uploadType'] == 'resumable' &&
          request.method == 'POST') {
        return http.Response(
          '',
          200,
          headers: {'location': 'https://upload.example/session'},
        );
      }
      return http.Response(
        jsonEncode({
          'id': 'new-id',
          'name': 'Moby Dick.epub',
          'size': '4',
          'md5Checksum': 'abc',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    uploader = BookUploader(drive.DriveApi(client));
  });
  tearDown(() => dir.delete(recursive: true));

  Future<File> write(String name, List<int> bytes) =>
      File('${dir.path}/$name').writeAsBytes(bytes);

  test('uploads a book into the library folder', () async {
    final file = await write('x', utf8.encode('%PDF-1.7 hello'));
    final result = await uploader.upload(
      file,
      'Moby Dick.epub',
      folderId: 'folder',
    );
    expect(result.skipped, isNull);
    expect(result.book?.driveFileId, 'new-id');
    expect(result.book?.format, BookFormat.epub);
    final metadata = jsonDecode(requests.first.body) as Map;
    expect(metadata['parents'], ['folder']);
    expect(metadata['name'], 'Moby Dick.epub');
  });

  test('a file already in the library is not uploaded again', () async {
    final file = await write('x', [1, 2, 3]);
    // md5 of [1, 2, 3].
    const sum = '5289df737df57326fcdd22597afb1fac';
    final existing = Book(
      driveFileId: 'old',
      fileName: 'Old.epub',
      format: BookFormat.epub,
      folderPath: '',
      md5: sum,
    );
    final result = await uploader.upload(
      file,
      'Copy.epub',
      folderId: 'folder',
      existing: [existing],
    );
    expect(result.skipped, UploadSkip.alreadyThere);
    expect(result.book, same(existing));
    expect(requests, isEmpty);
  });

  test('a file with no extension is named by its contents', () async {
    final pdf = await write('a', utf8.encode('%PDF-1.4\n'));
    expect(await bookFileName(pdf, 'scan'), 'scan.pdf');
    final png = await write('b', [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
    final result = await uploader.upload(png, 'photo', folderId: 'f');
    expect(result.skipped, UploadSkip.notABook);
  });
}
