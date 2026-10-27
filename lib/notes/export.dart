import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../core/platform_bridge.dart';
import 'ink_store.dart';

/// Writes [contents] (text or bytes) to a file named [name] that can be
/// shared or saved elsewhere.
Future<File> writeShared(String name, Object contents) async {
  final dir = await PlatformBridge.instance.sharedDir();
  final file = File(p.join(dir.path, safeFileName(name)));
  if (contents is String) {
    await file.writeAsString(contents);
  } else {
    await file.writeAsBytes(contents as List<int>);
  }
  return file;
}

/// [name] without characters file systems refuse.
String safeFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();

/// Draws [strokes] onto [image], whose width is the page width the strokes
/// are measured in.
void drawInk(img.Image image, Iterable<InkStroke> strokes) {
  final scale = image.width.toDouble();
  for (final s in strokes) {
    final c = s.color;
    final color = img.ColorRgba8(
      (c >> 16) & 0xff,
      (c >> 8) & 0xff,
      c & 0xff,
      s.highlighter ? 100 : (c >> 24) & 0xff,
    );
    final thickness = math.max(1.0, s.width * scale);
    final points = s.points;
    if (points.length == 1) {
      img.fillCircle(
        image,
        x: (points.first.dx * scale).round(),
        y: (points.first.dy * scale).round(),
        radius: math.max(1, (thickness / 2).round()),
        color: color,
      );
      continue;
    }
    for (var i = 1; i < points.length; i++) {
      img.drawLine(
        image,
        x1: (points[i - 1].dx * scale).round(),
        y1: (points[i - 1].dy * scale).round(),
        x2: (points[i].dx * scale).round(),
        y2: (points[i].dy * scale).round(),
        color: color,
        thickness: thickness,
        antialias: !s.highlighter,
      );
    }
  }
}

/// A copy of the PDF [file] with the handwriting in [ink] on its pages.
///
/// PDFium can copy pages between documents but not draw on them, so each
/// page with ink becomes a picture of itself with the ink on top (at 144
/// dpi); pages without ink are copied as they are, text and all.
Future<Uint8List> pdfWithInk(
  File file,
  Map<int, List<InkStroke>> ink, {
  void Function(double progress)? onProgress,
}) async {
  final source = await PdfDocument.openFile(file.path);
  final pictures = <PdfDocument>[];
  try {
    final pages = <PdfPage>[];
    final total = source.pages.length;
    for (final page in source.pages) {
      final strokes = ink[page.pageNumber];
      if (strokes == null || strokes.isEmpty) {
        pages.add(page);
      } else {
        final width = (page.width * 2).round();
        final height = (page.height * 2).round();
        final rendered = await page.render(
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          backgroundColor: 0xffffffff,
        );
        if (rendered == null) {
          pages.add(page);
          continue;
        }
        final image = img.Image.fromBytes(
          width: rendered.width,
          height: rendered.height,
          bytes: rendered.pixels.buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        );
        rendered.dispose();
        drawInk(image, strokes);
        final jpeg = img.encodeJpg(image, quality: 85);
        final picture = await PdfDocument.createFromJpegData(
          jpeg,
          width: page.width,
          height: page.height,
          sourceName: '${file.path}#ink${page.pageNumber}',
        );
        pictures.add(picture);
        pages.add(picture.pages.first);
      }
      onProgress?.call(page.pageNumber / total);
    }
    final out = await PdfDocument.createNew(sourceName: '${file.path}#ink');
    try {
      out.pages = pages;
      return await out.encodePdf();
    } finally {
      await out.dispose();
    }
  } finally {
    for (final d in pictures) {
      await d.dispose();
    }
    await source.dispose();
  }
}
