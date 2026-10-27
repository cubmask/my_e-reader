import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../core/book_format.dart';
import '../core/file_type.dart';
import 'book.dart';

/// Why a file was not added.
enum UploadSkip { notABook, alreadyThere }

/// The outcome for one file: the book in Drive (new, or the copy already
/// there), or why it was skipped.
typedef UploadResult = ({String name, Book? book, UploadSkip? skipped});

/// Adds books from the device to the library folder in Google Drive.
class BookUploader {
  BookUploader(this._api);

  final drive.DriveApi _api;

  /// Uploads [file] as [name] into [folderId].
  ///
  /// A file whose name says nothing is named by its contents. A file whose
  /// contents are already in [existing] is not uploaded again; its copy is
  /// returned instead, so it can be opened.
  Future<UploadResult> upload(
    File file,
    String name, {
    required String folderId,
    List<Book> existing = const [],
  }) async {
    final named = await bookFileName(file, name);
    if (named == null) {
      return (name: name, book: null, skipped: UploadSkip.notABook);
    }
    final md5sum = (await md5.bind(file.openRead()).first).toString();
    for (final b in existing) {
      if (b.md5 == md5sum) {
        return (name: name, book: b, skipped: UploadSkip.alreadyThere);
      }
    }
    final length = await file.length();
    final created = await _api.files.create(
      drive.File(name: named, parents: [folderId]),
      uploadMedia: drive.Media(file.openRead(), length),
      uploadOptions: drive.UploadOptions.resumable,
      $fields: 'id, name, size, modifiedTime, createdTime, md5Checksum',
    );
    return (
      name: name,
      book: Book(
        driveFileId: created.id!,
        fileName: created.name ?? named,
        format: BookFormat.fromFileName(created.name ?? named)!,
        folderPath: '',
        sizeBytes: int.tryParse(created.size ?? '') ?? length,
        modifiedTime: created.modifiedTime,
        createdTime: created.createdTime,
        md5: created.md5Checksum ?? md5sum,
      ),
      skipped: null,
    );
  }
}

/// The name to store [file] under: [name] when it is a book's, else [name]
/// with the extension its contents call for; null when it isn't a book.
Future<String?> bookFileName(File file, String name) async {
  if (BookFormat.fromFileName(name) != null) return name;
  final format = (await sniffFile(file))?.format;
  if (format == null) return null;
  return '$name${format.extensions.first}';
}
