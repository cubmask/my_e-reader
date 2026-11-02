import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../car/car_library.dart';
import '../car/car_player.dart';
import '../read_aloud.dart';

/// The book being read aloud, as the lock screen, the notification and
/// Android Auto show it, with what their buttons do.
class NowReading {
  const NowReading({
    required this.id,
    required this.title,
    this.author = '',
    this.cover,
    this.chapter = '',
    this.byChapter = true,
    this.start,
    this.nextChapter,
    this.previousChapter,
    this.released,
  });

  /// The book's Drive file id.
  final String id;
  final String title;
  final String author;
  final File? cover;
  final String chapter;

  /// Whether the book has chapters a sleep timer can wait for.
  final bool byChapter;

  /// Starts reading aloud from the reading position, for a play pressed in
  /// the car after reading stopped.
  final Future<void> Function()? start;
  final Future<void> Function()? nextChapter;
  final Future<void> Function()? previousChapter;

  /// Called once another book takes over the media session.
  final VoidCallback? released;

  NowReading copyWith({String? chapter}) => NowReading(
    id: id,
    title: title,
    author: author,
    cover: cover,
    chapter: chapter ?? this.chapter,
    byChapter: byChapter,
    start: start,
    nextChapter: nextChapter,
    previousChapter: previousChapter,
    released: released,
  );
}

/// Keeps reading aloud with the screen locked or the app in the background,
/// with play, pause and stop on the lock screen and in the notification.
///
/// On Android this runs a media playback foreground service, without which
/// the system pauses the app soon after the screen turns off. The same
/// service is what Android Auto browses and controls.
class BackgroundAudio {
  BackgroundAudio._();

  static final instance = BackgroundAudio._();

  Future<CarAudioHandler?>? _handler;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Starts the media service early, so that Android Auto finds it when it
  /// connects before any book has been opened. [car] supplies the library
  /// the car browses.
  Future<void> start({CarSource? car}) async {
    if (!supported) return;
    final handler = await (_handler ??= _start());
    handler?.car = car;
  }

  /// Shows [book] as the media of [reader], as playing while it is read
  /// aloud. An [offer] (a book just opened on screen) doesn't take over from
  /// another book being read aloud.
  Future<void> attach(
    ReadAloud reader,
    NowReading book, {
    bool offer = false,
  }) async {
    if (!supported) return;
    final handler = await (_handler ??= _start());
    handler?.open(reader, book, offer: offer);
  }

  /// The chapter shown under the title.
  void setChapter(ReadAloud reader, String chapter) {
    _handler?.then((h) => h?.setChapter(reader, chapter));
  }

  void detach(ReadAloud reader) {
    _handler?.then((h) => h?.detach(reader));
  }

  Future<CarAudioHandler?> _start() async {
    try {
      return await AudioService.init(
        builder: CarAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.cubmask.ebook_reader.read_aloud',
          androidNotificationChannelName: 'Read aloud',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          // Books show in the car as covers, folders as a list.
          androidBrowsableRootExtras: {
            'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
            'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 2,
            'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
            'android.media.browse.SEARCH_SUPPORTED': true,
          },
        ),
      );
    } catch (e) {
      debugPrint('Background audio unavailable: $e');
      return null;
    }
  }
}

/// Reading speeds the car's speed button steps through.
const carSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

/// The sleep timer steps the car's sleep button goes through, in minutes;
/// 0 waits for the end of the chapter.
const carSleepSteps = [15, 30, 60, 0];

/// Folders the car shows as tabs.
const carContinueId = 'continue';
const carDownloadedId = 'downloaded';
const carCollectionsId = 'collections';
const _collectionPrefix = 'collection:';
const _bookPrefix = 'book:';

/// The media id of a book, as the car plays it.
String carBookId(String driveFileId) => '$_bookPrefix$driveFileId';

/// Connects read aloud to the media session: the notification, the lock
/// screen, headset buttons and Android Auto.
class CarAudioHandler extends BaseAudioHandler {
  /// The library the car browses; null until the app has started it.
  CarSource? car;

  ReadAloud? _reader;
  NowReading? _book;

  /// Where the sleep button is in [carSleepSteps]; -1 is off.
  int _sleepStep = -1;

  /// Shown in the car until something plays.
  String? _error;

  /// Set while a book started from the car is opening.
  bool _loading = false;

  void open(ReadAloud reader, NowReading book, {bool offer = false}) {
    final previous = _reader;
    if (offer && previous != null && previous != reader && previous.active) {
      return;
    }
    if (previous != reader) {
      previous?.removeListener(_update);
      if (previous?.active ?? false) previous!.stop();
      final released = _book?.released;
      _reader = reader..addListener(_update);
      _sleepStep = -1;
      released?.call();
    }
    _book = book;
    _error = null;
    _publishItem();
    _update();
  }

