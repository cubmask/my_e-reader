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
    this.chapter = '',
    this.device = '',
    this.deviceName = '',
  });

  /// An EPUB CFI for reflowable books, or a page number for PDFs.
  final String location;

  /// Progress through the whole book, 0 to 1.
  final double fraction;
  final DateTime updatedAt;

  /// The chapter at [location], when known.
  final String chapter;

  /// The id of the device that read to here, and its name for people, such
  /// as "Galaxy Tab S9 Ultra". Empty in entries from before they were kept.
  final String device;
  final String deviceName;

  ReadingProgress copyWith({String? device, String? deviceName}) =>
      ReadingProgress(
        location: location,
        fraction: fraction,
        updatedAt: updatedAt,
        chapter: chapter,
        device: device ?? this.device,
        deviceName: deviceName ?? this.deviceName,
      );

  Map<String, Object> toJson() => {
    'location': location,
    'fraction': fraction,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (chapter.isNotEmpty) 'chapter': chapter,
    if (device.isNotEmpty) 'device': device,
    if (deviceName.isNotEmpty) 'deviceName': deviceName,
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
      chapter: '${json['chapter'] ?? ''}',
      device: '${json['device'] ?? ''}',
      deviceName: '${json['deviceName'] ?? ''}',
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

/// Decodes the books in a progress file, or with [own] this device's own
/// places, which only the local copy keeps.
Map<String, ReadingProgress> decodeProgress(String text, {bool own = false}) {
  final json = jsonDecode(text);
  if (json is! Map) return {};
  final books = json[own ? 'own' : 'books'];
  if (books is! Map) return {};
  return {
    for (final MapEntry(:key, :value) in books.entries)
      '$key': ?ReadingProgress.fromJson(value),
  };
}

String encodeProgress(
  Map<String, ReadingProgress> progress, {
  Map<String, ReadingProgress>? own,
}) => jsonEncode({
  'version': 1,
  'books': {for (final e in progress.entries) e.key: e.value.toJson()},
  if (own != null)
    'own': {for (final e in own.entries) e.key: e.value.toJson()},
});

/// Stores the synced copy of reading progress.
abstract interface class ProgressRemote {
  Future<String?> read();
  Future<void> write(String contents);
}

/// Reading progress, kept in a local file and synced to Drive's hidden app
/// data folder.
///
/// Each device also remembers its own place in every book, so a book opens
/// where it was left on this device and a newer place read elsewhere is
/// offered (see [elsewhere]) rather than jumped to.
class ProgressStore {
  ProgressStore(
    this._localFile,
    this._remote, {
    this.device = '',
    this.deviceName = '',
  });

  final File _localFile;
  final ProgressRemote? _remote;

  /// This device's id and its name for people.
  final String device;
  final String deviceName;
  Map<String, ReadingProgress> _progress = {};
  Map<String, ReadingProgress> _own = {};
  Timer? _pushTimer;

  /// The newest place in the book, read on any device.
  ReadingProgress? operator [](String driveFileId) => _progress[driveFileId];

  /// Where the book was left on this device.
  ReadingProgress? ownOf(String driveFileId) => _own[driveFileId];

  /// A place read on another device more recently than on this one, when
  /// it differs from this device's.
  ReadingProgress? elsewhere(String driveFileId) {
    final theirs = _progress[driveFileId];
    final ours = _own[driveFileId];
    if (theirs == null || ours == null) return null;
    if (theirs.device.isEmpty || theirs.device == device) return null;
    if (!theirs.updatedAt.isAfter(ours.updatedAt)) return null;
    if (theirs.location == ours.location) return null;
    return theirs;
  }

  /// Loads the local copy, then merges in the remote one.
  Future<void> load() async {
    if (await _localFile.exists()) {
      try {
        final text = await _localFile.readAsString();
        _progress = decodeProgress(text);
        _own = decodeProgress(text, own: true);
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
    progress = progress.copyWith(device: device, deviceName: deviceName);
    _progress[driveFileId] = progress;
    _own[driveFileId] = progress;
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
    await _localFile.writeAsString(encodeProgress(_progress, own: _own));
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
