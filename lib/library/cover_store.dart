import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'book.dart';

/// Where a cover came from, best first.
enum CoverKind {
  /// Chosen by the user from an online search.
  chosen('chosen'),

  /// Read from the book itself when it was opened.
  book('book'),

  /// Found online by the automatic metadata lookup.
  online('online'),

  /// Drive's preview image (PDFs).
  drive('drive');

  const CoverKind(this.suffix);
  final String suffix;
}

/// Cover images, kept on the device.
///
/// Covers arrive from several places (see [CoverKind]) and the best one
/// available is shown: a cover the user picked, then the book's own, then
/// one found online, then Drive's preview. Books with none get a typeset
/// cover in the UI.
class CoverStore extends ChangeNotifier {
  CoverStore(this._dir, this._drive, {http.Client? web})
    : _web = web ?? http.Client();

  final Directory _dir;

  /// Signed in to Google, for Drive previews only.
  final http.Client? _drive;

  /// Plain client for public covers, so the Google token never goes to
  /// other sites.
  final http.Client _web;

  /// The kinds of cover on disk for each book.
  final _have = <String, Set<CoverKind>>{};
  final _requested = <String>{};
  int _running = 0;
  final _queue = <Book>[];

  Future<void> load() async {
    if (!await _dir.exists()) return;
    final kinds = {for (final k in CoverKind.values) '.${k.suffix}.jpg': k};
    await for (final entity in _dir.list()) {
      final name = p.basename(entity.path);
      for (final MapEntry(key: ending, value: kind) in kinds.entries) {
        if (name.endsWith(ending)) {
          final id = name.substring(0, name.length - ending.length);
          (_have[id] ??= {}).add(kind);
        }
      }
    }
    notifyListeners();
  }

  File _file(String id, CoverKind kind) =>
      File(p.join(_dir.path, '$id.${kind.suffix}.jpg'));

  CoverKind? bestKind(String id) {
    final kinds = _have[id];
    if (kinds == null) return null;
    return CoverKind.values.where(kinds.contains).firstOrNull;
  }

  /// The best cover image for [book], if there is one yet. Asks Drive for its
  /// preview in the background when there is none.
  File? coverOf(Book book) {
    final kind = bestKind(book.driveFileId);
    if (kind == null) _fetchThumbnail(book);
    return kind == null ? null : _file(book.driveFileId, kind);
  }

  Future<void> save(String id, CoverKind kind, Uint8List bytes) async {
    await _dir.create(recursive: true);
    final file = _file(id, kind);
    await file.writeAsBytes(bytes);
    await FileImage(file).evict();
    (_have[id] ??= {}).add(kind);
    notifyListeners();
  }

  /// Downloads [url] as the book's cover of [kind]. Returns false when it
  /// can't be fetched or isn't an image.
  Future<bool> saveFromUrl(String id, CoverKind kind, Uri url) async {
    final client = kind == CoverKind.drive ? _drive : _web;
    if (client == null) return false;
    try {
      final response = await client.get(url);
      final type = response.headers['content-type'] ?? '';
      // Open Library answers a missing cover with a tiny placeholder.
      if (response.statusCode != 200 ||
          !type.startsWith('image/') ||
          response.bodyBytes.length < 1000) {
        return false;
      }
      await save(id, kind, response.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
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
      // Drive's links end in a size such as =s220; ask for a sharper one.
      final link = book.thumbnailLink!.replaceFirst(RegExp(r'=s\d+$'), '=s800');
      unawaited(
        saveFromUrl(
          book.driveFileId,
          CoverKind.drive,
          Uri.parse(link),
        ).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }
}
