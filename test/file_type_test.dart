import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/core/file_type.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _zip(String firstEntry, [String data = '']) => [
  ...'PK\x03\x04'.codeUnits,
  ...List.filled(26, 0),
  ...latin1.encode(firstEntry),
  ...latin1.encode(data),
];

BookFormat? _sniffed(List<int> head) => sniffFileType(head)?.format;

void main() {
  test('identifies books by their contents', () {
    expect(_sniffed(latin1.encode('%PDF-1.7\n')), BookFormat.pdf);
    expect(_sniffed(latin1.encode('${' ' * 200}%PDF-1.4')), BookFormat.pdf);
    expect(
      _sniffed(latin1.encode('AT&TFORM\x00\x00\x10\x00DJVMDIRM')),
      BookFormat.djvu,
    );
    expect(_sniffed(_zip('mimetypeapplication/epub+zip')), BookFormat.epub);
    expect(
      _sniffed(_zip('mimetypeapplication/vnd.oasis.opendocument.text')),
      BookFormat.odt,
    );
    expect(
      _sniffed(_zip('[Content_Types].xml', '...PK..word/document.xml')),
      BookFormat.docx,
    );
    expect(_sniffed(_zip('book.fb2')), BookFormat.fb2);
    expect(_sniffed(_zip('page001.jpg')), BookFormat.zip);
    expect(_sniffed(latin1.encode('Rar!\x1a\x07\x00')), BookFormat.rar);
    expect(
      _sniffed([...List.filled(60, 0), ...latin1.encode('BOOKMOBI')]),
      BookFormat.mobi,
    );
    expect(
      _sniffed([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]),
      BookFormat.doc,
    );
    expect(_sniffed(latin1.encode(r'{\rtf1\ansi')), BookFormat.rtf);
    expect(
      _sniffed(utf8.encode('<?xml version="1.0"?>\n<FictionBook xmlns="">')),
      BookFormat.fb2,
    );
    expect(
      _sniffed(utf8.encode('Chapter 1\n\nIt was a dark night…')),
      BookFormat.txt,
    );
  });

  test('names files the reader cannot open', () {
    for (final (head, label) in [
      (utf8.encode('<!DOCTYPE html><html>'), 'HTML'),
      (utf8.encode('  <html lang="en">'), 'HTML'),
      ([0xFF, 0xD8, 0xFF, 0xE0], 'JPEG'),
      (latin1.encode('\x89PNG\r\n'), 'PNG'),
      ([0x1F, 0x8B, 8, 0], 'GZIP'),
    ]) {
      final type = sniffFileType(head)!;
      expect(type.format, isNull);
      expect(type.label, contains(label));
    }
    expect(sniffFileType([0, 1, 2, 3, 0, 9]), isNull);
    expect(sniffFileType([]), isNull);
  });

  test('keeps the named format when the contents agree with it', () {
    const zip = FileType('a ZIP archive', BookFormat.zip);
    const mobi = FileType('a Kindle book', BookFormat.mobi);
    const epub = FileType('an EPUB book', BookFormat.epub);
    expect(formatToOpen(BookFormat.pdf, null), BookFormat.pdf);
    expect(formatToOpen(BookFormat.epub, zip), BookFormat.epub);
    expect(formatToOpen(BookFormat.cbz, zip), BookFormat.cbz);
    expect(formatToOpen(BookFormat.azw3, mobi), BookFormat.azw3);
    expect(formatToOpen(BookFormat.pdf, epub), BookFormat.epub);
    expect(formatToOpen(BookFormat.pdf, zip), BookFormat.zip);
    expect(formatToOpen(BookFormat.pdf, const FileType('a web page')), isNull);
  });

  test('reads only the start of a file', () async {
    final dir = await Directory.systemTemp.createTemp('sniff');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/book.pdf')
      ..writeAsBytesSync(_zip('mimetypeapplication/epub+zip'));
    expect((await sniffFile(file))?.format, BookFormat.epub);
  });
}
