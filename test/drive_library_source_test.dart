import 'dart:convert';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/drive/drive_library_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _file(String id, String name, {bool folder = false}) => {
  'id': id,
  'name': name,
  'mimeType': folder
      ? 'application/vnd.google-apps.folder'
      : 'application/octet-stream',
};

void main() {
  test('walks subfolders, follows pages and keeps only books', () async {
    final pages = <String, List<Map<String, Object?>>>{
      "'root' in parents and trashed = false|": [
        _file('b1', 'Zebra.epub'),
        _file('x1', 'notes.jpg'),
      ],
      "'root' in parents and trashed = false|p2": [
        _file('f1', 'Comics', folder: true),
      ],
      "'f1' in parents and trashed = false|": [
        _file('b2', 'Issue 1.CBR'),
        _file('f1', 'loop', folder: true),
      ],
    };
    final client = MockClient((request) async {
      final q = request.url.queryParameters['q']!;
      final token = request.url.queryParameters['pageToken'] ?? '';
      final files = pages['$q|$token']!;
      return http.Response(
        jsonEncode({
          'files': files,
          if (q.contains('root') && token.isEmpty) 'nextPageToken': 'p2',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final books = await DriveLibrarySource(
      drive.DriveApi(client),
      rootFolderId: 'root',
    ).listBooks();

    expect(books.map((b) => b.fileName), ['Issue 1.CBR', 'Zebra.epub']);
    expect(books.first.format, BookFormat.cbr);
    expect(books.first.folderPath, 'Comics');
    expect(books.first.displayTitle, 'Issue 1');
    expect(books.last.folderPath, '');
  });
}
