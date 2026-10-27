import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// The sentences around the one being spoken, which some voices use to
/// carry the intonation across.
typedef SpeechContext = ({String? previous, String? next});

/// Turns sentences into speech, one at a time.
abstract interface class SpeechEngine {
  /// Speaks [text], completing once it has been spoken or stopped.
  Future<void> speak(String text, [SpeechContext? context]);

  /// A hint that [text] is spoken next, so it can be prepared ahead.
  void prepare(String text, [SpeechContext? context]);

  /// Pauses mid-sentence; false when the engine can only stop.
  Future<bool> pause();

  Future<void> resume();

  Future<void> stop();

  /// 1.0 is normal speed.
  Future<void> setSpeed(double speed);

  /// A base language code such as 'en'.
  Future<void> setLanguage(String language);
}

/// The platform's own text-to-speech voices.
class SystemSpeechEngine implements SpeechEngine {
  SystemSpeechEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _awaiting = false;

  @override
  Future<void> speak(String text, [SpeechContext? context]) async {
    if (!_awaiting) {
      _awaiting = true;
      await _tts.awaitSpeakCompletion(true);
    }
    await _tts.speak(text);
  }

  @override
  void prepare(String text, [SpeechContext? context]) {}

  @override
  Future<bool> pause() async => false;

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async => _tts.stop();

  // flutter_tts treats 0.5 as the platform's normal rate.
  @override
  Future<void> setSpeed(double speed) async => _tts.setSpeechRate(0.5 * speed);

  @override
  Future<void> setLanguage(String language) async {
    try {
      if (await _tts.isLanguageAvailable(language) == true) {
        await _tts.setLanguage(language);
      }
    } catch (_) {
      // Keep the default voice when the platform can't tell.
    }
  }
}

/// Renders a sentence to an audio file.
abstract interface class Synthesizer {
  Future<String> synthesize(
    String text, {
    required String language,
    required int speaker,
    required double speed,
    SpeechContext? context,
  });
}

/// Plays rendered sentences.
abstract interface class AudioOut {
  /// Completes when [path] has played to the end or was stopped.
  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

/// An offline neural voice: renders the next sentence while the current
/// one plays, so there is no wait between them.
class NeuralSpeechEngine implements SpeechEngine {
  NeuralSpeechEngine(this._synth, this._out, {this.speaker = 0});

  final Synthesizer _synth;
  final AudioOut _out;
  int speaker;
  String _language = 'en';
  double _speed = 1.0;
  int _run = 0;
  final _rendered = <String, Future<String>>{};

  /// Set while paused, so a sentence still rendering waits to play.
  Completer<void>? _resumed;

  String _key(String text) => '$_language|$speaker|$_speed|$text';

  // The context is left out of the key so a sentence prepared ahead is
  // never rendered twice.
  Future<String> _render(String text, SpeechContext? context) =>
      _rendered.putIfAbsent(
        _key(text),
        () => _synth.synthesize(
          text,
          language: _language,
          speaker: speaker,
          speed: _speed,
          context: context,
        ),
      );

  void _discardRendered() {
    for (final path in _rendered.values) {
      path.then(_delete, onError: (_) {});
    }
    _rendered.clear();
  }

  static void _delete(String path) =>
      File(path).delete().then((_) {}, onError: (_) {});

  @override
  Future<void> speak(String text, [SpeechContext? context]) async {
    final run = _run;
    final key = _key(text);
    final String path;
    try {
      path = await _render(text, context);
    } finally {
      _rendered.remove(key);
    }
    try {
      if (_resumed case final resumed?) await resumed.future;
      if (run == _run) await _out.play(path);
    } finally {
      _delete(path);
    }
  }

  @override
  void prepare(String text, [SpeechContext? context]) =>
      _render(text, context).then((_) {}, onError: (_) {});

  @override
  Future<bool> pause() async {
    _resumed ??= Completer<void>();
    await _out.pause();
    return true;
  }

  @override
  Future<void> resume() async {
    _resumed?.complete();
    _resumed = null;
    await _out.resume();
  }

  @override
  Future<void> stop() async {
    _run++;
    _resumed?.complete();
    _resumed = null;
    _discardRendered();
    await _out.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (speed == _speed) return;
    _speed = speed;
    _discardRendered();
  }

  @override
  Future<void> setLanguage(String language) async {
    if (language == _language) return;
    _language = language;
    _discardRendered();
  }
}

/// Plays WAV files with the platform media player, keeping the device
/// awake so reading goes on with the screen off.
class PlayerAudioOut implements AudioOut {
  PlayerAudioOut() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.setAudioContext(AudioContextConfig(stayAwake: true).build());
    _player.onPlayerComplete.listen((_) => _finish());
  }

  final _player = AudioPlayer();
  Completer<void>? _done;

  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> play(String path) async {
    _finish();
    final done = _done = Completer<void>();
    await _player.play(DeviceFileSource(path));
    return done.future;
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() async {
    await _player.stop();
    _finish();
  }

  Future<void> dispose() async {
    _finish();
    await _player.dispose();
  }
}

/// Speaks with a primary engine until it fails, such as an online voice
/// losing its connection, then carries on with the fallback from the same
/// sentence.
class FallbackSpeechEngine implements SpeechEngine {
  FallbackSpeechEngine(this._current, this._fallback, {this.onFallback});

  SpeechEngine _current;
  final Future<SpeechEngine> Function() _fallback;
  final void Function(Object error)? onFallback;
  bool _fellBack = false;
  int _run = 0;
  String? _language;
  double? _speed;

  @override
  Future<void> speak(String text, [SpeechContext? context]) async {
    final run = _run;
    try {
      await _current.speak(text, context);
    } catch (e) {
      if (_fellBack) rethrow;
      _fellBack = true;
      onFallback?.call(e);
      final failed = _current;
      final next = await _fallback();
      if (_language case final language?) await next.setLanguage(language);
      if (_speed case final speed?) await next.setSpeed(speed);
      _current = next;
      unawaited(failed.stop());
      if (run == _run) await next.speak(text, context);
    }
  }

  @override
  void prepare(String text, [SpeechContext? context]) =>
      _current.prepare(text, context);

  @override
  Future<bool> pause() => _current.pause();

  @override
  Future<void> resume() => _current.resume();

  @override
  Future<void> stop() {
    _run++;
    return _current.stop();
  }

  @override
  Future<void> setSpeed(double speed) {
    _speed = speed;
    return _current.setSpeed(speed);
  }

  @override
  Future<void> setLanguage(String language) {
    _language = language;
    return _current.setLanguage(language);
  }
}
