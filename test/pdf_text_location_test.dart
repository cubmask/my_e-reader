import 'package:ebook_reader/notes/annotation_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PDF text locations round-trip across pages', () {
    const text = 'pdftext:12:140-260;13:0-85';
    final location = PdfTextLocation.parse(text)!;
    expect(location.ranges, [
      (page: 12, start: 140, end: 260),
      (page: 13, start: 0, end: 85),
    ]);
    expect(location.toString(), text);
  });

  test('anything else is not a PDF text location', () {
    expect(PdfTextLocation.parse('page:3'), isNull);
    expect(PdfTextLocation.parse('epubcfi(/6/4!/4/2,/1:0,/1:5)'), isNull);
    expect(PdfTextLocation.parse('pdftext:3:a-b'), isNull);
  });

  test('a PDF highlight knows its page', () {
    final now = DateTime(2026);
    Annotation at(String location) => Annotation(
      id: '1',
      bookId: 'b',
      bookTitle: 'T',
      location: location,
      text: 'quote',
      note: '',
      color: HighlightColor.blue,
      createdAt: now,
      updatedAt: now,
    );
    expect(at('pdftext:7:1-9').page, 7);
    expect(at('page:4').page, 4);
    expect(at('epubcfi(/6/4)').page, isNull);
  });
}
