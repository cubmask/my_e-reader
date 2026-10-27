import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../core/book_format.dart';
import '../core/file_type.dart';
import 'book.dart';

/// Why a book will not open.
enum ProblemKind {
  gone('No longer in Google Drive'),
  noAccess('Google Drive refused the download'),
  empty('Empty files'),
  notABook('Not really books'),
  damaged('Damaged or cut short'),
  reader('Failed in the reader');

  const ProblemKind(this.label);

  /// A heading for books with this problem.
  final String label;
}

class BookProblem {
  const BookProblem(this.kind, this.message, this.stamp);

  final ProblemKind kind;

  /// What is wrong, for the reader.
  final String message;

  /// The book's modified time when the problem was found, so a new version
  /// in Drive is checked again.
  final int stamp;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'message': message,
    'stamp': stamp,
  };

  static BookProblem? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ProblemKind.values.asNameMap()[json['kind']];
    if (kind == null) return null;
    return BookProblem(
      kind,
      '${json['message'] ?? ''}',
      (json['stamp'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Finds the books in the library that will not open, and why.
///
/// A check reads only the first and last 64 KB of each book from Drive,
/// which is enough to tell what a file really holds and whether it was cut
/// short. Failures the check cannot see, such as a book the reading engine
/// chokes on, are recorded when the book fails in the reader, and cleared
/// once it opens.
///
/// Results are kept on this device only, in [file].
class BookHealth extends ChangeNotifier {
  BookHealth(this._api, this.file);

  final drive.DriveApi? _api;
  final File? file;

  final _problems = <String, BookProblem>{};

  /// Each checked book's modified time when it was checked, by Drive id.
  final _checked = <String, int>{};

  DateTime? lastScan;

  /// Why the last scan stopped early, or null.
  String? scanError;

  /// Books the last scan could not check, because Drive failed in a way
  /// that says nothing about the book. They are checked again next time.
  int skipped = 0;

  int? _total;
  int _done = 0;
  bool _stop = false;

  bool get scanning => _total != null;

  /// Books checked so far in this scan, out of [total].
  int get done => _done;
  int get total => _total ?? 0;

  BookProblem? problemOf(Book book) => _problems[book.driveFileId];

  /// The books in [books] that will not open.
  List<(Book, BookProblem)> problemsIn(Iterable<Book> books) => [
    for (final b in books)
      if (_problems[b.driveFileId] case final problem?) (b, problem),
  ];

  /// The books in [books] not checked since they last changed.
  List<Book> unchecked(Iterable<Book> books) => [
    for (final b in books)
      if (_checked[b.driveFileId] != _stamp(b)) b,
  ];

  static int _stamp(Book book) =>
      book.modifiedTime?.millisecondsSinceEpoch ?? 0;

  Future<void> load() async {
    final file = this.file;
    if (file == null || !await file.exists()) return;
    try {
      final json = jsonDecode(await file.readAsString()) as Map;
      final scanned = json['lastScan'];
      lastScan = scanned is int
          ? DateTime.fromMillisecondsSinceEpoch(scanned)
          : null;
      for (final MapEntry(:key, :value) in (json['checked'] as Map).entries) {
        if (value is int) _checked['$key'] = value;
      }
      for (final MapEntry(:key, :value) in (json['problems'] as Map).entries) {
        if (BookProblem.fromJson(value) case final problem?) {
          _problems['$key'] = problem;
        }
      }
    } catch (_) {
      // A damaged results file only costs a new scan.
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await file?.writeAsString(
      jsonEncode({
        'lastScan': lastScan?.millisecondsSinceEpoch,
        'checked': _checked,
        'problems': {
          for (final MapEntry(:key, :value) in _problems.entries)
            key: value.toJson(),
        },
      }),
    );
  }

  /// Checks every book in [books] not checked since it last changed, or
  /// every book when [all] is true.
  ///
  /// Stops early, setting [scanError], when Drive cannot be reached, rather
  /// than blaming every book for the connection.
  Future<void> scan(List<Book> books, {bool all = false}) async {
    if (scanning) return;
    final ids = {for (final b in books) b.driveFileId};
    _problems.removeWhere((id, _) => !ids.contains(id));
    _checked.removeWhere((id, _) => !ids.contains(id));
    final todo = all ? books : unchecked(books);
    _total = todo.length;
    _done = 0;
    _stop = false;
    scanError = null;
    skipped = 0;
    notifyListeners();
    var next = 0;
    Future<void> worker() async {
      while (!_stop && next < todo.length) {
        final book = todo[next++];
        try {
          _record(book, await check(book));
        } catch (e) {
          if (_isConnectionError(e) || _isRateLimit(e)) {
            if (!_stop) scanError = _stopMessage(e);
            _stop = true;
          } else {
            skipped++;
          }
        }
        _done++;
        notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    _total = null;
    lastScan = DateTime.now();
    notifyListeners();
    await _save();
  }

  /// Stops the scan after the books being checked now.
  void stop() => _stop = true;

  void _record(Book book, BookProblem? problem) {
    final id = book.driveFileId;
    _checked[id] = _stamp(book);
    final old = _problems[id];
    if (problem != null) {
      _problems[id] = problem;
    } else if (old != null &&
        !(old.kind == ProblemKind.reader && old.stamp == _stamp(book))) {
      // A failure in the reader stays: the check cannot see what caused it.
      _problems.remove(id);
    }
  }

  /// Records that [book] would not open in the reader, because of [error].
  ///
  /// Connection errors say nothing about the book and are left out.
  Future<void> readerFailed(
    Book book,
    Object error, {
    ProblemKind kind = ProblemKind.reader,
  }) async {
    if (_isConnectionError(error)) return;
    _problems[book.driveFileId] =
        (error is drive.DetailedApiRequestError
            ? _driveProblem(error, _stamp(book))
            : null) ??
        BookProblem(kind, '$error', _stamp(book));
    notifyListeners();
    await _save();
  }

  /// Records that [book] opened, clearing any problem found earlier.
  Future<void> opened(Book book) async {
    if (_problems.remove(book.driveFileId) == null) return;
    notifyListeners();
    await _save();
  }

  /// Finds out whether [book] will open, reading its first and last bytes
  /// from Drive. Returns null when nothing is wrong.
  ///
  /// Throws when Drive cannot be reached.
  Future<BookProblem?> check(Book book) async {
    final stamp = _stamp(book);
    BookProblem problem(ProblemKind kind, String message) =>
        BookProblem(kind, message, stamp);
    final size = book.sizeBytes;
    if (size == 0) {
      return problem(ProblemKind.empty, 'The file in Google Drive is empty.');
    }
    try {
      final head = await _head(book);
      if (head.isEmpty) {
        return problem(ProblemKind.empty, 'The file in Google Drive is empty.');
      }
      final actual = sniffFileType(head);
      final format = formatToOpen(book.format, actual);
      if (format == null) {
        return problem(
          ProblemKind.notABook,
          'This file is really $actual, not ${_article(book.format)}, '
          'so it cannot be opened as a book.',
        );
      }
      if (size == null) return null;
      final tail = size <= head.length
          ? head
          : await _range(book, max(0, size - sniffLength), size);
      final damage = damageIn(format, head, tail, size);
      return damage == null ? null : problem(ProblemKind.damaged, damage);
    } on drive.DetailedApiRequestError catch (e) {
      return _driveProblem(e, stamp) ?? (throw e);
    }
  }

  Future<List<int>> _head(Book book) async {
    final media = await _api!.files.get(
      book.driveFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    // Leaving the loop cancels the rest of the download.
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
      if (bytes.length >= sniffLength) break;
    }
    return bytes.length > sniffLength ? bytes.sublist(0, sniffLength) : bytes;
  }

  /// Bytes [start] to [end], not including [end].
  Future<List<int>> _range(Book book, int start, int end) async {
    final media = await _api!.files.get(
      book.driveFileId,
      downloadOptions: drive.PartialDownloadOptions(
        drive.ByteRange(start, end - 1),
      ),
    ) as drive.Media;
    return media.stream.fold<List<int>>([], (all, c) => all..addAll(c));
  }

  /// The problem a Drive error means for the book, or null when it is about
  /// the connection or the app rather than the book.
  static BookProblem? _driveProblem(
    drive.DetailedApiRequestError e,
    int stamp,
  ) {
    if (e.status == 404) {
      return BookProblem(
        ProblemKind.gone,
        'Google Drive no longer has this file. It may have been deleted, '
        'or its sharing changed.',
        stamp,
      );
    }
    if (e.status == 416) {
      return BookProblem(
        ProblemKind.empty,
        'The file in Google Drive is shorter than Drive says.',
        stamp,
      );
    }
    if (e.status == 403 && !_isRateLimit(e)) {
      return BookProblem(
        ProblemKind.noAccess,
        'Google Drive would not let this file be downloaded: ${e.message}',
        stamp,
      );
    }
    return null;
  }

  static bool _isConnectionError(Object e) =>
      e is SocketException ||
      e is http.ClientException ||
      e is TimeoutException ||
      e is HandshakeException;

  static bool _isRateLimit(Object e) =>
      e is drive.DetailedApiRequestError &&
      (e.status == 429 ||
          e.errors.any((d) => '${d.reason}'.contains('ateLimit')));

  static String _stopMessage(Object e) => _isRateLimit(e)
      ? 'Stopped: Google Drive asked to slow down. Try again in a few '
            'minutes.'
      : 'Stopped: Google Drive could not be reached. Check the connection '
            'and try again.';
}

String _article(BookFormat format) {
  const an = {'EPUB', 'AZW3', 'FB2', 'RTF', 'ODT'};
  return '${an.contains(format.label) ? 'an' : 'a'} ${format.label}';
}

/// Why a [format] file of [size] bytes, whose first and last bytes are [head]
/// and [tail], is damaged, or null when nothing looks wrong.
///
/// These are the ways a file is cut short by an upload that never finished:
/// each format keeps something the reader needs at its end, or says up front
/// how long it is.
String? damageIn(BookFormat format, List<int> head, List<int> tail, int size) {
  const cutShort = 'It may not have finished uploading to Google Drive.';
  if (_startsWith(head, 'PK\x03\x04')) {
    // A ZIP (EPUB, CBZ, DOCX and so on) ends with the list of its contents.
    if (!_contains(tail, 'PK\x05\x06')) {
      return 'The end of this file is missing, so nothing inside it can be '
          'found. $cutShort';
    }
    return null;
  }
  switch (format) {
    case BookFormat.pdf:
      if (!_contains(tail, '%%EOF')) {
        return 'The end of this PDF is missing. $cutShort';
      }
    case BookFormat.mobi || BookFormat.azw3:
      // A Palm database lists where each of its records starts.
      if (head.length < 78) return 'This file is too short to be a book.';
      final count = head[76] << 8 | head[77];
      var missing = 0;
      for (var i = 0; i < count && 78 + i * 8 + 4 <= head.length; i++) {
        final at = 78 + i * 8;
        final offset =
            head[at] << 24 |
            head[at + 1] << 16 |
            head[at + 2] << 8 |
            head[at + 3];
        if (offset >= size) missing++;
      }
      if (missing > 0) {
        return '$missing of the $count parts of this book are missing. '
            '$cutShort';
      }
    case BookFormat.djvu:
      // An IFF file gives its own length after the FORM tag.
      if (_startsWith(head, 'AT&TFORM') && head.length >= 12) {
        final length = head[8] << 24 | head[9] << 16 | head[10] << 8 | head[11];
        if (12 + length > size) {
          return 'The end of this DjVu file is missing. $cutShort';
        }
      }
    default:
  }
  return null;
}

bool _startsWith(List<int> bytes, String prefix) =>
    bytes.length >= prefix.length &&
    latin1.decode(bytes.sublist(0, prefix.length)) == prefix;

bool _contains(List<int> bytes, String pattern) =>
    latin1.decode(bytes, allowInvalid: true).contains(pattern);