  void setChapter(ReadAloud reader, String chapter) {
    final book = _book;
    if (_reader != reader || book == null || book.chapter == chapter) return;
    _book = book.copyWith(chapter: chapter);
    _publishItem();
  }

  void detach(ReadAloud reader) {
    if (_reader != reader) return;
    reader.removeListener(_update);
    _reader = null;
    _book = null;
    _sleepStep = -1;
    mediaItem.add(null);
    _update();
  }

  MediaItem? _item() {
    final book = _book;
    if (book == null) return null;
    return MediaItem(
      id: carBookId(book.id),
      title: book.title,
      artist: book.author.isEmpty ? null : book.author,
      album: book.chapter.isEmpty ? null : book.chapter,
      displayTitle: book.title,
      displaySubtitle: [
        if (book.author.isNotEmpty) book.author,
        if (book.chapter.isNotEmpty) book.chapter,
      ].join(' · '),
      artUri: book.cover == null ? null : Uri.file(book.cover!.path),
      playable: true,
    );
  }

  void _publishItem() => mediaItem.add(_item());

  void _update() {
    final reader = _reader;
    final book = _book;
    final active = reader?.active ?? false;
    final playing = reader?.playing ?? false;
    if (reader != null && _sleepStep >= 0) {
      // The timer ran out or was changed on the phone.
      if (reader.sleepAt == null && !reader.sleepAtChapterEnd) _sleepStep = -1;
    }
    final error = _error;
    playbackState.add(
      PlaybackState(
        controls: [
          if (book?.previousChapter != null) MediaControl.skipToPrevious,
          if (active) _backControl,
          if (playing) MediaControl.pause else MediaControl.play,
          if (book?.nextChapter != null) MediaControl.skipToNext,
          if (active) _speedControl(reader!.speed),
          if (active) _sleepControl(),
          if (active) MediaControl.stop,
        ],
        systemActions: {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
          MediaAction.prepareFromSearch,
          MediaAction.rewind,
          MediaAction.stop,
          if (book?.nextChapter != null) MediaAction.skipToNext,
          if (book?.previousChapter != null) MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: _compactIndices(book, active),
        processingState: error != null
            ? AudioProcessingState.error
            : _loading
            ? AudioProcessingState.loading
            : active
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        errorMessage: error,
        playing: playing,
        speed: reader?.speed ?? 1.0,
      ),
    );
  }

  /// Back, play or pause, and next chapter fit in the small notification.
  List<int> _compactIndices(NowReading? book, bool active) {
    var i = 0;
    if (book?.previousChapter != null) i++;
    final indices = <int>[];
    if (active) indices.add(i++);
    indices.add(i++);
    if (book?.nextChapter != null) indices.add(i);
    return indices;
  }

  static const _backControl = MediaControl(
    androidIcon: 'drawable/audio_service_fast_rewind',
    label: 'Back a sentence',
    action: MediaAction.rewind,
  );

  static MediaControl _speedControl(double speed) => MediaControl.custom(
    androidIcon: 'drawable/ic_car_speed',
    label: 'Speed ${speed}x',
    name: 'speed',
  );

  MediaControl _sleepControl() {
    final step = _sleepStep;
    final label = step < 0
        ? 'Sleep timer off'
        : carSleepSteps[step] == 0
        ? 'Sleep at end of chapter'
        : 'Sleep in ${carSleepSteps[step]} min';
    return MediaControl.custom(
      androidIcon: 'drawable/ic_car_sleep',
      label: label,
      name: 'sleep',
    );
  }

  void _showError(String message) {
    _error = message;
    _update();
  }

  // Browsing

  static MediaItem _folder(String id, String title) =>
      MediaItem(id: id, title: title, playable: false);

  static MediaItem _bookItem(CarBook b) {
    final fraction = b.fraction;
    return MediaItem(
      id: carBookId(b.book.driveFileId),
      title: b.title,
      artist: b.author.isEmpty ? null : b.author,
      displaySubtitle: [
        if (b.author.isNotEmpty) b.author,
        if (fraction != null && fraction > 0) '${(fraction * 100).round()}%',
      ].join(' · '),
      artUri: b.cover == null ? null : Uri.file(b.cover!.path),
      playable: true,
      extras: {
        // Android Auto's progress bar under the cover.
        if (fraction != null && fraction > 0) ...{
          'android.media.extra.PLAYBACK_STATUS': 1,
          'androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE': fraction,
        },
      },
    );
  }

  static List<MediaItem> _books(List<CarBook> books) => [
    for (final b in books)
      if (canReadInCar(b.book.format)) _bookItem(b),
  ];

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final library = await car?.library();
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        if (library == null) {
          // Signed out: only a book open on screen can play.
          return [?_item()];
        }
        return [
          _folder(carContinueId, 'Continue'),
          _folder(carDownloadedId, 'Downloaded'),
          if (library.collections().isNotEmpty)
            _folder(carCollectionsId, 'Collections'),
        ];
      case AudioService.recentRootId:
        if (_item() case final item?) return [item];
        final recent = library == null
            ? const <MediaItem>[]
            : _books(library.recent());
        return recent.take(1).toList();
      case carContinueId:
        return library == null ? const [] : _books(library.recent());
      case carDownloadedId:
        return library == null ? const [] : _books(library.downloaded());
      case carCollectionsId:
        return [
          for (final name in library?.collections() ?? const <String>[])
            _folder('$_collectionPrefix$name', name),
        ];
    }
    if (parentMediaId.startsWith(_collectionPrefix) && library != null) {
      return _books(
        library.inCollection(parentMediaId.substring(_collectionPrefix.length)),
      );
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final item = _item();
    if (item?.id == mediaId) return item;
    if (!mediaId.startsWith(_bookPrefix)) return null;
    final library = await car?.library();
    final book = library?.byId(mediaId.substring(_bookPrefix.length));
    return book == null ? null : _bookItem(book);
  }

