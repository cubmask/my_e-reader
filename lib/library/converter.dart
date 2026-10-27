import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:pdfrx/pdfrx.dart';

import '../core/book_format.dart';
import '../notes/export.dart' show safeFileName;
import '../reader/reader_server.dart';
import 'book.dart';

/// A format books can be converted to. Google Docs does the writing, so
/// these are the formats it exports.
enum ConvertTarget {
  epub('EPUB', '.epub', 'application/epub+zip'),
  pdf('PDF', '.pdf', 'application/pdf'),
  docx(
    'Word (DOCX)',
    '.docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  odt('OpenDocument (ODT)', '.odt', 'application/vnd.oasis.opendocument.text'),
  txt('Plain text', '.txt', 'text/plain');

  const ConvertTarget(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;

  /// What [format] can be converted to: not itself, and nothing for comics
  /// and scans, which are pictures rather than text.
  static List<ConvertTarget> forFormat(BookFormat format) {
    if (format.engine == ReaderEngine.comic || format == BookFormat.djvu) {
      return const [];
    }
    return [
      for (final t in values)
        if (t.extension != format.extensions.first) t,
    ];
  }
}

/// Converts books between formats, the way Calibre's "Convert books" does,
/// with Google Docs as the engine.
///
/// The book's text and structure (headings, paragraphs, lists, emphasis,
/// tables) come across; pictures and the book's own styling don't. Office
/// documents go to Google Docs as they are; ebooks are read as HTML by the
/// reader's own engine, and PDFs by their text layer.
class BookConverter {
  BookConverter(this._api, {ReaderServer? server})
    : _server = server ?? ReaderServer();

  final drive.DriveApi _api;
  final ReaderServer _server;

  static const _googleDoc = 'application/vnd.google-apps.document';

  /// Converts [book], whose local copy is [file] in [format], and writes the
  /// result to [out]. Office documents need no local copy.
  Future<void> convert(
    Book book,
    File? file,
    BookFormat format,
    ConvertTarget target,
    File out, {
    void Function(String stage)? onStage,
  }) async {
    String docId;
    if (format.needsConversion) {
      onStage?.call('Opening in Google Docs');
      final copy = await _api.files.copy(
        drive.File(
          name: '${book.displayTitle} (My E-Reader conversion)',
          mimeType: _googleDoc,
        ),
        book.driveFileId,
        $fields: 'id',
      );
      docId = copy.id!;
    } else {
      onStage?.call('Reading the book');
      final html = format == BookFormat.pdf
          ? await pdfToHtml(file!, title: book.displayTitle)
          : await _ebookToHtml(file!, book.fileName);
      onStage?.call('Converting with Google Docs');
      final bytes = utf8.encode(html);
      final doc = await _api.files.create(
        drive.File(
          name: '${book.displayTitle} (My E-Reader conversion)',
          mimeType: _googleDoc,
        ),
        uploadMedia: drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: 'text/html',
        ),
        $fields: 'id',
      );
      docId = doc.id!;
    }
    try {
      onStage?.call('Writing ${target.label}');
      final media = await _api.files.export(
        docId,
        target.mimeType,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final sink = out.openWrite();
      await media.stream.pipe(sink);
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 403 && '${e.message}'.contains('too large')) {
        throw const ConvertException(
          'This book is too long for Google Docs to export (over 10 MB).',
        );
      }
      rethrow;
    } finally {
      await _api.files.delete(docId).catchError((_) {});
    }
  }

  /// The book as one HTML page, read by foliate-js in a hidden WebView.
  Future<String> _ebookToHtml(File file, String name) async {
    final url = await _server.serve(file);
    final done = Completer<Map<Object?, Object?>>();
    final view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(url)),
      onLoadStop: (web, _) async {
        try {
          final result = await web.callAsyncJavaScript(
            functionBody: 'return await window.reader.extract(args)',
            arguments: {
              'args': {'url': ReaderServer.bookPath, 'name': name},
            },
          );
          final value = result?.value;
          if (value is Map) {
            done.complete(value);
          } else {
            done.completeError(
              ConvertException(result?.error ?? 'Could not read the book.'),
            );
          }
        } catch (e) {
          if (!done.isCompleted) done.completeError(e);
        }
      },
    );
    await view.run();
    try {
      final d = await done.future.timeout(const Duration(minutes: 3));
      return htmlPage(
        title: '${d['title'] ?? ''}',
        author: '${d['author'] ?? ''}',
        language: '${d['language'] ?? ''}',
        body: '${d['html'] ?? ''}',
      );
    } finally {
      await view.dispose();
    }
  }
}

class ConvertException implements Exception {
  const ConvertException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A complete HTML page with the title and author on top, as Google Docs
/// imports it.
String htmlPage({
  required String title,
  String author = '',
  String language = '',
  required String body,
}) {
  final e = const HtmlEscape();
  return '<!doctype html><html${language.isEmpty ? '' : ' lang="${e.convert(language)}"'}>'
      '<head><meta charset="utf-8"><title>${e.convert(title)}</title></head><body>'
      '${title.isEmpty ? '' : '<h1>${e.convert(title)}</h1>'}'
      '${author.isEmpty ? '' : '<p><i>${e.convert(author)}</i></p>'}'
      '$body</body></html>';
}

/// A PDF's text as HTML, a page break between pages. Lines are joined into
/// paragraphs, which end at a blank line or a line ending a sentence that
/// is noticeably shorter than the others.
Future<String> pdfToHtml(File file, {required String title}) async {
  final doc = await PdfDocument.openFile(file.path);
  try {
    final pages = <String>[];
    for (final page in doc.pages) {
      final text = await page.loadStructuredText();
      pages.add(textToHtml(text.fullText));
    }
    return htmlPage(
      title: title,
      body: pages.join('\n<div style="page-break-before: always"></div>\n'),
    );
  } finally {
    await doc.dispose();
  }
}

/// Paragraphs of [text] as `<p>` elements; see [pdfToHtml].
String textToHtml(String text) {
  final lines = text.replaceAll('\r', '').split('\n');
  final longest = lines.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  final out = StringBuffer();
  final para = StringBuffer();
  void end() {
    final t = para.toString().trim();
    if (t.isNotEmpty) out.write('<p>${const HtmlEscape().convert(t)}</p>\n');
    para.clear();
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      end();
      continue;
    }
    if (para.isNotEmpty) {
      // A word hyphenated across lines is joined again.
      final s = para.toString();
      if (s.endsWith('-') && RegExp(r'^\p{Ll}', unicode: true).hasMatch(line)) {
        para
          ..clear()
          ..write(s.substring(0, s.length - 1));
      } else {
        para.write(' ');
      }
    }
    para.write(line);
    final short = line.length < longest * 0.7;
    if (short && RegExp(r'''[.!?:;"”’)]$''').hasMatch(line)) end();
  }
  end();
  return out.toString();
}

/// The converted copy's name: the title and the new format's extension.
String convertedName(String title, ConvertTarget target) =>
    '${safeFileName(title.isEmpty ? 'Book' : title)}${target.extension}';
