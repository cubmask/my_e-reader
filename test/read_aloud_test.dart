import 'dart:async';

import 'package:ebook_reader/reader/read_aloud.dart';
import 'package:ebook_reader/reader/tts/speech_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements SpeechEngine {
  _FakeEngine({this.canPause = false});

  final bool canPause;
  final spoken = <String>[];
  final prepared = <String>[];
  final contexts = <SpeechContext?>[];
  final preparedContexts = <SpeechContext?>[];
  double? speed;
  String? language;

  /// When set, each sentence waits for it before finishing.
  Completer<void>? gate;
  Completer<void>? _current;

  @override
  Future<void> speak(String text, [SpeechContext? context]) async {
    spoken.add(text);
    contexts.add(context);
    if (gate case final gate?) {
      final current = _current = Completer<void>();
      await Future.any([gate.future, current.future]);
    }
  }

  @override
  void prepare(String text, [SpeechContext? context]) {
    prepared.add(text);
    preparedContexts.add(context);
  }

  @override
  Future<bool> pause() async => canPause;

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    current?.complete();
  }

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<void> setLanguage(String language) async => this.language = language;
}

class _FakeVoices implements Voices {
  _FakeVoices(this.engine);

  final SpeechEngine engine;
  String? declared;

  @override
  String languageFor(String sample, String? declared) {
    this.declared = declared;
    return 'de';
  }

  @override
  Future<SpeechEngine> engineFor(String language) async => engine;
}

class _Source implements SpeechSource {
  _Source(this.blocks);

  final List<List<SpeechSegment>> blocks;
  final marks = <String?>[];
  int _i = 0;
  bool stopped = false;

  @override
  String? get language => 'de-AT';

  @override
  Future<List<SpeechSegment>?> start() async => blocks[_i = 0];

  @override
  Future<List<SpeechSegment>?> next() async =>
      ++_i < blocks.length ? blocks[_i] : null;

  @override
  void onSegment(SpeechSegment segment) => marks.add(segment.mark);

  @override
  void stop() => stopped = true;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('splits page text into sentences', () {
    expect(
      sentencesOf('First line of a hyphen-\nated word. Second? "Third!" Tail')
          .map((s) => s.text),
      ['First line of a hyphenated word.', 'Second?', '"Third!"', 'Tail'],
    );
    expect(sentencesOf('一つ。二つ！三つ'), [
      isA<SpeechSegment>().having((s) => s.text, 'text', '一つ。'),
      isA<SpeechSegment>().having((s) => s.text, 'text', '二つ！'),
      isA<SpeechSegment>().having((s) => s.text, 'text', '三つ'),
    ]);
    expect(sentencesOf('  \n '), isEmpty);
  });

  test(
    'speaks every block in order, preparing the next sentence ahead',
    () async {
      final engine = _FakeEngine();
      final voices = _FakeVoices(engine);
      final reader = ReadAloud(voices: voices);
      final source = _Source([
        [const SpeechSegment('One.', 'a'), const SpeechSegment('Two.', 'b')],
        [const SpeechSegment(' ', 'skip'), const SpeechSegment('Three.', 'c')],
      ]);
      await reader.setSpeed(1.5);
      await reader.play(source);

      expect(engine.spoken, ['One.', 'Two.', 'Three.']);
      expect(engine.prepared, ['Two.', 'Three.']);
      // Each sentence comes with its neighbours, across blocks too.
      expect(engine.contexts, [
        (previous: null, next: 'Two.'),
        (previous: 'One.', next: null),
        (previous: 'Two.', next: null),
      ]);
      expect(engine.preparedContexts, [
        (previous: 'One.', next: null),
        (previous: 'Two.', next: null),
      ]);
      expect(source.marks, ['a', 'b', 'c']);
      expect(engine.speed, 1.5);
      expect(engine.language, 'de');
      expect(voices.declared, 'de-AT');
      expect(reader.language, 'de');
      expect(source.stopped, isTrue);
      expect(reader.active, isFalse);
    },
  );

  test('a pause that has to stop says the sentence again', () async {
    final engine = _FakeEngine()..gate = Completer<void>();
    final reader = ReadAloud(voices: _FakeVoices(engine));
    final done = reader.play(
      _Source([
        [const SpeechSegment('One.'), const SpeechSegment('Two.')],
      ]),
    );
    await _settle();
    expect(engine.spoken, ['One.']);

    await reader.pause();
    await _settle();
    expect(reader.paused, isTrue);
    expect(reader.playing, isFalse);
    expect(engine.spoken, ['One.']);

    engine.gate = null;
    await reader.resume();
    await done;
    expect(engine.spoken, ['One.', 'One.', 'Two.']);
  });

  test('a pause in place carries on without repeating', () async {
    final gate = Completer<void>();
    final engine = _FakeEngine(canPause: true)..gate = gate;
    final reader = ReadAloud(voices: _FakeVoices(engine));
    final done = reader.play(
      _Source([
        [const SpeechSegment('One.'), const SpeechSegment('Two.')],
      ]),
    );
    await _settle();
    await reader.pause();
    gate.complete();
    await _settle();
    // Paused between sentences: the next one waits.
    expect(engine.spoken, ['One.']);
    await reader.resume();
    await done;
    expect(engine.spoken, ['One.', 'Two.']);
  });

  test('stop while paused ends reading', () async {
    final engine = _FakeEngine()..gate = Completer<void>();
    final reader = ReadAloud(voices: _FakeVoices(engine));
    final source = _Source([
      [const SpeechSegment('One.'), const SpeechSegment('Two.')],
    ]);
    final done = reader.play(source);
    await _settle();
    await reader.pause();
    await reader.stop();
    await done;
    expect(engine.spoken, ['One.']);
    expect(source.stopped, isTrue);
    expect(reader.active, isFalse);
  });
}
