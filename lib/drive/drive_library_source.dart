import 'package:googleapis/drive/v3.dart' as drive;

import '../core/book_format.dart';
import '../library/book.dart';
import '../library/library_source.dart';

const _folderMimeType = 'application/vnd.google-apps.folder';

/// Lists the books in a Google Drive folder and all of its subfolders.
class DriveLibrarySource implements LibrarySource {
  DriveLibrarySource(this._api, {required this.rootFolderId});

  final drive.DriveApi _api;
  final String rootFolderId;

  @override
  Future<List<Book>> listBooks() async {
    final books = <Book>[];
    // Breadth-first walk; a visited set guards against shortcut cycles.
    final pending = <(String id, String path)>[(rootFolderId, '')];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final (folderId, path) = pending.removeAt(0);
      if (!visited.add(folderId)) continue;
      await for (final file in _children(folderId)) {
        final name = file.name ?? '';
        if (file.mimeType == _folderMimeType) {
          pending.add((file.id!, path.isEmpty ? name : '$path/$name'));
          continue;
        }
        final format = BookFormat.fromFileName(name);
        if (format == null) continue;
        books.add(
          Book(
            driveFileId: file.id!,
            fileName: name,
            format: format,
            folderPath: path,
            sizeBytes: int.tryParse(file.size ?? ''),
            modifiedTime: file.modifiedTime,
            thumbnailLink: file.thumbnailLink,
            md5: file.md5Checksum,
            createdTime: file.createdTime,
          ),
        );
      }
    }
    books.sort(
      (a, b) =>
          a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
    );
    return books;
  }

  Stream<drive.File> _children(String folderId) async* {
    String? pageToken;
    do {
      final page = await _api.files.list(
        q: "'$folderId' in parents and trashed = false",
        $fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, createdTime, thumbnailLink, md5Checksum)',
        pageSize: 1000,
        pageToken: pageToken,
        spaces: 'drive',
      );
      yield* Stream.fromIterable(page.files ?? const []);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
  }
}
