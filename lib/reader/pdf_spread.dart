import 'dart:math';
import 'dart:ui';

/// Lays pages out two per row (1-2, 3-4, ...) for landscape tablets.
///
/// Each pair is centred horizontally and top-aligned. Returns the page
/// rectangles and the overall document size.
({List<Rect> rects, Size size}) spreadLayout(List<Size> pages, double margin) {
  final rowWidths = <double>[];
  for (var i = 0; i < pages.length; i += 2) {
    final right = i + 1 < pages.length ? pages[i + 1].width + margin : 0.0;
    rowWidths.add(pages[i].width + right);
  }
  final width = rowWidths.fold(0.0, max) + margin * 2;
  final rects = <Rect>[];
  var y = margin;
  for (var i = 0, row = 0; i < pages.length; i += 2, row++) {
    var x = (width - rowWidths[row]) / 2;
    var rowHeight = 0.0;
    for (final page in pages.skip(i).take(2)) {
      rects.add(Rect.fromLTWH(x, y, page.width, page.height));
      x += page.width + margin;
      rowHeight = max(rowHeight, page.height);
    }
    y += rowHeight + margin;
  }
  return (rects: rects, size: Size(width, y));
}
