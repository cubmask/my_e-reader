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
}