  @override
  Future<List<MediaItem>> search(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    final library = await car?.library();
    return library == null ? const [] : _books(library.search(query));
  }

  // Playing

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (!mediaId.startsWith(_bookPrefix)) return;
    final id = mediaId.substring(_bookPrefix.length);
    if (_book?.id == id) return play();
    await _playFromCar(id);
  }

  /// "Read Dune on My E-Reader": the best match in the library. An empty
  /// query ("play My E-Reader") carries on with the last book.
  @override
  Future<void> playFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {
    if (query.trim().isEmpty) return play();
    final library = await car?.library();
    if (library == null) {
      return _showError("Sign in on your phone when it's safe");
    }
    final found = [
      for (final b in library.search(query))
        if (canReadInCar(b.book.format)) b,
    ];
    if (found.isEmpty) {
      return _showError('“$query” isn’t in your library');
    }
    await _playFromCar(found.first.book.driveFileId);
  }

  @override
  Future<void> prepareFromSearch(
    String query, [
    Map<String, dynamic>? extras,
  ]) async {}

  Future<void> _playFromCar(String driveFileId) async {
    final car = this.car;
    if (car == null) {
      return _showError("Open the book on your phone when it's safe");
    }
    _error = null;
    _loading = true;
    _update();
    try {
      await car.play(driveFileId);
      _loading = false;
      _update();
    } on CarError catch (e) {
      _loading = false;
      _showError(e.message);
    } catch (e) {
      _loading = false;
      debugPrint('Car playback failed: $e');
      _showError('This book couldn’t be opened');
    }
  }

  @override
  Future<void> play() async {
    final reader = _reader;
    final book = _book;
    if (reader == null || book == null) {
      // Nothing open: carry on with the book read last.
      final last = (await car?.library())?.recent().where(
        (b) => canReadInCar(b.book.format),
      );
      if (last != null && last.isNotEmpty) {
        return _playFromCar(last.first.book.driveFileId);
      }
      return _showError(
        car == null
            ? "Open a book on your phone when it's safe"
            : "Sign in on your phone when it's safe",
      );
    }
    _error = null;
    if (reader.active) return reader.resume();
    final start = book.start;
    if (start == null) return _showError('This book can’t be read aloud');
    await start();
  }

  @override
  Future<void> pause() async => _reader?.pause();

  @override
  Future<void> rewind() async => _reader?.skipBack();

  @override
  Future<void> skipToNext() async => _book?.nextChapter?.call();

  @override
  Future<void> skipToPrevious() async => _book?.previousChapter?.call();

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    final reader = _reader;
    if (reader == null) return;
    switch (name) {
      case 'speed':
        final i = carSpeeds.indexWhere((s) => s >= reader.speed - 0.01);
        final next = carSpeeds[(i < 0 ? 0 : i + 1) % carSpeeds.length];
        await reader.setSpeed(next);
      case 'sleep':
        final byChapter = _book?.byChapter ?? false;
        var step = _sleepStep + 1;
        if (step < carSleepSteps.length && carSleepSteps[step] == 0) {
          if (!byChapter) step++;
        }
        if (step >= carSleepSteps.length) {
          _sleepStep = -1;
          reader.setSleepTimer(null);
        } else {
          _sleepStep = step;
          final minutes = carSleepSteps[step];
          if (minutes == 0) {
            reader.sleepAtEndOfChapter();
          } else {
            reader.setSleepTimer(Duration(minutes: minutes));
          }
        }
        _update();
    }
  }

  @override
  Future<void> stop() async {
    await _reader?.stop();
    await super.stop();
  }
}
