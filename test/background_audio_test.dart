import 'package:audio_service/audio_service.dart';
import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/reader/car/car_library.dart';
import 'package:ebook_reader/reader/car/car_player.dart';
import 'package:ebook_reader/reader/read_aloud.dart';
import 'package:ebook_reader/reader/tts/background_audio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCar implements CarSource {
  _FakeCar(this.lib);

  CarLibrary? lib;
  final played = <String>[];
  CarError? failure;

  @override
  Future<CarLibrary?> library() async => lib;

  @override
  Future<void> play(String driveFileId) async {
    if (failure case final e?) throw e;
    played.add(driveFileId);
  }
}

CarLibrary _library() {
  Book book(String id, BookFormat format) => Book(
    driveFileId: id,
    fileName: '$id.${format.extensions.first.substring(1)}',
    format: format,
    folderPath: '',
  );
  final books = [
    book('dune', BookFormat.epub),
    book('emma', BookFormat.epub),
    book('comic', BookFormat.cbz),
  ];
  const titles = {'dune': 'Dune', 'emma': 'Emma', 'comic': 'Comic'};
  return CarLibrary(
    books: books,
    titleOf: (b) => titles[b.driveFileId]!,
    authorOf: (_) => '',
    coverOf: (_) => null,
    collectionsOf: (b) => b.driveFileId == 'emma' ? ['Classics'] : const [],
    openedAt: (b) => b.driveFileId == 'emma' ? null : DateTime(2026, 10, 30),
    fractionOf: (b) => b.driveFileId == 'dune' ? 0.5 : null,
    isOffline: (_) => true,
  );
}

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
    expect(items.single.id, 'book:drive-1');
    expect(items.single.title, 'Dune');
    expect(items.single.displaySubtitle, 'Frank Herbert · One');
    expect(items.single.playable, isTrue);
    expect((await handler.getMediaItem('book:drive-1'))?.title, 'Dune');

    handler.setChapter(reader, 'Two');
    expect(handler.mediaItem.value?.album, 'Two');
  });

  test('play from the car starts reading the open book', () async {
    handler.open(reader, book());
    await handler.playFromMediaId('book:drive-1');
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
    await handler.playFromMediaId('book:another-book');
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

  test('the car browses the library in tabs', () async {
    handler.car = _FakeCar(_library());
    final tabs = await handler.getChildren(AudioService.browsableRootId);
    expect(
      [for (final t in tabs) t.id],
      [carContinueId, carDownloadedId, carCollectionsId],
    );
    expect(tabs.every((t) => t.playable == false), isTrue);

    final continuing = await handler.getChildren(carContinueId);
    // Comics can't be read aloud, so the car doesn't offer them.
    expect([for (final b in continuing) b.id], ['book:dune']);
    expect(continuing.single.displaySubtitle, '50%');
    expect(
      continuing
          .single
          .extras?['androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE'],
      0.5,
    );
    final downloaded = await handler.getChildren(carDownloadedId);
    expect([for (final b in downloaded) b.title], ['Dune', 'Emma']);
    final shelves = await handler.getChildren(carCollectionsId);
    expect(shelves.single.title, 'Classics');
    final classics = await handler.getChildren(shelves.single.id);
    expect(classics.single.id, 'book:emma');
    expect((await handler.getMediaItem('book:emma'))?.title, 'Emma');
    expect([for (final b in await handler.search('emma')) b.id], ['book:emma']);
  });

  test('plays a book picked in the car, or found by voice', () async {
    final car = _FakeCar(_library());
    handler.car = car;
    await handler.playFromMediaId('book:emma');
    await handler.playFromSearch('dune');
    // "Play My E-Reader" with nothing open carries on with the last book.
    await handler.playFromSearch('');
    expect(car.played, ['emma', 'dune', 'dune']);

    await handler.playFromSearch('tolkien');
    expect(handler.playbackState.value.errorMessage, contains('tolkien'));
  });

  test('shows why a book from the car could not play', () async {
    final car = _FakeCar(_library())..failure = const CarError('No signal');
    handler.car = car;
    await handler.playFromMediaId('book:dune');
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.error,
    );
    expect(handler.playbackState.value.errorMessage, 'No signal');
  });

  test('signed out, the car asks to sign in on the phone', () async {
    handler.car = _FakeCar(null);
    expect(await handler.getChildren(AudioService.browsableRootId), isEmpty);
    await handler.play();
    expect(handler.playbackState.value.errorMessage, contains('Sign in'));
  });

  test('a book opened on screen takes over when nothing is read', () async {
    var released = 0;
    handler.open(
      reader,
      NowReading(id: 'car', title: 'Car book', released: () => released++),
    );
    // Not reading yet, so an offer takes over.
    final screen = ReadAloud();
    handler.open(screen, book(), offer: true);
    expect(handler.mediaItem.value?.id, 'book:drive-1');
    expect(released, 1);
  });
}
