import 'dart:ui';

import 'package:ebook_reader/reader/pdf_spread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pairs pages side by side and centres an odd last page', () {
    final layout = spreadLayout(const [
      Size(100, 200),
      Size(100, 200),
      Size(100, 150),
    ], 10);
    expect(layout.rects, [
      const Rect.fromLTWH(10, 10, 100, 200),
      const Rect.fromLTWH(120, 10, 100, 200),
      const Rect.fromLTWH(65, 220, 100, 150),
    ]);
    expect(layout.size, const Size(230, 380));
  });
}
