import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'book.dart';

/// Cover images, kept on the device.
///
/// A cover comes from the book itself the first time it is opened (EPUB,
/// MOBI, FB2, comics), or from Drive's preview image (PDFs) for books not
/// yet opened. A cover read from the book replaces a Drive preview.
class CoverStore extends ChangeNotifier {
  CoverStore(this._dir, this._drive);

  final Directory _dir;
  final http.Client? _drive;
  final _have = <String>{};
  final _fromBook = <String>{};
  final _requested = <String>{};
  int _running = 0;
  final _queue = <Book>[];

  Future<void> load() async {
    if (!await _dir.exists()) return;
    await for (final entity in _dir.list()) {
      final name = p.basename(entity.path);
      if (name.endsWith('.book.jpg')) {
        final id = name.substring(0, name.length - '.book.jpg'.length);
        _have.add(id);
        _fromBook.add(id);
      } else if (name.endsWith('.jpg')) {
        _have.add(name.substring(0, name.length - '.jpg'.length));
      }
    }
    notifyListeners();
  }

  File _file(String id, {required bool fromBook}) =>
      File(p.join(_dir.path, fromBook ? '$id.book.jpg' : '$id.jpg'));

  /// The cover image for [book], if there is one yet. Asks Drive for its
  /// preview in the background when there is none.
  File? coverOf(Book book) {
    final id = book.driveFileId;
    if (_fromBook.contains(id)) return _file(id, fromBook: true);
    if (_have.contains(id)) return _file(id, fromBook: false);
    _fetchThumbnail(book);
    return null;
  }

  /// Saves the cover read from the book itself.
  Future<void> saveFromBook(String id, Uint8List bytes) async {
    await _dir.create(recursive: true);
    final file = _file(id, fromBook: true);
    await file.writeAsBytes(bytes);
    await FileImage(file).evict();
    final thumb = _file(id, fromBook: false);
    if (await thumb.exists()) await thumb.delete();
    _have.add(id);
    _fromBook.add(id);
    notifyListeners();
  }

  void _fetchThumbnail(Book book) {
    if (_drive == null ||
        book.thumbnailLink == null ||
        !_requested.add(book.driveFileId)) {
      return;
    }
    _queue.add(book);
    _pump();
  }

  // A few at a time, so a big library doesn't flood the connection.
  void _pump() {
    while (_running < 3 && _queue.isNotEmpty) {
      final book = _queue.removeLast();
      _running++;
      unawaited(
        _download(book).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _download(Book book) async {
    try {
      // Drive's links end in a size such as =s220; ask for a sharper one.
      final link = book.thumbnailLink!.replaceFirst(RegExp(r'=s\d+$'), '=s800');
      final response = await _drive!.get(Uri.parse(link));
      if (response.statusCode != 200) return;
      await _dir.create(recursive: true);
      await _file(
        book.driveFileId,
        fromBook: false,
      ).writeAsBytes(response.bodyBytes);
      _have.add(book.driveFileId);
      notifyListeners();
    } catch (_) {
      // Offline: the generated cover stays until the next launch.
    }
  }
}
