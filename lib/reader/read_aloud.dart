import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// One sentence to speak; [mark] lets the source highlight it.
class SpeechSegment {
  const SpeechSegment(this.text, [this.mark]);

  final String text;
  final String? mark;
}

/// Supplies text to read aloud, one block (paragraph or page) at a time.
abstract interface class SpeechSource {
  /// The block at the current reading position.
  Future<List<SpeechSegment>?> start();

  /// The following block, turning pages as needed; null at the end.
  Future<List<SpeechSegment>?> next();

  /// Called just before [segment] is spoken.
  void onSegment(SpeechSegment segment);

  void stop();
}

/// Speaks segments one by one with the platform voice.
class ReadAloud extends ChangeNotifier {
  ReadAloud({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  SpeechSource? _source;
  bool _playing = false;
  double _speed = 1.0;
  int _run = 0;

  bool get playing => _playing;
  bool get active => _source != null;

  /// 1.0 is normal speed.
  double get speed => _speed;

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    // flutter_tts treats 0.5 as the platform's normal rate.
    await _tts.setSpeechRate(0.5 * speed);
  }

  Future<void> play(SpeechSource source) async {
    await stop();
    _source = source;
    final run = ++_run;
    _playing = true;
    notifyListeners();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.5 * _speed);
    var block = await source.start();
    while (block != null && run == _run) {
      for (final segment in block) {
        if (run != _run) return;
        if (segment.text.trim().isEmpty) continue;
        source.onSegment(segment);
        await _tts.speak(segment.text);
      }
      if (run != _run) return;
      block = await source.next();
    }
    if (run == _run) await stop();
  }

  Future<void> stop() async {
    _run++;
    final source = _source;
    _source = null;
    _playing = false;
    notifyListeners();
    await _tts.stop();
    source?.stop();
  }

  @override
  void dispose() {
    _run++;
    _tts.stop();
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
    for (final m in RegExp(r'[^.!?…]+(?:[.!?…]+["”’)\]]*|$)').allMatches(clean))
      if (m[0]!.trim().isNotEmpty) SpeechSegment(m[0]!.trim()),
  ];
}
