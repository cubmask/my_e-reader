import 'package:ebook_reader/notes/export.dart';
import 'package:ebook_reader/notes/ink_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

InkStroke _stroke(List<Offset> points, {bool highlighter = false}) => InkStroke(
  id: 's',
  bookId: 'b',
  page: 1,
  color: 0xFFD9625D,
  width: 0.01,
  points: points,
  highlighter: highlighter,
  updatedAt: DateTime(2026),
);

void main() {
  test('ink is drawn where it was written, scaled to the page', () {
    final page = img.Image(width: 200, height: 260)
      ..clear(img.ColorRgb8(255, 255, 255));
    drawInk(page, [
      _stroke([const Offset(0.1, 0.5), const Offset(0.9, 0.5)]),
    ]);
    // Halfway along the line, at y = 0.5 page widths = 100 px.
    final on = page.getPixel(100, 100);
    expect(on.r, closeTo(0xD9, 20));
    expect(on.g, closeTo(0x62, 20));
    final off = page.getPixel(100, 200);
    expect(off.r, 255);
    expect(off.g, 255);
  });

  test('a highlighter lets the page show through', () {
    final page = img.Image(width: 100, height: 100)
      ..clear(img.ColorRgb8(255, 255, 255));
    drawInk(page, [
      _stroke([
        const Offset(0.1, 0.5),
        const Offset(0.9, 0.5),
      ], highlighter: true),
    ]);
    final pixel = page.getPixel(50, 50);
    expect(pixel.g, greaterThan(0x62 + 40));
    expect(pixel.g, lessThan(255));
  });

  test('file names lose characters file systems refuse', () {
    expect(
      safeFileName('Dune: Book 1/2 "notes".md'),
      'Dune_ Book 1_2 _notes_.md',
    );
  });
}
