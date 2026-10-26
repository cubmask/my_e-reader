import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'speech_engine.dart';

/// A model a provider offers, by its API id.
typedef CloudModel = ({String id, String name});

/// Online text-to-speech services, used with the reader's own API key.
enum CloudProvider {
  elevenLabs('ElevenLabs', 'https://elevenlabs.io/app/settings/api-keys', [
    (id: 'eleven_v4', name: 'Eleven v4 (best for audiobooks)'),
    (id: 'eleven_multilingual_v2', name: 'Multilingual v2 (steadiest)'),
    (id: 'eleven_flash_v2_5', name: 'Flash v2.5 (fast, cheaper)'),
  ]),
  fishAudio('Fish Audio', 'https://fish.audio/app/api-keys/', [
    (id: 'drama-3', name: 'Drama 3 (most expressive)'),
    (id: 's2.1-pro', name: 'S2.1 Pro'),
  ]);

  const CloudProvider(this.label, this.keysUrl, this.models);

  final String label;

  /// Where the reader creates an API key.
  final String keysUrl;
  final List<CloudModel> models;
}

/// A voice offered by a provider.
class CloudVoice {
  const CloudVoice(this.id, this.name, {this.details = ''});

  final String id;
  final String name;

  /// Accent, gender, languages or author, when known.
  final String details;
}

/// A request the provider refused or that couldn't reach it.
class CloudVoiceException implements Exception {
  const CloudVoiceException(this.message, {this.status});

  final String message;

  /// The HTTP status, when the service answered.
  final int? status;

  @override
  String toString() => message;
}

/// Talks to ElevenLabs and Fish Audio.
class CloudTtsClient {
  CloudTtsClient(this._http, {this.timeout = const Duration(seconds: 20)});

  final http.Client _http;
  final Duration timeout;

  static final _eleven = Uri.parse('https://api.elevenlabs.io');
  static final _fish = Uri.parse('https://api.fish.audio');

  Map<String, String> _auth(CloudProvider provider, String key) =>
      switch (provider) {
        CloudProvider.elevenLabs => {'xi-api-key': key},
        CloudProvider.fishAudio => {'Authorization': 'Bearer $key'},
      };

  Future<http.Response> _send(Future<http.Response> request) async {
    final http.Response response;
    try {
      response = await request.timeout(timeout);
    } on TimeoutException {
      throw const CloudVoiceException('The voice service took too long');
    } on SocketException {
      throw const CloudVoiceException('No connection');
    } on http.ClientException catch (e) {
      throw CloudVoiceException('No connection (${e.message})');
    }
    if (response.statusCode == 200) return response;
    throw CloudVoiceException(switch (response.statusCode) {
      401 || 403 => 'The API key was refused',
      402 => 'The account is out of credits',
      429 => 'Too many requests; try again shortly',
      final code => 'The voice service failed ($code${_reason(response)})',
    }, status: response.statusCode);
  }

