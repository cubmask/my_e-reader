import 'package:ebook_reader/reader/pdf_speech.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  test('lines carry the box around their characters', () {
    const text = 'Ab\ncd';
    final rects = [
      const PdfRect(0, 700, 5, 690),
      const PdfRect(5, 702, 10, 690),
      const PdfRect(0, 0, 0, 0),
      const PdfRect(0, 600, 5, 590),
      const PdfRect(5, 600, 10, 588),
    ];
    final lines = pdfLines(text, rects);
    expect(lines.map((l) => l.text), ['Ab', 'cd']);
    expect(lines.first.top, 702);
    expect(lines.last.bottom, 588);
    expect(pdfLines(text, rects.sublist(1)), isEmpty);
  });

  test('running heads, page numbers and footnotes are skipped', () {
    PdfTextLine line(String text, double bottom, [double size = 10]) =>
        (text: text, top: bottom + size, bottom: bottom);
    final text = readablePdfText([
      line('THE SECRET GARDEN', 760),
      line('Mary Lennox was sent to live with her uncle.', 600),
      line('Nobody liked her very much at first.', 586),
      line('1 Misselthwaite Manor is in Yorkshire.', 80, 6),
      line('42', 30),
    ], 792);
    expect(
      text,
      'Mary Lennox was sent to live with her uncle.\n'
      'Nobody liked her very much at first.',
    );
  });

  test('reference marks, links and broken words are dropped', () {
    expect(
      speakable('A well-known re-\nsult [12] holds¹ (see www.x.org/a) here.'),
      'A well-known result holds (see ) here.',
    );
    expect(speakable('Shown in [3, 4] and [5–7] .'), 'Shown in and.');
  });

  test('sentences are found on the page despite what was dropped', () {
    const page =
        'THE SECRET GARDEN\n'
        'Mary Lennox was sent to live with her uncle.[12] Nobody liked\n'
        'her very much at first. She was a dis-\n'
        'agreeable child¹ who saw www.example.com rarely.\n'
        '42';
    final sentences = [
      'Mary Lennox was sent to live with her uncle.',
      'Nobody liked her very much at first.',
      'She was a disagreeable child who saw rarely.',
    ];
    final found = locateSentences(page, sentences);
    String at(int i) => page.substring(found[i]!.start, found[i]!.end);
    expect(at(0), 'Mary Lennox was sent to live with her uncle.');
    expect(at(1), 'Nobody liked\nher very much at first.');
    expect(
      at(2),
      'She was a dis-\nagreeable child¹ who saw www.example.com rarely.',
    );
  });

  test('a sentence not on the page is not found, and the rest still are', () {
    const page = 'One fish. Two fish. Red fish.';
    final found = locateSentences(page, [
      'One fish.',
      'Blue whale.',
      'Red fish.',
    ]);
    expect(found[0], (start: 0, end: 9));
    expect(found[1], isNull);
    expect(page.substring(found[2]!.start, found[2]!.end), 'Red fish.');
  });

  test('repeated sentences are found in reading order', () {
    const page = 'Yes. No. Yes.';
    final found = locateSentences(page, ['Yes.', 'No.', 'Yes.']);
    expect([for (final f in found) f!.start], [0, 5, 9]);
  });
}
