import 'package:ebook_reader/reader/read_aloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

class _FakeTts extends Fake implements FlutterTts {
  final spoken = <String>[];
  double? rate;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => this.rate = rate;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async =>
      spoken.add(text);

  @override
  Future<dynamic> stop() async => 1;
}

class _Source implements SpeechSource {
  _Source(this.blocks);

  final List<List<SpeechSegment>> blocks;
  final marks = <String?>[];
  int _i = 0;
  bool stopped = false;

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

void main() {
  test('splits page text into sentences', () {
    expect(
      sentencesOf('First line of a hyphen-\nated word. Second? "Third!" Tail')
          .map((s) => s.text),
      ['First line of a hyphenated word.', 'Second?', '"Third!"', 'Tail'],
    );
    expect(sentencesOf('  \n '), isEmpty);
  });

  test(
    'speaks every block in order, marks each sentence, then stops',
    () async {
      final tts = _FakeTts();
      final reader = ReadAloud(tts: tts);
      final source = _Source([
        [const SpeechSegment('One.', 'a'), const SpeechSegment('Two.', 'b')],
        [const SpeechSegment(' ', 'skip'), const SpeechSegment('Three.', 'c')],
      ]);
      await reader.setSpeed(1.5);
      await reader.play(source);

      expect(tts.spoken, ['One.', 'Two.', 'Three.']);
      expect(source.marks, ['a', 'b', 'c']);
      expect(tts.rate, 0.75);
      expect(source.stopped, isTrue);
      expect(reader.active, isFalse);
    },
  );
}
