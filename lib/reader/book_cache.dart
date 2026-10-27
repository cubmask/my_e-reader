import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../core/book_format.dart';
import '../library/book.dart';

/// Where book files live on the device.
///
/// Books are streamed by default: PDFs are paged in straight from Drive (see
/// `ReaderServer.driveUrl`), and other formats, which the reader needs whole,
/// go to a small temporary cache that is trimmed to [streamMaxBytes]. A book
/// the user downloads for offline reading goes to [downloads] instead and is
/// kept until they remove it.
///
/// Files are keyed by Drive id and modified time, so a book edited in Drive is
/// fetched again. Office documents (DOC, DOCX, RTF, ODT) are converted by
/// Google Drive: a temporary Google Docs copy is exported as EPUB, then
/// deleted. The stored file is that EPUB.
class BookCache extends ChangeNotifier {
  BookCache(
    this._api,
    Directory root, {
    this.streamMaxBytes = 300 * 1024 * 1024,
  }) : _root = root,
       _streams = Directory(p.join(root.path, 'stream')),
       downloads = Directory(p.join(root.path, 'downloads'));

  final drive.DriveApi _api;
  final Directory _root;
  final Directory _streams;
  final Directory downloads;
  final int streamMaxBytes;

  /// Drive ids of downloaded books, filled by [load].
  final _downloaded = <String>{};

  /// Download progress (0 to 1, or null when the size is unknown) by Drive id.
  final _active = <String, double?>{};

  /// Drive ids of books deleted from Drive in this session.
  final _deleted = <String>{};
  Set<String> get deleted => UnmodifiableSetView(_deleted);

  Future<void> load() async {
    // Earlier versions kept every opened book in the root; those copies are
    // replaced by explicit downloads.
    if (await _root.exists()) {
      await for (final entity in _root.list()) {
        if (entity is File) await entity.delete();
      }
    }
    _downloaded.clear();
    if (await downloads.exists()) {
      await for (final entity in downloads.list()) {
        final name = p.basename(entity.path);
        if (entity is File && !name.endsWith('.part')) {
          _downloaded.add(name.substring(0, name.lastIndexOf('_')));
        }
      }
    }
    notifyListeners();
  }

  String _name(Book book) {
    final stamp = book.modifiedTime?.millisecondsSinceEpoch ?? 0;
    final ext = book.format.needsConversion
        ? '.epub'
        : book.format.extensions.first;
    return '${book.driveFileId}_$stamp$ext';
  }

  File _downloadFile(Book book) => File(p.join(downloads.path, _name(book)));
  File _streamFile(Book book) => File(p.join(_streams.path, _name(book)));

  /// Whether the book is kept for offline reading.
  bool isDownloaded(Book book) => _downloaded.contains(book.driveFileId);

  /// Whether the current version of the book is on the device, so it opens
  /// without a connection.
  bool isAvailableOffline(Book book) => _downloadFile(book).existsSync();

  /// Download progress if the book is downloading now.
  bool isDownloading(Book book) => _active.containsKey(book.driveFileId);
  double? downloadProgress(Book book) => _active[book.driveFileId];

  /// Whether the reader can page this book in from Drive without a local copy.
  bool canStreamDirectly(Book book) =>
      book.format == BookFormat.pdf && !isAvailableOffline(book);

