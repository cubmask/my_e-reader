import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../read_aloud.dart';

/// Keeps reading aloud with the screen locked or the app in the background,
/// with play, pause and stop on the lock screen and in the notification.
///
/// On Android this runs a media playback foreground service, without which
/// the system pauses the app soon after the screen turns off.
class BackgroundAudio {
  BackgroundAudio._();

  static final instance = BackgroundAudio._();

  Future<_Handler?>? _handler;

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Shows [reader] as the playing media while it reads [title].
  Future<void> attach(ReadAloud reader, {required String title}) async {
    if (!supported) return;
    final handler = await (_handler ??= _start());
    handler?.attach(reader, title);
  }

  void detach(ReadAloud reader) {
    _handler?.then((h) => h?.detach(reader));
  }

  Future<_Handler?> _start() async {
    try {
      return await AudioService.init(
        builder: _Handler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.cubmask.ebook_reader.read_aloud',
          androidNotificationChannelName: 'Read aloud',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e) {
      debugPrint('Background audio unavailable: $e');
      return null;
    }
  }
}

class _Handler extends BaseAudioHandler {
  ReadAloud? _reader;

  void attach(ReadAloud reader, String title) {
    if (_reader != reader) {
      _reader?.removeListener(_update);
      _reader = reader..addListener(_update);
    }
    mediaItem.add(MediaItem(id: title, title: title, album: 'Reading aloud'));
    _update();
  }

  void detach(ReadAloud reader) {
    if (_reader != reader) return;
    reader.removeListener(_update);
    _reader = null;
    _update();
  }

  void _update() {
    final reader = _reader;
    final active = reader?.active ?? false;
    final playing = reader?.playing ?? false;
    playbackState.add(
      PlaybackState(
        controls: [
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
        ],
        systemActions: const {MediaAction.play, MediaAction.pause},
        androidCompactActionIndices: const [0, 1],
        processingState: active
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: playing,
      ),
    );
  }

  @override
  Future<void> play() async => _reader?.resume();

  @override
  Future<void> pause() async => _reader?.pause();

  @override
  Future<void> stop() async {
    await _reader?.stop();
    await super.stop();
  }
}
