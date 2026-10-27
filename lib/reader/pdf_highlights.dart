import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../notes/annotation_store.dart';

/// A highlight to draw on a PDF: where it is and its colour.
typedef PdfHighlight = ({PdfTextLocation location, Color color});

/// Draws text highlights on PDF pages and finds the one under a tap.
///
/// Highlights are stored as character ranges, so each page's text layer is
/// loaded once (when the page is first drawn) to find the rectangles.
class PdfHighlighter {
  PdfHighlighter(this._controller, this._highlights);

  final PdfViewerController _controller;
  final List<PdfHighlight> Function() _highlights;
  final _texts = <int, PdfPageText>{};
  final _loading = <int>{};

  Iterable<({PdfHighlight highlight, int start, int end})> _onPage(
    int page,
  ) sync* {
    for (final h in _highlights()) {
      for (final r in h.location.ranges) {
        if (r.page == page) yield (highlight: h, start: r.start, end: r.end);
      }
    }
  }

  /// Pass to [PdfViewerParams.pagePaintCallbacks].
  void paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final ranges = _onPage(page.pageNumber).toList();
    if (ranges.isEmpty) return;
    final text = _texts[page.pageNumber];
    if (text == null) {
      _load(page);
      return;
    }
    for (final (:highlight, :start, :end) in ranges) {
      final paint = Paint()
        ..color = highlight.color.withValues(alpha: 0.38)
        ..blendMode = BlendMode.multiply;
      for (final rect in _rects(text, start, end, page, pageRect)) {
        canvas.drawRect(rect, paint);
      }
    }
  }

  Iterable<Rect> _rects(
    PdfPageText text,
    int start,
    int end,
    PdfPage page,
    Rect pageRect,
  ) sync* {
    final s = start.clamp(0, text.fullText.length);
    final e = end.clamp(s, text.fullText.length);
    if (e <= s) return;
    final range = PdfPageTextRange(pageText: text, start: s, end: e);
    for (final f in range.enumerateFragmentBoundingRects()) {
      yield f.bounds.toRectInDocument(page: page, pageRect: pageRect);
    }
  }

  Future<void> _load(PdfPage page) async {
    if (!_loading.add(page.pageNumber)) return;
    try {
      _texts[page.pageNumber] = await page.loadStructuredText();
      if (_controller.isReady) _controller.invalidate();
    } catch (_) {
      // No text layer: nothing to draw.
    }
  }

  /// The highlight under [position], in document coordinates.
  PdfTextLocation? hitTest(Offset position) {
    if (!_controller.isReady) return null;
    final layouts = _controller.layout.pageLayouts;
    final pages = _controller.document.pages;
    for (var i = 0; i < layouts.length && i < pages.length; i++) {
      final pageRect = layouts[i];
      if (!pageRect.contains(position)) continue;
      final text = _texts[i + 1];
      if (text == null) return null;
      for (final (:highlight, :start, :end) in _onPage(i + 1)) {
        for (final rect in _rects(text, start, end, pages[i], pageRect)) {
          if (rect.inflate(4).contains(position)) return highlight.location;
        }
      }
      return null;
    }
    return null;
  }
}

/// The selected PDF text as a [PdfTextLocation], or null when nothing is
/// selected.
Future<({String location, String text})?> pdfSelection(
  PdfTextSelection selection,
) async {
  if (!selection.hasSelectedText) return null;
  final ranges = await selection.getSelectedTextRanges();
  final parts = [
    for (final r in ranges)
      if (r.end > r.start) (page: r.pageNumber, start: r.start, end: r.end),
  ];
  if (parts.isEmpty) return null;
  final text = ranges.map((r) => r.text).join(' ').trim();
  if (text.isEmpty) return null;
  return (location: PdfTextLocation(parts).toString(), text: text);
}