  /// Returns a local copy of [book]: the download if there is one, otherwise
  /// a temporary streamed copy.
  ///
  /// [onProgress] receives 0 to 1 while fetching, when the size is known.
  Future<File> open(Book book, {void Function(double)? onProgress}) async {
    final kept = _downloadFile(book);
    if (await kept.exists()) return kept;
    final file = _streamFile(book);
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
      return file;
    }
    await _fetch(book, file, onProgress);
    await _removeOlderVersions(_streams, book, keep: file);
    await trimStreams(keep: file);
    return file;
  }

  /// Keeps [book] on the device for offline reading.
  Future<void> download(Book book) async {
    if (isDownloading(book)) return;
    _downloaded.add(book.driveFileId);
    _active[book.driveFileId] = null;
    notifyListeners();
    try {
      final file = _downloadFile(book);
      final streamed = _streamFile(book);
      await downloads.create(recursive: true);
      if (await streamed.exists()) {
        await streamed.rename(file.path);
      } else if (!await file.exists()) {
        await _fetch(book, file, (v) {
          _active[book.driveFileId] = v;
          notifyListeners();
        });
      }
      await _removeOlderVersions(downloads, book, keep: file);
    } catch (_) {
      _downloaded.remove(book.driveFileId);
      rethrow;
    } finally {
      _active.remove(book.driveFileId);
      notifyListeners();
    }
  }

  /// Frees the space a downloaded book uses; it streams again from then on.
  Future<void> removeDownload(Book book) async {
    _downloaded.remove(book.driveFileId);
    notifyListeners();
    await _removeOlderVersions(downloads, book);
  }

  /// Deletes [book] from Google Drive for good, skipping the Drive trash,
  /// along with its copies on this device.
  ///
  /// Throws a [drive.DetailedApiRequestError] when Drive refuses, such as
  /// for a file shared by someone else.
  Future<void> deleteFromDrive(Book book) async {
    try {
      await _api.files.delete(book.driveFileId, supportsAllDrives: true);
    } on drive.DetailedApiRequestError catch (e) {
      // Already gone is as good as deleted.
      if (e.status != 404) rethrow;
    }
    _deleted.add(book.driveFileId);
    _downloaded.remove(book.driveFileId);
    notifyListeners();
    await _removeOlderVersions(downloads, book);
    await _removeOlderVersions(_streams, book);
  }

  Future<void> removeAllDownloads() async {
    _downloaded.clear();
    notifyListeners();
    if (await downloads.exists()) await downloads.delete(recursive: true);
  }

  /// Bytes used by downloads and by the temporary streaming cache.
  Future<({int downloads, int streams})> usage() async =>
      (downloads: await _size(downloads), streams: await _size(_streams));

  Future<void> clearStreams() async {
    if (await _streams.exists()) await _streams.delete(recursive: true);
    notifyListeners();
  }

  /// Downloads the books that changed in Drive since they were downloaded.
  Future<void> refreshDownloads(Iterable<Book> books) async {
    for (final book in books) {
      if (isDownloaded(book) && !isAvailableOffline(book)) {
        try {
          await download(book);
        } catch (_) {
          // Offline or gone: the old copy stays until the next refresh.
        }
      }
    }
  }

  Future<void> _fetch(
    Book book,
    File file,
    void Function(double)? onProgress,
  ) async {
    await file.parent.create(recursive: true);
    if (book.format.needsConversion) {
      await _convert(book, file, onProgress);
    } else {
      final media = await _api.files.get(
        book.driveFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      await _write(media, file, media.length ?? book.sizeBytes, onProgress);
    }
  }

  Future<void> _convert(
    Book book,
    File file,
    void Function(double)? onProgress,
  ) async {
    final copy = await _api.files.copy(
      drive.File(
        name: '${book.displayTitle} (My E-Reader conversion)',
        mimeType: _googleDoc,
      ),
      book.driveFileId,
      $fields: 'id',
    );
    await _exportEpub(copy.id!, file, onProgress);
  }

  /// Returns an EPUB of [source], an office document whose contents are
  /// [actual] although [book]'s name says otherwise, converted by Drive.
  ///
  /// Drive picks how to import a copy from the file's recorded type, which
  /// comes from its name, so the local bytes are uploaded with their real
  /// type instead.
  Future<File> convertMisnamed(
    Book book,
    File source,
    BookFormat actual, {
    void Function(double)? onProgress,
  }) async {
    final file = File(p.setExtension(source.path, '.epub'));
    if (await file.exists()) return file;
    final upload = await _api.files.create(
      drive.File(
        name: '${book.displayTitle} (My E-Reader conversion)',
        mimeType: _googleDoc,
      ),
      uploadMedia: drive.Media(
        source.openRead(),
        await source.length(),
        contentType: _officeTypes[actual]!,
      ),
      $fields: 'id',
    );
    await _exportEpub(upload.id!, file, onProgress);
    return file;
  }

  /// Exports the Google Doc [docId] as EPUB to [file], then deletes the doc.
  Future<void> _exportEpub(
    String docId,
    File file,
    void Function(double)? onProgress,
  ) async {
    try {
      final media = await _api.files.export(
        docId,
        'application/epub+zip',
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      await _write(media, file, media.length, onProgress);
    } finally {
      await _api.files.delete(docId).catchError((_) {});
    }
  }

  static const _googleDoc = 'application/vnd.google-apps.document';
  static const _officeTypes = {
    BookFormat.doc: 'application/msword',
    BookFormat.docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    BookFormat.rtf: 'application/rtf',
    BookFormat.odt: 'application/vnd.oasis.opendocument.text',
  };

  Future<void> _write(
    drive.Media media,
    File file,
    int? total,
    void Function(double)? onProgress,
  ) async {
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
  }

  Future<void> _removeOlderVersions(
    Directory dir,
    Book book, {
    File? keep,
  }) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File &&
          entity.path != keep?.path &&
          p.basename(entity.path).startsWith('${book.driveFileId}_')) {
        await entity.delete();
      }
    }
  }

  /// Deletes the least recently opened streamed books until the temporary
  /// cache fits in [streamMaxBytes]. Downloads are never touched.
  Future<void> trimStreams({File? keep}) async {
    if (!await _streams.exists()) return;
    final files = <(File, FileStat)>[];
    await for (final entity in _streams.list()) {
      if (entity is File && !entity.path.endsWith('.part')) {
        files.add((entity, await entity.stat()));
      }
    }
    var total = files.fold<int>(0, (sum, f) => sum + f.$2.size);
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= streamMaxBytes) break;
      if (file.path == keep?.path) continue;
      await file.delete();
      total -= stat.size;
    }
  }

  static Future<int> _size(Directory dir) async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