  static String _reason(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body is Map ? (body['detail'] ?? body['message']) : null;
      final message = detail is Map ? detail['message'] : detail;
      return message is String && message.isNotEmpty ? ': $message' : '';
    } catch (_) {
      return '';
    }
  }

  /// The voices the key can use: the account's own first, then the
  /// provider's library, optionally filtered by [search].
  Future<List<CloudVoice>> voices(
    CloudProvider provider,
    String key, {
    String search = '',
  }) async {
    switch (provider) {
      case CloudProvider.elevenLabs:
        final response = await _send(
          _http.get(
            _eleven.replace(
              path: '/v2/voices',
              queryParameters: {
                'page_size': '100',
                'include_total_count': 'false',
                if (search.isNotEmpty) 'search': search,
              },
            ),
            headers: _auth(provider, key),
          ),
        );
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
        return [
          for (final v in body['voices'] as List? ?? const [])
            if (v is Map && v['voice_id'] is String)
              CloudVoice(
                v['voice_id'] as String,
                '${v['name'] ?? v['voice_id']}',
                details: [
                  ...((v['labels'] as Map?)?.values ?? const []),
                  if (v['category'] case final String c) c,
                ].where((s) => '$s'.isNotEmpty).join(' · '),
              ),
        ];
      case CloudProvider.fishAudio:
        Future<List<CloudVoice>> page(Map<String, String> query) async {
          final response = await _send(
            _http.get(
              _fish.replace(path: '/model', queryParameters: query),
              headers: _auth(provider, key),
            ),
          );
          final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
          return [
            for (final v in body['items'] as List? ?? const [])
              if (v is Map && v['_id'] is String)
                CloudVoice(
                  v['_id'] as String,
                  '${v['title'] ?? v['_id']}',
                  details: [
                    ...(v['languages'] as List? ?? const []),
                    if ((v['author'] as Map?)?['nickname'] case final String n)
                      'by $n',
                  ].join(' · '),
                ),
          ];
        }
        final title = {if (search.isNotEmpty) 'title': search};
        final (own, library) = await (
          page({'self': 'true', 'page_size': '100', ...title}),
          page({'page_size': '50', 'sort_by': 'score', ...title}),
        ).wait;
        final ids = {for (final v in own) v.id};
        return [...own, ...library.where((v) => !ids.contains(v.id))];
    }
  }

  /// ElevenLabs models that refused the surrounding sentences, which are
  /// then left out.
  static final _noContext = <String>{};

  /// Context sent with a sentence: enough to set the tone, no more.
  static const _contextChars = 500;

  /// [text] spoken as MP3. ElevenLabs also gets [context], so the
  /// intonation flows from one sentence into the next.
  Future<Uint8List> speak(
    CloudProvider provider,
    String key, {
    required String text,
    required String model,
    required String voice,
    required String language,
    required double speed,
    SpeechContext? context,
  }) async {
    Future<http.Response> eleven({required bool withContext}) {
      final previous = withContext ? context?.previous : null;
      final next = withContext ? context?.next : null;
      return _send(
        _http.post(
          _eleven.replace(
            path: '/v1/text-to-speech/$voice',
            queryParameters: {'output_format': 'mp3_44100_128'},
          ),
          headers: {
            ..._auth(provider, key),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'text': text,
            'model_id': model,
            // Multilingual v2 detects the language and rejects the code.
            if (model != 'eleven_multilingual_v2') 'language_code': language,
            // ElevenLabs accepts 0.7x to 1.2x.
            'voice_settings': {'speed': speed.clamp(0.7, 1.2)},
            if (previous != null && previous.isNotEmpty)
              'previous_text': previous.length > _contextChars
                  ? previous.substring(previous.length - _contextChars)
                  : previous,
            if (next != null && next.isNotEmpty)
              'next_text': next.length > _contextChars
                  ? next.substring(0, _contextChars)
                  : next,
          }),
        ),
      );
    }

    Future<http.Response> elevenWithContext() async {
      final hasContext = context?.previous != null || context?.next != null;
      if (!hasContext || _noContext.contains(model)) {
        return eleven(withContext: false);
      }
      try {
        return await eleven(withContext: true);
      } on CloudVoiceException catch (e) {
        if (e.status != 400 && e.status != 422) rethrow;
        // A model without request stitching: try once more without.
        final response = await eleven(withContext: false);
        _noContext.add(model);
        return response;
      }
    }

    final response = switch (provider) {
      CloudProvider.elevenLabs => await elevenWithContext(),
      CloudProvider.fishAudio => await _send(
        _http.post(
          _fish.replace(path: '/v1/tts'),
          headers: {
            ..._auth(provider, key),
            'Content-Type': 'application/json',
            'model': model,
          },
          body: jsonEncode({
            'text': text,
            if (voice.isNotEmpty) 'reference_id': voice,
            'language': language,
            'format': 'mp3',
            'prosody': {'speed': speed.clamp(0.5, 2.0)},
          }),
        ),
      ),
    };
    if (response.bodyBytes.isEmpty) {
      throw const CloudVoiceException('The voice service sent no audio');
    }
    return response.bodyBytes;
  }
}

/// Renders sentences with an online voice into MP3 files, reusing audio
/// already paid for when a passage is read again.
class CloudSynthesizer implements Synthesizer {
  CloudSynthesizer(
    this._client,
    this.provider,
    this._key, {
    required this.model,
    required this.voice,
    required Directory outDir,
    this.cache,
  }) : _out = outDir;

  final CloudTtsClient _client;
  final CloudProvider provider;
  final String _key;
  final String model;
  final String voice;
  final Directory _out;
  final AudioCache? cache;
  int _next = 0;

  @override
  Future<String> synthesize(
    String text, {
    required String language,
    required int speaker,
    required double speed,
    SpeechContext? context,
  }) async {
    await _out.create(recursive: true);
    final file = File(
      p.join(
        _out.path,
        '${provider.name}-${identityHashCode(this)}-'
        '${_next++}.mp3',
      ),
    );
    final cacheKey = AudioCache.keyOf([
      provider.name,
      model,
      voice,
      language,
      speed,
      text,
    ]);
    // The engine deletes what it played, so it gets a copy.
    if (await cache?.lookup(cacheKey) case final cached?) {
      return (await cached.copy(file.path)).path;
    }
    final audio = await _client.speak(
      provider,
      _key,
      text: text,
      model: model,
      voice: voice,
      language: language,
      speed: speed,
      context: context,
    );
    await file.writeAsBytes(audio);
    await cache?.store(cacheKey, audio);
    return file.path;
  }
}

/// Online audio kept on disk, oldest-used dropped first past [maxBytes].
class AudioCache {
  AudioCache(this.dir, {this.maxBytes = 300 * 1000 * 1000});

  final Directory dir;
  final int maxBytes;
  int _writes = 0;

  static String keyOf(List<Object> parts) =>
      sha1.convert(utf8.encode(parts.join('\u0000'))).toString();

