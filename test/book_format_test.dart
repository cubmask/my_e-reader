import 'package:ebook_reader/core/book_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects every requested format by extension', () {
    const cases = {
      'a.epub': BookFormat.epub,
      'a.mobi': BookFormat.mobi,
      'a.azw3': BookFormat.azw3,
      'a.pdf': BookFormat.pdf,
      'a.djvu': BookFormat.djvu,
      'a.cbr': BookFormat.cbr,
      'a.cbz': BookFormat.cbz,
      'a.doc': BookFormat.doc,
      'a.docx': BookFormat.docx,
      'a.rtf': BookFormat.rtf,
      'a.odt': BookFormat.odt,
      'a.txt': BookFormat.txt,
      'a.fb2': BookFormat.fb2,
      'a.zip': BookFormat.zip,
      'a.rar': BookFormat.rar,
    };
    cases.forEach((name, format) {
      expect(BookFormat.fromFileName(name), format, reason: name);
    });
  });

  test('is case-insensitive and prefers compound extensions', () {
    expect(BookFormat.fromFileName('War And Peace.EPUB'), BookFormat.epub);
    expect(BookFormat.fromFileName('tale.fb2.zip'), BookFormat.fb2);
  });

  test('ignores unsupported and extensionless files', () {
    expect(BookFormat.fromFileName('cover.jpg'), isNull);
    expect(BookFormat.fromFileName('README'), isNull);
  });

  test('maps formats to engines', () {
    expect(BookFormat.mobi.engine, ReaderEngine.reflowable);
    expect(BookFormat.djvu.engine, ReaderEngine.fixedLayout);
    expect(BookFormat.cbr.engine, ReaderEngine.comic);
    expect(BookFormat.odt.needsConversion, isTrue);
    expect(BookFormat.epub.needsConversion, isFalse);
  });
}
