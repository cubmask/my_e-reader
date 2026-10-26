import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tts/speech_engine.dart';
import 'tts/voice_pack.dart';

/// One sentence to speak; [mark] lets the source highlight it.
class SpeechSegment {
  const SpeechSegment(this.text, [this.mark]);

  final String text;
  final String? mark;
}

/// Supplies text to read aloud, one block (paragraph or page) at a time.
abstract interface class SpeechSource {
  /// The book's declared language, such as 'en-GB', when it has one.
  String? get language;

  /// The block at the current reading position.
  Future<List<SpeechSegment>?> start();

  /// The following block, turning pages as needed; null at the end.
  Future<List<SpeechSegment>?> next();

  /// Called just before [segment] is spoken.
  void onSegment(SpeechSegment segment);

  void stop();
}

/// Picks the reading language and the voice that speaks it.
abstract interface class Voices {
  /// The language to read [sample] in, given the book's own [declared] one.
  String languageFor(String sample, String? declared);

  /// The best voice for [language]: a downloaded one when it speaks the
  /// language, else the system's.
  Future<SpeechEngine> engineFor(String language);
}

/// Only the platform voices, in the language the text looks like.
class SystemVoices implements Voices {
  SystemVoices({SpeechEngine? engine})
    : _engine = engine ?? SystemSpeechEngine();

  final SpeechEngine _engine;

  @override
  String languageFor(String sample, String? declared) => resolveLanguage(
    sample,
    book: declared,
    fallback: baseLanguage(PlatformDispatcher.instance.locale.languageCode)!,
  );

  @override
  Future<SpeechEngine> engineFor(String language) async => _engine;
}

/// Speaks a [SpeechSource] sentence by sentence, preparing the next one
/// while the current one plays.
class ReadAloud extends ChangeNotifier {
  ReadAloud({Voices? voices}) : _voices = voices ?? SystemVoices();

  final Voices _voices;
  SpeechSource? _source;
  SpeechEngine? _engine;
  bool _playing = false;
  bool _paused = false;
  double _speed = 1.0;
  String? _language;
  int _run = 0;

  /// Set when a pause had to stop the sentence, which is then said again.
  bool _repeat = false;
  Completer<void>? _resumed;

  bool get playing => _playing && !_paused;
  bool get paused => _paused;
  bool get active => _source != null;

  /// The language being read, once reading has started.
  String? get language => _language;

  /// 1.0 is normal speed.
  double get speed => _speed;

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    await _engine?.setSpeed(speed);
  }

  Future<void> play(SpeechSource source) async {
    await stop();
    _source = source;
    final run = ++_run;
    _playing = true;
    notifyListeners();
    var block = await source.start();
    if (run != _run) return;
    final sample = (block ?? const []).map((s) => s.text).join(' ');
    final language = _language = _voices.languageFor(
      sample.length > 1000 ? sample.substring(0, 1000) : sample,
      source.language,
    );
    final engine = _engine = await _voices.engineFor(language);
    await engine.setLanguage(language);
    await engine.setSpeed(_speed);
    notifyListeners();
    String? previous;
    while (block != null && run == _run) {
      final segments = [
        for (final s in block)
          if (s.text.trim().isNotEmpty) s,
      ];
      String? textAt(int i) => i < segments.length ? segments[i].text : null;
      Future<List<SpeechSegment>?>? upcoming;
      for (var i = 0; i < segments.length; i++) {
        if (run != _run) return;
        final segment = segments[i];
        source.onSegment(segment);
        if (i + 1 < segments.length) {
          engine.prepare(textAt(i + 1)!, (
            previous: segment.text,
            next: textAt(i + 2),
          ));
        } else {
          // Fetch the next block while the last sentence plays.
          upcoming = source.next().then((next) {
            final texts = [
              for (final s in next ?? const <SpeechSegment>[])
                if (s.text.trim().isNotEmpty) s.text,
            ];
            if (texts.isNotEmpty && run == _run) {
              engine.prepare(texts.first, (
                previous: segment.text,
                next: texts.elementAtOrNull(1),
              ));
            }
            return next;
          });
        }
        final context = (previous: previous, next: textAt(i + 1));
        do {
          if (_resumed case final resumed?) await resumed.future;
          if (run != _run) return;
          _repeat = false;
          await engine.speak(segment.text, context);
        } while (_repeat && run == _run);
        previous = segment.text;
      }
      if (run != _run) return;
      block = await (upcoming ?? source.next());
    }
    if (run == _run) await stop();
  }

  /// Pauses reading; [resume] carries on from the same sentence.
  Future<void> pause() async {
    final engine = _engine;
    if (!active || _paused) return;
    _paused = true;
    _resumed = Completer<void>();
    notifyListeners();
    if (engine != null && !await engine.pause()) {
      _repeat = true;
      await engine.stop();
    }
  }

  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    notifyListeners();
    if (!_repeat) await _engine?.resume();
    _resumed?.complete();
    _resumed = null;
  }

  Future<void> stop() async {
    _run++;
    final source = _source;
    final engine = _engine;
    _source = null;
    _engine = null;
    _playing = false;
    _paused = false;
    _repeat = false;
    _resumed?.complete();
    _resumed = null;
    notifyListeners();
    await engine?.stop();
    source?.stop();
  }

  @override
  void dispose() {
    _run++;
    _resumed?.complete();
    _engine?.stop();
    super.dispose();
  }
}

/// Splits page text into sentences for speaking.
List<SpeechSegment> sentencesOf(String text) {
  final clean = text
      .replaceAll(RegExp(r'-\n(?=\w)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.isEmpty) return const [];
  return [
    for (final m in RegExp(
      r'[^.!?…。！？]+(?:[.!?…。！？]+["”’」)\]]*|$)',
    ).allMatches(clean))
      if (m[0]!.trim().isNotEmpty) SpeechSegment(m[0]!.trim()),
  ];
}
