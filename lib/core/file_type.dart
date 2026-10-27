import 'dart:convert';
import 'dart:io';

import 'book_format.dart';

/// What a file really holds, judged by its first bytes rather than its name.
class FileType {
  const FileType(this.label, [this.format]);

  /// A name for the reader, such as "an EPUB book" or "a web page (HTML)".
  final String label;

  /// The format to open it as, or null when the reader cannot open this kind
  /// of file at all.
  final BookFormat? format;

  @override
  String toString() => label;
}

/// How many leading bytes [sniffFileType] looks at.
const sniffLength = 64 * 1024;

/// Identifies a file from its first bytes, or returns null when they match
/// nothing known.
FileType? sniffFileType(List<int> head) {
  bool startsWith(List<int> magic, [int at = 0]) {
    if (head.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[at + i] != magic[i]) return false;
    }
    return true;
  }

  final text = latin1.decode(head, allowInvalid: true);
  final start = text.substring(0, text.length.clamp(0, 1024));
  final lowerStart = start.trimLeft().toLowerCase();

  // PDFium accepts the header anywhere in the first kilobyte.
  if (start.contains('%PDF-')) return const FileType('a PDF', BookFormat.pdf);
  if (text.startsWith('AT&TFORM') &&
      (_has(text, 'DJVU', 12) || _has(text, 'DJVM', 12))) {
    return const FileType('a DjVu document', BookFormat.djvu);
  }
  if (text.startsWith('PK\x03\x04')) return _sniffZip(text);
  if (text.startsWith('Rar!\x1a\x07')) {
    return const FileType('a RAR archive', BookFormat.rar);
  }
  if (_has(text, 'BOOKMOBI', 60) || _has(text, 'TEXtREAd', 60)) {
    return const FileType('a Kindle (MOBI/AZW) book', BookFormat.mobi);
  }
  if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    return const FileType('a Word document (DOC)', BookFormat.doc);
  }
  if (text.startsWith(r'{\rtf')) {
    return const FileType('a rich text document (RTF)', BookFormat.rtf);
  }
  if (start.contains('<FictionBook')) {
    return const FileType('a FictionBook (FB2) book', BookFormat.fb2);
  }
  if (lowerStart.startsWith('<!doctype html') ||
      lowerStart.startsWith('<html') ||
      (lowerStart.startsWith('<?xml') && lowerStart.contains('<html'))) {
    return const FileType('a web page (HTML)');
  }
  if (startsWith(const [0xFF, 0xD8, 0xFF])) {
    return const FileType('a JPEG image');
  }
  if (text.startsWith('\x89PNG')) return const FileType('a PNG image');
  if (text.startsWith('GIF8')) return const FileType('a GIF image');
  if (text.startsWith('RIFF') && _has(text, 'WEBP', 8)) {
    return const FileType('a WebP image');
  }
  if (startsWith(const [0x1F, 0x8B])) return const FileType('a GZIP archive');
  if (text.startsWith('7z\xBC\xAF\x27\x1C')) {
    return const FileType('a 7-Zip archive');
  }
  if (_isText(head)) return const FileType('plain text', BookFormat.txt);
  return null;
}

FileType _sniffZip(String text) {
  // An EPUB or ODF file stores its type uncompressed as the first entry.
  if (_has(text, 'mimetypeapplication/epub+zip', 30)) {
    return const FileType('an EPUB book', BookFormat.epub);
  }
  if (_has(text, 'mimetypeapplication/vnd.oasis.opendocument.text', 30)) {
    return const FileType('an OpenDocument text (ODT)', BookFormat.odt);
  }
  if (text.contains('word/')) {
    return const FileType('a Word document (DOCX)', BookFormat.docx);
  }
  if (text.contains('META-INF/container.xml')) {
    return const FileType('an EPUB book', BookFormat.epub);
  }
  if (text.length > 30 &&
      RegExp(r'\.fb2', caseSensitive: false).hasMatch(text.substring(30))) {
    return const FileType('a zipped FictionBook (FB2) book', BookFormat.fb2);
  }
  return const FileType('a ZIP archive', BookFormat.zip);
}

/// Whether [text] holds [pattern] at [index]; false when it is too short.
bool _has(String text, String pattern, int index) =>
    text.length >= index + pattern.length && text.startsWith(pattern, index);

/// UTF-8 or Latin-1 text with no control characters besides whitespace.
bool _isText(List<int> head) {
  if (head.isEmpty) return false;
  var control = 0;
  for (final b in head) {
    if (b == 0) return false;
    if (b < 0x20 && b != 0x09 && b != 0x0A && b != 0x0D && b != 0x0C) {
      control++;
    }
  }
  return control * 100 < head.length;
}

/// Reads the start of [file] and identifies it.
Future<FileType?> sniffFile(File file) async {
  final head = await file
      .openRead(0, sniffLength)
      .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
  return sniffFileType(head);
}

/// The format to open a file named as [named] whose contents are [actual].
///
/// Returns [named] when the contents agree with the name, or are unknown,
/// and null when the file is a kind the reader cannot open.
BookFormat? formatToOpen(BookFormat named, FileType? actual) {
  if (actual == null) return named;
  final format = actual.format;
  if (format == null) return null;
  if (format == named) return named;
  // A plain ZIP or MOBI header is also what these formats look like inside.
  const zipped = {
    BookFormat.epub,
    BookFormat.cbz,
    BookFormat.fb2,
    BookFormat.docx,
    BookFormat.odt,
  };
  if (format == BookFormat.zip && zipped.contains(named)) return named;
  if (format == BookFormat.rar && named == BookFormat.cbr) return named;
  if (format == BookFormat.mobi && named == BookFormat.azw3) return named;
  return format;
}
