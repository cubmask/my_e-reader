import 'package:pdfrx/pdfrx.dart';

/// One line of a PDF page's text and where it sits, in PDF points measured
/// up from the foot of the page.
typedef PdfTextLine = ({String text, double top, double bottom});

/// Splits a page's text into lines with their positions, from PDFium's text
/// and the box of each character. Empty when the boxes don't match the text.
List<PdfTextLine> pdfLines(String fullText, List<PdfRect> charRects) {
  if (charRects.length != fullText.length) return const [];
  final lines = <PdfTextLine>[];
  var start = 0;
  void close(int end) {
    final text = fullText.substring(start, end).replaceAll('\r', '');
    double? top, bottom;
    for (var i = start; i < end; i++) {
      if (fullText[i].trim().isEmpty) continue;
      final r = charRects[i];
      if (r.top <= r.bottom) continue;
      top = top == null || r.top > top ? r.top : top;
      bottom = bottom == null || r.bottom < bottom ? r.bottom : bottom;
    }
    if (text.trim().isNotEmpty && top != null) {
      lines.add((text: text, top: top, bottom: bottom!));
    }
  }

  for (var i = 0; i < fullText.length; i++) {
    if (fullText[i] == '\n') {
      close(i);
      start = i + 1;
    }
  }
  close(fullText.length);
  return lines;
}

/// The words of a page worth reading aloud: without the running head and
/// page number at the top and foot, or footnotes set small at the bottom.
String readablePdfText(List<PdfTextLine> lines, double pageHeight) {
  if (lines.isEmpty) return '';
  final heights = [for (final l in lines) l.top - l.bottom]..sort();
  final body = heights[heights.length ~/ 2];
  bool short(String text) =>
      text.trim().split(RegExp(r'\s+')).length <= 10 ||
      RegExp(r'^[\divxlcIVXLC.\s–—-]+$').hasMatch(text.trim());
  final kept = [
    for (final l in lines)
      // Running heads and page numbers sit in the outer bands.
      if (!((l.bottom > pageHeight * 0.92 || l.top < pageHeight * 0.08) &&
              short(l.text)) &&
          // Footnotes: small type in the lower part of the page.
          !(l.top < pageHeight * 0.35 && l.top - l.bottom < body * 0.8))
        l.text,
  ];
  return kept.join('\n');
}

/// Drops what sounds wrong spoken: reference marks such as [12] or ¹, web
/// addresses, and hyphens that split a word across lines.
String speakable(String text) => text
    .replaceAllMapped(
      RegExp(r'(\p{L})[-­]\r?\n(\p{Ll})', unicode: true),
      (m) => '${m[1]}${m[2]}',
    )
    .replaceAll(RegExp(r'\[\d+(?:\s*[,–-]\s*\d+)*\]'), '')
    .replaceAll(RegExp(r'[¹²³⁰⁴-⁹]+'), '')
    .replaceAll(RegExp(r'\b(?:https?://|www\.)[^\s)\]]+'), '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'[ \t]+([.,;:!?])'), (m) => m[1]!);
