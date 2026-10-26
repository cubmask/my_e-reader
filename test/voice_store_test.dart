import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:ebook_reader/reader/tts/speech_engine.dart';
import 'package:ebook_reader/reader/tts/voice_pack.dart';
import 'package:ebook_reader/reader/tts/voice_store.dart';
import 'package:ebook_reader/ui/voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoSynth implements Synthesizer {
  @override
  Future<String> synthesize(
    String text, {
    required String language,
    required int speaker,
    required double speed,
  }) => throw UnimplementedError();
}

class _NoOut implements AudioOut {
  @override
  Future<void> play(String path) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
}

class _System implements SpeechEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _pack = VoicePack(
  id: 'test-voice',
  name: 'Test voice',
  url: 'https://example.com/test-voice.tar.bz2',
  downloadBytes: 100,
  languages: {'en': 'English', 'de': 'German'},
  speakers: ['A', 'B'],
);

/// A model archive shaped like sherpa-onnx's: one folder of files.
List<int> _modelArchive() {
  final archive = Archive()
    ..add(ArchiveFile.bytes('model-2026/tts.json', utf8.encode('{}')))
    ..add(ArchiveFile.bytes('model-2026/voice.bin', [1, 2, 3]));
  return BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
}

void main() {
  late Directory dir;
  late _System system;
  var synthStarts = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('voices');
    system = _System();
    synthStarts = 0;
  });
  tearDown(() => dir.delete(recursive: true));

  VoiceStore store(http.Client client) => VoiceStore(
    dir,
    pack: _pack,
    client: client,
    synthesizer: (_) async {
      synthStarts++;
      return _NoSynth();
    },
    audioOut: _NoOut.new,
    system: system,
    deviceLanguage: () => 'de_DE',
  );

  test('downloads and unpacks the voice, then reads with it', () async {
    final bytes = _modelArchive();
    final voices = store(
      MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream.fromIterable([bytes]),
          200,
          contentLength: bytes.length,
        ),
      ),
    );
    await voices.load();
    expect(voices.status, VoiceStatus.notInstalled);
    expect(await voices.engineFor('en'), same(system));

    final progress = <double?>[];
    voices.addListener(() => progress.add(voices.progress));
    await voices.download();

    expect(voices.error, isNull);
    expect(voices.status, VoiceStatus.installed);
    expect(progress, contains(1.0));
    expect(File('${voices.modelDir.path}/voice.bin').readAsBytesSync(), [
      1,
      2,
      3,
    ]);
    expect(dir.listSync().map((e) => e.path.split('/').last), ['test-voice']);

    final engine = await voices.engineFor('en');
    expect(engine, isA<NeuralSpeechEngine>());
    expect(await voices.engineFor('de'), same(engine));
    expect(synthStarts, 1);
    // Languages the voice doesn't speak, or turning it off, use the system.
    expect(await voices.engineFor('zh'), same(system));
    await voices.setUseNeural(false);
    expect(await voices.engineFor('en'), same(system));

    // Still installed after a restart.
    final again = store(MockClient((_) async => http.Response('', 404)));
    await again.load();
    expect(again.installed, isTrue);
    expect(again.useNeural, isFalse);

    await voices.remove();
    expect(voices.status, VoiceStatus.notInstalled);
    expect(voices.modelDir.existsSync(), isFalse);
  });

  test('a failed download leaves nothing behind', () async {
    final voices = store(MockClient((_) async => http.Response('nope', 503)));
    await voices.load();
    await voices.download();
    expect(voices.status, VoiceStatus.notInstalled);
    expect(voices.error, contains('503'));
    expect(dir.listSync(), isEmpty);
  });

  test('picks the language from the book, the device or the setting', () async {
    final voices = store(MockClient((_) async => http.Response('', 404)));
    await voices.load();
    expect(voices.languageFor('Hello', 'en-US'), 'en');
    expect(voices.languageFor('Hello', null), 'de');
    expect(voices.languageFor('Привет', 'en'), 'ru');
    await voices.setLanguage('fr');
    expect(voices.languageFor('Привет', 'en'), 'fr');

    final again = store(MockClient((_) async => http.Response('', 404)));
    await again.load();
    expect(again.language, 'fr');
    await again.setLanguage(null);
    expect(again.language, isNull);
  });

  testWidgets('settings offer the download, then the voices', (tester) async {
    final bytes = _modelArchive();
    late VoiceStore voices;
    await tester.runAsync(() async {
      voices = store(
        MockClient.streaming(
          (request, _) async =>
              http.StreamedResponse(Stream.fromIterable([bytes]), 200),
        ),
      );
      await voices.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: VoiceSettings(voices: voices)),
        ),
      ),
    );
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Voice'), findsNothing);

    await tester.runAsync(voices.download);
    await tester.pump();
    expect(find.text('Download'), findsNothing);
    expect(find.text('Read with Test voice'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
  });
}
