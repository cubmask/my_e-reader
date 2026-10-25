import 'package:path/path.dart' as p;

/// The engine that renders a format. Every format maps to exactly one.
enum ReaderEngine {
  /// foliate-js inside a WebView: reflowable text with CFI anchors.
  reflowable,

  /// Native page renderer (PDFium, DjVuLibre).
  fixedLayout,

  /// Page images extracted from an archive.
  comic,
}

/// Every file type the library accepts.
enum BookFormat {
  epub('EPUB', ReaderEngine.reflowable, ['.epub']),
  mobi('MOBI', ReaderEngine.reflowable, ['.mobi', '.prc']),
  azw3('AZW3', ReaderEngine.reflowable, ['.azw3', '.azw', '.kf8']),
  fb2('FB2', ReaderEngine.reflowable, ['.fb2', '.fb2.zip']),
  txt('TXT', ReaderEngine.reflowable, ['.txt']),
  docx('DOCX', ReaderEngine.reflowable, ['.docx']),
  doc('DOC', ReaderEngine.reflowable, ['.doc']),
  rtf('RTF', ReaderEngine.reflowable, ['.rtf']),
  odt('ODT', ReaderEngine.reflowable, ['.odt']),
  pdf('PDF', ReaderEngine.fixedLayout, ['.pdf']),
  djvu('DjVu', ReaderEngine.fixedLayout, ['.djvu', '.djv']),
  cbz('CBZ', ReaderEngine.comic, ['.cbz']),
  cbr('CBR', ReaderEngine.comic, ['.cbr']),
  zip('ZIP', ReaderEngine.comic, ['.zip']),
  rar('RAR', ReaderEngine.comic, ['.rar']);

  const BookFormat(this.label, this.engine, this.extensions);

  final String label;
  final ReaderEngine engine;
  final List<String> extensions;

  /// Office formats are converted to HTML before the reflowable engine opens them.
  bool get needsConversion =>
      this == docx || this == doc || this == rtf || this == odt;

  /// Archives that may hold a single book of another format rather than page images.
  bool get isGenericArchive => this == zip || this == rar;

  /// Returns the format for [fileName], or null when it is not a supported book.
  ///
  /// Compound extensions such as `.fb2.zip` win over their last segment.
  static BookFormat? fromFileName(String fileName) {
    final name = fileName.toLowerCase();
    for (final format in values) {
      for (final ext in format.extensions) {
        if (ext.split('.').length > 2 && name.endsWith(ext)) return format;
      }
    }
    final ext = p.extension(name);
    if (ext.isEmpty) return null;
    for (final format in values) {
      if (format.extensions.contains(ext)) return format;
    }
    return null;
  }
}