  File _file(String key) => File(p.join(dir.path, '$key.mp3'));

  Future<File?> lookup(String key) async {
    final file = _file(key);
    try {
      if (!await file.exists()) return null;
      await file.setLastModified(DateTime.now());
      return file;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> store(String key, List<int> audio) async {
    try {
      await dir.create(recursive: true);
      final file = _file(key);
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(audio, flush: true);
      await partial.rename(file.path);
      if (++_writes % 20 == 1) await prune();
    } on FileSystemException catch (e) {
      debugPrint('Could not cache audio: $e');
    }
  }

  Future<List<(File, FileStat)>> _entries() async {
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list())
        if (e is File && e.path.endsWith('.mp3')) (e, await e.stat()),
    ];
  }

  Future<int> size() async =>
      (await _entries()).fold<int>(0, (sum, e) => sum + e.$2.size);

  /// Drops the least recently played audio down to 80% of [maxBytes].
  Future<void> prune() async {
    final entries = await _entries();
    var total = entries.fold<int>(0, (sum, e) => sum + e.$2.size);
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in entries) {
      if (total <= maxBytes * 0.8) break;
      await file.delete().catchError((_) => file);
      total -= stat.size;
    }
  }

  Future<void> clear() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// Which online voice to use, if any. API keys are kept in the platform's
/// secure storage (Android Keystore, Keychain, Windows Credential Manager),
/// never in plain preferences.
class CloudVoiceSettings extends ChangeNotifier {
  CloudVoiceSettings({FlutterSecureStorage? secrets})
    : _secrets =
          secrets ??
          FlutterSecureStorage(
            // The Keychain without App Groups needs no provisioning.
            mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _providerKey = 'voices.cloud.provider';

  final FlutterSecureStorage _secrets;
  CloudProvider? _provider;
  final _keys = <CloudProvider, String>{};
  final _models = <CloudProvider, String>{};
  final _voices = <CloudProvider, CloudVoice>{};

  /// The provider to read with when online, or null for offline voices only.
  CloudProvider? get provider => _provider;

  bool hasKey(CloudProvider provider) => _keys[provider]?.isNotEmpty ?? false;
  String? keyFor(CloudProvider provider) => _keys[provider];
  String modelFor(CloudProvider provider) =>
      _models[provider] ?? provider.models.first.id;
  CloudVoice? voiceFor(CloudProvider provider) => _voices[provider];

  /// Whether the chosen provider has what it needs to speak.
  bool get ready {
    final provider = _provider;
    if (provider == null || !hasKey(provider)) return false;
    // Fish Audio has a default voice; ElevenLabs needs one picked.
    return provider == CloudProvider.fishAudio || voiceFor(provider) != null;
  }

  static String _secret(CloudProvider p) => 'voices.cloud.${p.name}.apiKey';
  static String _model(CloudProvider p) => 'voices.cloud.${p.name}.model';
  static String _voiceId(CloudProvider p) => 'voices.cloud.${p.name}.voice';
  static String _voiceName(CloudProvider p) =>
      'voices.cloud.${p.name}.voiceName';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _provider = CloudProvider.values.asNameMap()[prefs.getString(_providerKey)];
    for (final p in CloudProvider.values) {
      if (prefs.getString(_model(p)) case final model?
          when p.models.any((m) => m.id == model)) {
        _models[p] = model;
      }
      if (prefs.getString(_voiceId(p)) case final id?) {
        _voices[p] = CloudVoice(id, prefs.getString(_voiceName(p)) ?? id);
      }
      try {
        if (await _secrets.read(key: _secret(p)) case final key?) {
          _keys[p] = key;
        }
      } catch (e) {
        debugPrint('Could not read the ${p.label} key: $e');
      }
    }
    notifyListeners();
  }

  Future<void> setProvider(CloudProvider? provider) async {
    _provider = provider;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (provider == null) {
      await prefs.remove(_providerKey);
    } else {
      await prefs.setString(_providerKey, provider.name);
    }
  }

  /// Saves [key], or forgets it when empty.
  Future<void> setKey(CloudProvider provider, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      _keys.remove(provider);
      await _secrets.delete(key: _secret(provider));
    } else {
      _keys[provider] = trimmed;
      await _secrets.write(key: _secret(provider), value: trimmed);
    }
    notifyListeners();
  }

  Future<void> setModel(CloudProvider provider, String model) async {
    _models[provider] = model;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _model(provider),
      model,
    );
  }

  Future<void> setVoice(CloudProvider provider, CloudVoice? voice) async {
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      _voices.remove(provider);
      await prefs.remove(_voiceId(provider));
      await prefs.remove(_voiceName(provider));
    } else {
      _voices[provider] = voice;
      await prefs.setString(_voiceId(provider), voice.id);
      await prefs.setString(_voiceName(provider), voice.name);
    }
    notifyListeners();
  }
}
