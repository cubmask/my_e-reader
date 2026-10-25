import 'book_format.dart';

/// A position inside a document that survives re-layout.
///
/// Reflowable books use an EPUB CFI, fixed-layout books a page plus text
/// offsets, comics a page index. [value] is opaque outside its engine.
class DocumentLocator {
  const DocumentLocator(this.engine, this.value);

  final ReaderEngine engine;
  final String value;

  Map<String, Object> toJson() => {'engine': engine.name, 'value': value};

  factory DocumentLocator.fromJson(Map<String, Object?> json) =>
      DocumentLocator(
        ReaderEngine.values.byName(json['engine']! as String),
        json['value']! as String,
      );
}

class TocEntry {
  const TocEntry(this.title, this.locator, {this.children = const []});

  final String title;
  final DocumentLocator locator;
  final List<TocEntry> children;
}

class SearchHit {
  const SearchHit(this.locator, this.excerpt);

  final DocumentLocator locator;
  final String excerpt;
}

/// The one interface every engine implements, so the UI, notes and TTS never
/// depend on which format is open.
abstract interface class ReaderDocument {
  BookFormat get format;
  String get title;
  List<TocEntry> get tableOfContents;

  /// Reading progress from 0 to 1 for [locator].
  double progressOf(DocumentLocator locator);

  Future<List<SearchHit>> search(String query);

  /// Plain text from [from] onward, used by text-to-speech.
  Stream<String> sentencesFrom(DocumentLocator from);

  Future<void> close();
}
