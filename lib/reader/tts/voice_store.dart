import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../read_aloud.dart';
import 'sherpa_synthesizer.dart';
import 'speech_engine.dart';
import 'voice_pack.dart';

enum VoiceStatus { notInstalled, downloading, installing, installed }

typedef SynthesizerFactory = Future<Synthesizer> Function(Directory modelDir);

/// Downloads, removes and picks the offline neural voice, falling back to
/// the system voices for languages it doesn't speak or when it isn't
/// installed. The model lives outside the app, so the app stays small.
class VoiceStore extends ChangeNotifier implements Voices {
  VoiceStore(
    this.root, {
    this.pack = supertonic3,
    http.Client? client,
    SynthesizerFactory? synthesizer,
    AudioOut Function()? audioOut,
    SpeechEngine? system,
    String Function()? deviceLanguage,
  }) : _client = client ?? http.Client(),
       _startSynthesizer = synthesizer,
       _audioOut = audioOut ?? PlayerAudioOut.new,
       _systemOverride = system,
       _deviceLanguage =
           deviceLanguage ??
           (() => PlatformDispatcher.instance.locale.languageCode);

  static const _useKey = 'voices.useNeural';
  static const _speakerKey = 'voices.speaker';
  static const _languageKey = 'voices.language';
  static const _marker = '.installed';

  final Directory root;
  final VoicePack pack;
  final http.Client _client;
  final SynthesizerFactory? _startSynthesizer;
  final AudioOut Function() _audioOut;
  final SpeechEngine? _systemOverride;
  late final SpeechEngine _system = _systemOverride ?? SystemSpeechEngine();
  final String Function() _deviceLanguage;

  VoiceStatus _status = VoiceStatus.notInstalled;
  double? _progress;
  String? _error;
  bool _useNeural = true;
  int _speaker = 0;
  String? _language;
  bool _cancelled = false;
  NeuralSpeechEngine? _neural;
  Future<NeuralSpeechEngine>? _loading;
  Synthesizer? _synth;

  Directory get modelDir => Directory(p.join(root.path, pack.id));
  VoiceStatus get status => _status;
  bool get installed => _status == VoiceStatus.installed;

  /// Download progress from 0 to 1, or null while unknown.
  double? get progress => _progress;

  /// Why the last download failed.
  String? get error => _error;

  /// Whether to read with the downloaded voice when it speaks the language.
  bool get useNeural => _useNeural;
  int get speaker => _speaker;

  /// A language to always read in, or null to follow each book.
  String? get language => _language;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useNeural = prefs.getBool(_useKey) ?? true;
    _speaker = (prefs.getInt(_speakerKey) ?? 0).clamp(
      0,
      pack.speakers.length - 1,
    );
    _language = prefs.getString(_languageKey);
    if (await File(p.join(modelDir.path, _marker)).exists()) {
      _status = VoiceStatus.installed;
    }
    notifyListeners();
  }

  Future<void> setUseNeural(bool value) async {
    _useNeural = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_useKey, value);
  }

  Future<void> setSpeaker(int speaker) async {
    _speaker = speaker;
    _neural?.speaker = speaker;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_speakerKey, speaker);
  }

  Future<void> setLanguage(String? language) async {
    _language = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (language == null) {
      await prefs.remove(_languageKey);
    } else {
      await prefs.setString(_languageKey, language);
    }
  }

  // Choosing a voice

  @override
  String languageFor(String sample, String? declared) =>
      _language ??
      resolveLanguage(
        sample,
        book: declared,
        fallback: baseLanguage(_deviceLanguage()) ?? 'en',
      );

  /// Whether reading [language] uses the downloaded voice.
  bool usesNeuralFor(String language) =>
      installed && _useNeural && pack.speaks(language);

  @override
  Future<SpeechEngine> engineFor(String language) async {
    if (!usesNeuralFor(language)) return _system;
    try {
      return await (_loading ??= _loadNeural());
    } catch (e) {
      _loading = null;
      debugPrint('Neural voice failed to load, using the system voice: $e');
      return _system;
    }
  }

  Future<NeuralSpeechEngine> _loadNeural() async {
    final synth = _synth = await (_startSynthesizer ?? _sherpa)(modelDir);
    return _neural = NeuralSpeechEngine(synth, _audioOut(), speaker: _speaker);
  }

  static Future<Synthesizer> _sherpa(Directory modelDir) async =>
      SherpaSynthesizer.start(
        modelDir,
        Directory(p.join(Directory.systemTemp.path, 'tts')),
      );

  void _unloadNeural() {
    unawaited(_neural?.stop());
    if (_synth case final SherpaSynthesizer synth) synth.dispose();
    _neural = null;
    _synth = null;
    _loading = null;
  }

  // Download and removal

  Future<void> download() async {
    if (_status == VoiceStatus.downloading ||
        _status == VoiceStatus.installing) {
      return;
    }
    _cancelled = false;
    _error = null;
    _progress = 0;
    _status = VoiceStatus.downloading;
    notifyListeners();
    final archive = File(p.join(root.path, '${pack.id}.tar.bz2'));
    final partial = Directory(p.join(root.path, '${pack.id}.partial'));
    try {
      await root.create(recursive: true);
      final response = await _client.send(
        http.Request('GET', Uri.parse(pack.url)),
      );
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }
      final total = response.contentLength ?? pack.downloadBytes;
      final sink = archive.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (_cancelled) throw const _Cancelled();
          sink.add(chunk);
          received += chunk.length;
          _progress = (received / total).clamp(0, 1);
          notifyListeners();
        }
      } finally {
        await sink.close();
      }
      _status = VoiceStatus.installing;
      _progress = null;
      notifyListeners();
      if (await partial.exists()) await partial.delete(recursive: true);
      final archivePath = archive.path, partialPath = partial.path;
      await Isolate.run(() => extractFileToDisk(archivePath, partialPath));
      // The archive holds a single folder with the model files.
      final folders = await partial
          .list()
          .where((e) => e is Directory)
          .toList();
      final source = folders.length == 1 ? folders.single.path : partial.path;
      if (await modelDir.exists()) await modelDir.delete(recursive: true);
      await Directory(source).rename(modelDir.path);
      await File(p.join(modelDir.path, _marker)).writeAsString(pack.url);
      _status = VoiceStatus.installed;
    } catch (e) {
      _status = VoiceStatus.notInstalled;
      if (e is! _Cancelled) _error = '$e';
    } finally {
      _progress = null;
      if (await archive.exists()) await archive.delete();
      if (await partial.exists()) await partial.delete(recursive: true);
      notifyListeners();
    }
  }

  void cancel() => _cancelled = true;

  Future<void> remove() async {
    _unloadNeural();
    _status = VoiceStatus.notInstalled;
    notifyListeners();
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
  }

  /// Space the installed voice takes.
  Future<int> sizeOnDisk() async {
    if (!await modelDir.exists()) return 0;
    var bytes = 0;
    await for (final e in modelDir.list(recursive: true)) {
      if (e is File) bytes += await e.length();
    }
    return bytes;
  }

  @override
  void dispose() {
    _unloadNeural();
    super.dispose();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
