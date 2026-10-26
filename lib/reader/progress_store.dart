import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;

/// Where one book was left off.
class ReadingProgress {
  const ReadingProgress({
    required this.location,
    required this.fraction,
    required this.updatedAt,
  });

  /// An EPUB CFI for reflowable books, or a page number for PDFs.
  final String location;

  /// Progress through the whole book, 0 to 1.
  final double fraction;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'location': location,
    'fraction': fraction,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static ReadingProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final location = json['location'];
    final fraction = json['fraction'];
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (location is! String || fraction is! num || updatedAt == null) {
      return null;
    }
    return ReadingProgress(
      location: location,
      fraction: fraction.toDouble(),
      updatedAt: updatedAt,
    );
  }
}

/// Merges two progress maps keyed by Drive file id; the newer entry wins.
Map<String, ReadingProgress> mergeProgress(
  Map<String, ReadingProgress> a,
  Map<String, ReadingProgress> b,
) {
  final merged = {...a};
  b.forEach((id, theirs) {
    final ours = merged[id];
    if (ours == null || theirs.updatedAt.isAfter(ours.updatedAt)) {
      merged[id] = theirs;
    }
  });
  return merged;
}

Map<String, ReadingProgress> decodeProgress(String text) {
  final json = jsonDecode(text);
  if (json is! Map) return {};
  final books = json['books'];
  if (books is! Map) return {};
  return {
    for (final MapEntry(:key, :value) in books.entries)
      '$key': ?ReadingProgress.fromJson(value),
  };
}

String encodeProgress(Map<String, ReadingProgress> progress) => jsonEncode({
  'version': 1,
  'books': {for (final e in progress.entries) e.key: e.value.toJson()},
});

/// Stores the synced copy of reading progress.
abstract interface class ProgressRemote {
  Future<String?> read();
  Future<void> write(String contents);
}

/// Reading progress, kept in a local file and synced to Drive's hidden app
/// data folder so every device resumes at the same place.
class ProgressStore {
  ProgressStore(this._localFile, this._remote);

  final File _localFile;
  final ProgressRemote? _remote;
  Map<String, ReadingProgress> _progress = {};
  Timer? _pushTimer;

  ReadingProgress? operator [](String driveFileId) => _progress[driveFileId];

  /// Loads the local copy, then merges in the remote one.
  Future<void> load() async {
    if (await _localFile.exists()) {
      try {
        _progress = decodeProgress(await _localFile.readAsString());
      } on FormatException {
        _progress = {};
      }
    }
    await sync();
  }

  /// Pulls the remote copy, merges, and pushes the result back.
  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    try {
      final text = await remote.read();
      if (text != null) {
        _progress = mergeProgress(_progress, decodeProgress(text));
      }
      await _saveLocal();
      await remote.write(encodeProgress(_progress));
    } catch (_) {
      // Offline: the local copy is kept and pushed on the next sync.
    }
  }

  /// Records progress now and pushes it to Drive a few seconds later, so a
  /// burst of page turns becomes one upload.
  Future<void> save(String driveFileId, ReadingProgress progress) async {
    _progress[driveFileId] = progress;
    await _saveLocal();
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), sync);
  }

  /// Pushes any pending change immediately, for example when a book closes.
  Future<void> flush() async {
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await sync();
    }
  }

  Future<void> _saveLocal() async {
    await _localFile.parent.create(recursive: true);
    await _localFile.writeAsString(encodeProgress(_progress));
  }
}

/// A JSON file in the Drive appDataFolder, invisible in the user's Drive.
class DriveAppDataRemote implements ProgressRemote {
  DriveAppDataRemote(this._api, this._name);

  final drive.DriveApi _api;
  final String _name;
  String? _fileId;

  Future<String?> _findId() async {
    if (_fileId != null) return _fileId;
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_name'",
      $fields: 'files(id)',
    );
    return _fileId = list.files?.firstOrNull?.id;
  }

  @override
  Future<String?> read() async {
    final id = await _findId();
    if (id == null) return null;
    final media = await _api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    return utf8.decodeStream(media.stream);
  }

  @override
  Future<void> write(String contents) async {
    final bytes = utf8.encode(contents);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );
    final id = await _findId();
    if (id == null) {
      final created = await _api.files.create(
        drive.File(name: _name, parents: ['appDataFolder']),
        uploadMedia: media,
        $fields: 'id',
      );
      _fileId = created.id;
    } else {
      await _api.files.update(drive.File(), id, uploadMedia: media);
    }
  }
}
