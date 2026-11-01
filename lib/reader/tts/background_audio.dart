import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

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
  /// connects before any book has been opened.
  Future<void> start() async {
    if (!supported) return;
    await (_handler ??= _start());
  }

  /// Shows [book] as the media of [reader]: offered to the car while the book
  /// is open, and shown as playing while it is read aloud.
  Future<void> attach(ReadAloud reader, NowReading book) async {
    if (!supported) return;
    final handler = await (_handler ??= _start());
    handler?.open(reader, book);
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
          // Android Auto shows books as covers rather than a plain list.
          androidBrowsableRootExtras: {
            'android.media.browse.CONTENT_STYLE_SUPPORTED': true,
            'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT': 2,
            'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT': 1,
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

/// Connects read aloud to the media session: the notification, the lock
/// screen, headset buttons and Android Auto.
class CarAudioHandler extends BaseAudioHandler {
  ReadAloud? _reader;
  NowReading? _book;

  /// Where the sleep button is in [carSleepSteps]; -1 is off.
  int _sleepStep = -1;

  /// Shown in the car until something plays.
  String? _error;

  void open(ReadAloud reader, NowReading book) {
    if (_reader != reader) {
      _reader?.removeListener(_update);
      _reader = reader..addListener(_update);
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
      id: book.id,
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
          if (active) _sleepControl(book?.byChapter ?? false),
          if (active) MediaControl.stop,
        ],
        systemActions: {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.playFromMediaId,
          MediaAction.rewind,
          MediaAction.stop,
          if (book?.nextChapter != null) MediaAction.skipToNext,
          if (book?.previousChapter != null) MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: _compactIndices(book, active),
        processingState: error != null
            ? AudioProcessingState.error
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

  MediaControl _sleepControl(bool byChapter) {
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

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
      case AudioService.recentRootId:
        return [?_item()];
    }
    return const [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final item = _item();
    return item?.id == mediaId ? item : null;
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (_book?.id != mediaId) {
      return _showError("Open the book on your phone when it's safe");
    }
    await play();
  }

  @override
  Future<void> play() async {
    final reader = _reader;
    final book = _book;
    if (reader == null || book == null) {
      return _showError("Open a book on your phone when it's safe");
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
