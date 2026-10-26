import 'dart:io';

import 'package:ebook_reader/reader/tts/speech_engine.dart';
import 'package:ebook_reader/reader/tts/voice_pack.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSynth implements Synthesizer {
  _FakeSynth(this.dir);

  final Directory dir;
  final requests = <String>[];
  final contexts = <SpeechContext?>[];
  int _n = 0;

  @override
  Future<String> synthesize(
    String text, {
    required String language,
    required int speaker,
    required double speed,
    SpeechContext? context,
  }) async {
    requests.add('$language/$speaker/$speed: $text');
    contexts.add(context);
    final file = File('${dir.path}/${_n++}.wav');
    await file.writeAsString(text);
    return file.path;
  }
}

class _FakeOut implements AudioOut {
  final played = <String>[];
  final events = <String>[];

  @override
  Future<void> play(String path) async =>
      played.add(await File(path).readAsString());

  @override
  Future<void> pause() async => events.add('pause');

  @override
  Future<void> resume() async => events.add('resume');

  @override
  Future<void> stop() async => events.add('stop');
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('tts'));
  tearDown(() => dir.delete(recursive: true));

  test('renders ahead once, plays, and deletes each sentence', () async {
    final synth = _FakeSynth(dir);
    final out = _FakeOut();
    final engine = NeuralSpeechEngine(synth, out, speaker: 3);
    await engine.setLanguage('fr');
    await engine.setSpeed(1.25);

    engine.prepare('Deux.', (previous: 'Un.', next: null));
    await engine.speak('Un.', (previous: null, next: 'Deux.'));
    await engine.speak('Deux.', (previous: 'Un.', next: null));

    expect(out.played, ['Un.', 'Deux.']);
    expect(synth.requests, ['fr/3/1.25: Deux.', 'fr/3/1.25: Un.']);
    expect(synth.contexts, [
      (previous: 'Un.', next: null),
      (previous: null, next: 'Deux.'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(dir.listSync(), isEmpty);
  });

  test('a new speed renders the prepared sentence again', () async {
    final synth = _FakeSynth(dir);
    final engine = NeuralSpeechEngine(synth, _FakeOut());
    engine.prepare('One.');
    await engine.setSpeed(2.0);
    await engine.speak('One.');
    expect(synth.requests, ['en/0/1.0: One.', 'en/0/2.0: One.']);
  });

  test('pauses in place and holds back a sentence still rendering', () async {
    final out = _FakeOut();
    final engine = NeuralSpeechEngine(_FakeSynth(dir), out);
    expect(await engine.pause(), isTrue);
    var finished = false;
    final speaking = engine.speak('Later.').then((_) => finished = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(out.played, isEmpty);
    expect(finished, isFalse);
    await engine.resume();
    await speaking;
    expect(out.played, ['Later.']);
    expect(out.events, ['pause', 'resume']);
  });

  test('stop drops a sentence that is still rendering', () async {
    final out = _FakeOut();
    final engine = NeuralSpeechEngine(_FakeSynth(dir), out);
    final speaking = engine.speak('Never.');
    await engine.stop();
    await speaking;
    expect(out.played, isEmpty);
  });

  group('reading language', () {
    test('Latin text follows the book, then the fallback', () {
      expect(resolveLanguage('Bonjour à tous', book: 'fr-CA'), 'fr');
      expect(resolveLanguage('Hello there', fallback: 'de'), 'de');
      expect(resolveLanguage('Hello there', book: ''), 'en');
    });

    test('distinctive scripts win over wrong metadata', () {
      expect(resolveLanguage('Привет, мир', book: 'en'), 'ru');
      expect(resolveLanguage('Привіт, світе', book: 'uk'), 'uk');
      expect(resolveLanguage('吾輩は猫である', book: 'en'), 'ja');
      expect(resolveLanguage('我是一只猫'), 'zh');
      expect(resolveLanguage('안녕하세요'), 'ko');
      expect(resolveLanguage('Καλημέρα'), 'el');
      expect(resolveLanguage('नमस्ते'), 'hi');
    });

    test('Supertonic covers the main European and Asian languages', () {
      for (final code in ['en', 'de', 'fr', 'es', 'ja', 'ko', 'ru', 'hi']) {
        expect(supertonic3.speaks(code), isTrue, reason: code);
      }
      expect(supertonic3.speaks('zh'), isFalse);
      expect(supertonic3.speaks(null), isFalse);
      expect(languageName('de'), 'German');
      expect(languageName('zh'), 'Chinese');
    });
  });
}
