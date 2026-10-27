import 'dart:io';

import 'package:ebook_reader/reader/pdf_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('tells a PDF from a renamed file by its header', () async {
    final dir = await Directory.systemTemp.createTemp('pdf');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/a.pdf')..writeAsStringSync('%PDF-1.7\n...');
    final late = File('${dir.path}/b.pdf')
      ..writeAsStringSync('${' ' * 100}%PDF-1.4');
    final html = File('${dir.path}/c.pdf')..writeAsStringSync('<html>');
    final empty = File('${dir.path}/d.pdf')..writeAsBytesSync([]);

    expect(await looksLikePdf(pdf), isTrue);
    expect(await looksLikePdf(late), isTrue);
    expect(await looksLikePdf(html), isFalse);
    expect(await looksLikePdf(empty), isFalse);
    expect(await looksLikePdf(File('${dir.path}/missing.pdf')), isFalse);
  });

  test('explains load errors without PDFium codes', () {
    const format = PdfException('Failed (FPDF_ERR_FORMAT: 3).', 3);
    expect(pdfErrorMessage(format), contains('damaged'));
    expect(pdfErrorMessage(format, isPdf: false), contains("isn't really"));
    expect(
      pdfErrorMessage(const PdfPasswordException('no password')),
      contains('password'),
    );
    for (final error in [format, Exception('x'), const PdfException('?', 5)]) {
      expect(pdfErrorMessage(error), isNot(contains('FPDF')));
    }
  });
}
