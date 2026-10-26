import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../drive/drive_auth.dart';
import '../drive/drive_library_source.dart';
import '../reader/reader_services.dart';
import 'book.dart';
import 'library_source.dart';

enum LibraryStatus { signedOut, needsFolder, loading, ready, error }

typedef SourceFactory = LibrarySource Function(
  http.Client client,
  String folderId,
);

typedef ServicesFactory = Future<ReaderServices> Function(http.Client client);

LibrarySource _driveSource(http.Client client, String folderId) =>
    DriveLibrarySource(drive.DriveApi(client), rootFolderId: folderId);

/// Owns sign-in, the chosen library folder and the list of books.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this._auth,
    this._sourceFactory = _driveSource,
    this._servicesFactory = ReaderServices.create,
  });

  static const _folderKey = 'library.folderId';

  final DriveAuth _auth;
  final SourceFactory _sourceFactory;
  final ServicesFactory _servicesFactory;

  http.Client? _client;
  ReaderServices? _services;
  String? _folderId;
  LibraryStatus _status = LibraryStatus.signedOut;
  List<Book> _books = const [];
  String? _error;

  LibraryStatus get status => _status;
  List<Book> get books => _books;
  String? get error => _error;
  String? get folderId => _folderId;

  /// Book cache, progress and reader settings; set once signed in.
  ReaderServices? get services => _services;

  Future<void> signIn() async {
    _set(LibraryStatus.loading);
    try {
      final client = _client = await _auth.signIn();
      _services = await _servicesFactory(client);
      final prefs = await SharedPreferences.getInstance();
      _folderId = prefs.getString(_folderKey);
      if (_folderId == null) {
        _set(LibraryStatus.needsFolder);
      } else {
        await refresh();
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _services?.progress.flush();
    await _services?.meta.flush();
    _client = null;
    _services = null;
    _books = const [];
    _set(LibraryStatus.signedOut);
  }

  /// Accepts a bare folder id or a drive.google.com folder link.
  Future<void> setFolder(String input) async {
    final id = parseFolderId(input);
    if (id == null) {
      _fail('That is not a Google Drive folder link or id.');
      return;
    }
    _folderId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, id);
    await refresh();
  }

  Future<void> refresh() async {
    final client = _client;
    final folderId = _folderId;
    if (client == null || folderId == null) return;
    _set(LibraryStatus.loading);
    try {
      await _services?.progress.sync();
      await _services?.meta.sync();
      _books = await _sourceFactory(client, folderId).listBooks();
      _set(LibraryStatus.ready);
    } catch (e) {
      _fail(e);
    }
  }

  void _set(LibraryStatus status) {
    _status = status;
    if (status != LibraryStatus.error) _error = null;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = error.toString();
    _set(LibraryStatus.error);
  }
}

/// Extracts the folder id from a Drive folder URL, or returns a bare id as is.
String? parseFolderId(String input) {
  final text = input.trim();
  final match = RegExp(r'/folders/([A-Za-z0-9_-]+)').firstMatch(text);
  if (match != null) return match.group(1);
  if (RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(text)) return text;
  return null;
}
