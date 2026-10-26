import '../core/book_format.dart';

/// A book file in the user's Google Drive library folder.
class Book {
  const Book({
    required this.driveFileId,
    required this.fileName,
    required this.format,
    required this.folderPath,
    this.sizeBytes,
    this.modifiedTime,
    this.thumbnailLink,
  });

  final String driveFileId;
  final String fileName;
  final BookFormat format;

  /// Path of the containing folder relative to the library root, '' for the root.
  final String folderPath;
  final int? sizeBytes;
  final DateTime? modifiedTime;

  /// A short-lived link to Drive's preview image, when Drive made one (it does
  /// for PDFs and images, rarely for ebooks).
  final String? thumbnailLink;

  /// File name without its extension, used until real metadata is read.
  String get displayTitle {
    final lower = fileName.toLowerCase();
    for (final ext in format.extensions) {
      if (lower.endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return fileName;
  }
}
