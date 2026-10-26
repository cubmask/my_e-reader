import 'dart:convert';
import 'dart:io';

import 'package:ebook_reader/reader/tts/cloud_voices.dart';
import 'package:ebook_reader/reader/tts/speech_engine.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Engine implements SpeechEngine {
  _Engine(this.name, {this.fails = false});

  final String name;
  final bool fails;
  final spoken = <String>[];
  String? language;
  double? speed;
  bool stopped = false;

  @override
  Future<void> speak(String text) async {
    if (fails) throw const CloudVoiceException('No connection');
    spoken.add(text);
  }

  @override
  void prepare(String text) {}
  @override
  Future<bool> pause() async => true;
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
  @override
  Future<void> setLanguage(String language) async => this.language = language;
}

void main() {
  group('ElevenLabs', () {
    test('speaks with the key, model, language and a clamped speed', () async {
      late http.Request sent;
      final client = CloudTtsClient(
        MockClient((request) async {
          sent = request;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );
      final audio = await client.speak(
        CloudProvider.elevenLabs,
        'el-key',
        text: 'Hallo.',
        model: 'eleven_v4',
        voice: 'voice123',
        language: 'de',
        speed: 2.0,
      );
      expect(audio, [1, 2, 3]);
      expect(sent.method, 'POST');
      expect(
        sent.url.toString(),
        'https://api.elevenlabs.io/v1/text-to-speech/voice123'
        '?output_format=mp3_44100_128',
      );
      expect(sent.headers['xi-api-key'], 'el-key');
      expect(jsonDecode(sent.body), {
        'text': 'Hallo.',
        'model_id': 'eleven_v4',
        'language_code': 'de',
        'voice_settings': {'speed': 1.2},
      });
    });

    test('leaves the language to Multilingual v2', () async {
      late http.Request sent;
      final client = CloudTtsClient(
        MockClient((request) async {
          sent = request;
          return http.Response.bytes([1], 200);
        }),
      );
      await client.speak(
        CloudProvider.elevenLabs,
        'k',
        text: 'Hi.',
        model: 'eleven_multilingual_v2',
        voice: 'v',
        language: 'en',
        speed: 1.0,
      );
      expect(jsonDecode(sent.body), isNot(contains('language_code')));
    });

    test('lists voices with their labels', () async {
      final client = CloudTtsClient(
        MockClient((request) async {
          expect(request.url.path, '/v2/voices');
          expect(request.url.queryParameters['search'], 'calm');
          return http.Response(
            jsonEncode({
              'voices': [
                {
                  'voice_id': 'a1',
                  'name': 'Rachel',
                  'category': 'premade',
                  'labels': {'accent': 'american', 'gender': 'female'},
                },
                {'name': 'no id'},
              ],
            }),
            200,
          );
        }),
      );
      final voices = await client.voices(
        CloudProvider.elevenLabs,
        'k',
        search: 'calm',
      );
      expect(voices.map((v) => (v.id, v.name, v.details)), [
        ('a1', 'Rachel', 'american · female · premade'),
      ]);
    });
  });

  group('Fish Audio', () {
    test('speaks Drama 3 with the chosen voice', () async {
      late http.Request sent;
      final client = CloudTtsClient(
        MockClient((request) async {
          sent = request;
          return http.Response.bytes([9], 200);
        }),
      );
      await client.speak(
        CloudProvider.fishAudio,
        'fish-key',
        text: 'Bonjour.',
        model: 'drama-3',
        voice: 'ref1',
        language: 'fr',
        speed: 1.25,
      );
      expect(sent.url.toString(), 'https://api.fish.audio/v1/tts');
      expect(sent.headers['authorization'], 'Bearer fish-key');
      expect(sent.headers['model'], 'drama-3');
      expect(jsonDecode(sent.body), {
        'text': 'Bonjour.',
        'reference_id': 'ref1',
        'language': 'fr',
        'format': 'mp3',
        'prosody': {'speed': 1.25},
      });
    });

    test('lists the account\'s voices first, then the library', () async {
      final client = CloudTtsClient(
        MockClient((request) async {
          expect(request.url.path, '/model');
          final own = request.url.queryParameters['self'] == 'true';
          Map<String, Object> item(String id, String title) => {
            '_id': id,
            'title': title,
            'languages': ['en'],
            'author': {'nickname': 'kev'},
          };
          return http.Response(
            jsonEncode({
              'total': 2,
              'items': own
                  ? [item('mine', 'My voice')]
                  : [item('pop', 'Narrator'), item('mine', 'My voice')],
            }),
            200,
          );
        }),
      );
      final voices = await client.voices(CloudProvider.fishAudio, 'k');
      expect(voices.map((v) => v.id), ['mine', 'pop']);
      expect(voices.first.details, 'en · by kev');
    });
  });

  test('explains refusals and lost connections', () async {
    Future<String> failure(Future<http.Response> Function() respond) async {
      final client = CloudTtsClient(MockClient((_) => respond()));
      try {
        await client.speak(
          CloudProvider.fishAudio,
          'k',
          text: 'x',
          model: 'drama-3',
          voice: '',
          language: 'en',
          speed: 1,
        );
        return 'no error';
      } on CloudVoiceException catch (e) {
        return e.message;
      }
    }

    expect(
      await failure(() async => http.Response('', 401)),
      'The API key was refused',
    );
    expect(
      await failure(() async => http.Response('', 402)),
      'The account is out of credits',
    );
    expect(
      await failure(
        () async => http.Response(jsonEncode({'message': 'Bad text'}), 400),
      ),
      'The voice service failed (400: Bad text)',
    );
    expect(
      await failure(() => throw const SocketException('down')),
      'No connection',
    );
    expect(
      await failure(() async => http.Response.bytes([], 200)),
      'The voice service sent no audio',
    );
  });

  test('keys live in secure storage, choices in preferences', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final settings = CloudVoiceSettings();
    await settings.load();
    expect(settings.ready, isFalse);

    await settings.setProvider(CloudProvider.elevenLabs);
    await settings.setKey(CloudProvider.elevenLabs, '  secret  ');
    expect(settings.ready, isFalse, reason: 'ElevenLabs needs a voice');
    await settings.setVoice(
      CloudProvider.elevenLabs,
      const CloudVoice('a1', 'Rachel'),
    );
    await settings.setModel(CloudProvider.elevenLabs, 'eleven_flash_v2_5');
    expect(settings.ready, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().map(prefs.get).join(), isNot(contains('secret')));
    expect(
      await const FlutterSecureStorage().read(
        key: 'voices.cloud.elevenLabs.apiKey',
      ),
      'secret',
    );

    final again = CloudVoiceSettings();
    await again.load();
    expect(again.provider, CloudProvider.elevenLabs);
    expect(again.keyFor(CloudProvider.elevenLabs), 'secret');
    expect(again.voiceFor(CloudProvider.elevenLabs)?.name, 'Rachel');
    expect(again.modelFor(CloudProvider.elevenLabs), 'eleven_flash_v2_5');
    expect(again.modelFor(CloudProvider.fishAudio), 'drama-3');

    // Fish Audio has a default voice, so a key is enough.
    await again.setProvider(CloudProvider.fishAudio);
    expect(again.ready, isFalse);
    await again.setKey(CloudProvider.fishAudio, 'f');
    expect(again.ready, isTrue);
    await again.setKey(CloudProvider.fishAudio, '');
    expect(again.ready, isFalse);
  });

  test('a failing voice hands the same sentence to the fallback', () async {
    final online = _Engine('online', fails: true);
    final offline = _Engine('offline');
    Object? reported;
    final engine = FallbackSpeechEngine(
      online,
      () async => offline,
      onFallback: (e) => reported = e,
    );
    await engine.setLanguage('de');
    await engine.setSpeed(1.5);
    await engine.speak('Eins.');
    await engine.speak('Zwei.');

    expect(offline.spoken, ['Eins.', 'Zwei.']);
    expect(offline.language, 'de');
    expect(offline.speed, 1.5);
    expect(online.stopped, isTrue);
    expect('$reported', 'No connection');
  });
}
