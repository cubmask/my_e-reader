import 'package:audio_service/audio_service.dart';
import 'package:ebook_reader/reader/read_aloud.dart';
import 'package:ebook_reader/reader/tts/background_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CarAudioHandler handler;
  late ReadAloud reader;
  var starts = 0;
  var skips = <int>[];

  NowReading book({String chapter = 'One'}) => NowReading(
    id: 'drive-1',
    title: 'Dune',
    author: 'Frank Herbert',
    chapter: chapter,
    start: () async => starts++,
    nextChapter: () async => skips.add(1),
    previousChapter: () async => skips.add(-1),
  );

  setUp(() {
    handler = CarAudioHandler();
    reader = ReadAloud();
    starts = 0;
    skips = [];
  });

  test('offers the open book to the car', () async {
    expect(await handler.getChildren(AudioService.browsableRootId), isEmpty);
    handler.open(reader, book());
    final items = await handler.getChildren(AudioService.browsableRootId);
    expect(items.single.id, 'drive-1');
    expect(items.single.title, 'Dune');
    expect(items.single.displaySubtitle, 'Frank Herbert · One');
    expect(items.single.playable, isTrue);
    expect((await handler.getMediaItem('drive-1'))?.title, 'Dune');

    handler.setChapter(reader, 'Two');
    expect(handler.mediaItem.value?.album, 'Two');
  });

  test('play from the car starts reading the open book', () async {
    handler.open(reader, book());
    await handler.playFromMediaId('drive-1');
    expect(starts, 1);
    await handler.skipToNext();
    await handler.skipToPrevious();
    expect(skips, [1, -1]);
  });

  test('asks for the phone when no book is open', () async {
    await handler.play();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.error,
    );
    expect(handler.playbackState.value.errorMessage, contains('phone'));

    handler.open(reader, book());
    await handler.playFromMediaId('another-book');
    expect(starts, 0);
    expect(handler.playbackState.value.errorMessage, contains('phone'));
  });

  test('the speed button steps through the speeds', () async {
    handler.open(reader, book());
    await handler.customAction('speed');
    expect(reader.speed, 1.25);
    await reader.setSpeed(2.0);
    await handler.customAction('speed');
    expect(reader.speed, 0.75);
  });

  test('the sleep button steps through the timers, then off', () async {
    handler.open(reader, book());
    await handler.customAction('sleep');
    expect(reader.sleepAt, isNotNull);
    await handler.customAction('sleep');
    await handler.customAction('sleep');
    await handler.customAction('sleep');
    expect(reader.sleepAtChapterEnd, isTrue);
    await handler.customAction('sleep');
    expect(reader.sleepAt, isNull);
    expect(reader.sleepAtChapterEnd, isFalse);
    reader.dispose();
  });

  test('forgets the book when the reader closes', () async {
    handler.open(reader, book());
    handler.detach(reader);
    expect(await handler.getChildren(AudioService.browsableRootId), isEmpty);
    expect(handler.mediaItem.value, isNull);
  });
}
