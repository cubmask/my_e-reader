import 'book.dart';

/// Where the library's books come from.
abstract interface class LibrarySource {
  /// Lists every supported book under the library root, including subfolders.
  Future<List<Book>> listBooks();
}
