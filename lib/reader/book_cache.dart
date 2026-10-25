import 'dart:async';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../library/book.dart';

/// Downloads books from Drive on first open and keeps them for offline use.
///
/// Files are keyed by Drive id and modified time, so an edited book in Drive
/// is fetched again. The least recently opened files are evicted once the
/// cache passes [maxBytes].
class BookCache {
  BookCache(this._api, this._dir, {this.maxBytes = 2 * 1024 * 1024 * 1024});

  final drive.DriveApi _api;
  final Directory _dir;
  final int maxBytes;

  File _fileFor(Book book) {
    final stamp = book.modifiedTime?.millisecondsSinceEpoch ?? 0;
    final ext = book.format.extensions.first;
    return File(p.join(_dir.path, '${book.driveFileId}_$stamp$ext'));
  }

  bool isCached(Book book) => _fileFor(book).existsSync();

  /// Returns the local copy of [book], downloading it if needed.
  ///
  /// [onProgress] receives 0 to 1 while downloading, when the size is known.
  Future<File> open(Book book, {void Function(double)? onProgress}) async {
    final file = _fileFor(book);
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
      return file;
    }
    await _dir.create(recursive: true);
    final media = await _api.files.get(
      book.driveFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final total = media.length ?? book.sizeBytes;
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    var received = 0;
    try {
      await for (final chunk in media.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      await partial.delete();
      rethrow;
    }
    await partial.rename(file.path);
    await _removeOlderVersions(book, keep: file);
    await evict(keep: file);
    return file;
  }

  Future<void> _removeOlderVersions(Book book, {required File keep}) async {
    await for (final entity in _dir.list()) {
      if (entity is File &&
          entity.path != keep.path &&
          p.basename(entity.path).startsWith('${book.driveFileId}_')) {
        await entity.delete();
      }
    }
  }

  /// Deletes least recently used files until the cache fits in [maxBytes].
  Future<void> evict({File? keep}) async {
    final files = <(File, FileStat)>[];
    await for (final entity in _dir.list()) {
      if (entity is File && !entity.path.endsWith('.part')) {
        files.add((entity, await entity.stat()));
      }
    }
    var total = files.fold<int>(0, (sum, f) => sum + f.$2.size);
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxBytes) break;
      if (file.path == keep?.path) continue;
      await file.delete();
      total -= stat.size;
    }
  }
}
