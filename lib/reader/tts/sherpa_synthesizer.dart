import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart';

import 'speech_engine.dart';

/// Runs a Supertonic model with sherpa-onnx on a worker isolate, so
/// rendering never blocks the UI.
class SherpaSynthesizer implements Synthesizer {
  SherpaSynthesizer._(this._isolate, this._requests, this._replies, this._out);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _replies;
  final Directory _out;
  final _pending = <int, Completer<String>>{};
  int _next = 0;

  /// Loads the model in [modelDir]; sentences are written to [outDir].
  static Future<SherpaSynthesizer> start(
    Directory modelDir,
    Directory outDir,
  ) async {
    // Sentences left over from a session that ended abruptly.
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await outDir.create(recursive: true);
    final replies = ReceivePort();
    final threads = min(4, max(1, Platform.numberOfProcessors ~/ 2));
    final isolate = await Isolate.spawn(_work, (
      replies.sendPort,
      modelDir.path,
      threads,
    ), debugName: 'tts');
    final ready = Completer<SendPort>();
    late final SherpaSynthesizer synth;
    replies.listen((message) {
      switch (message) {
        case SendPort port:
          ready.complete(port);
        case String error when !ready.isCompleted:
          ready.completeError(StateError(error));
        case (int id, String? error):
          final done = synth._pending.remove(id);
          if (error == null) {
            done?.complete(synth._pathOf(id));
          } else {
            done?.completeError(StateError(error));
          }
      }
    });
    try {
      synth = SherpaSynthesizer._(isolate, await ready.future, replies, outDir);
    } catch (_) {
      replies.close();
      isolate.kill();
      rethrow;
    }
    return synth;
  }

  String _pathOf(int id) => p.join(_out.path, 'sentence-$id.wav');

  @override
  Future<String> synthesize(
    String text, {
    required String language,
    required int speaker,
    required double speed,
    SpeechContext? context,
  }) {
    final id = _next++;
    final done = _pending[id] = Completer<String>();
    _requests.send((id, text, language, speaker, speed, _pathOf(id)));
    return done.future;
  }

  void dispose() {
    _requests.send(null);
    for (final done in _pending.values) {
      done.completeError(StateError('Voice closed'));
    }
    _pending.clear();
    _replies.close();
    Timer(const Duration(seconds: 5), _isolate.kill);
  }
}

/// The sherpa-onnx config for an extracted Supertonic model folder.
OfflineTtsConfig supertonicConfig(String dir, {int threads = 2}) {
  String f(String name) => p.join(dir, name);
  return OfflineTtsConfig(
    model: OfflineTtsModelConfig(
      numThreads: threads,
      supertonic: OfflineTtsSupertonicModelConfig(
        durationPredictor: f('duration_predictor.int8.onnx'),
        textEncoder: f('text_encoder.int8.onnx'),
        vectorEstimator: f('vector_estimator.int8.onnx'),
        vocoder: f('vocoder.int8.onnx'),
        ttsJson: f('tts.json'),
        unicodeIndexer: f('unicode_indexer.bin'),
        voiceStyle: f('voice.bin'),
      ),
    ),
  );
}

void _work((SendPort, String, int) args) {
  final (replies, dir, threads) = args;
  final OfflineTts tts;
  try {
    initBindings();
    tts = OfflineTts(supertonicConfig(dir, threads: threads));
    if (tts.ptr.address == 0) throw StateError('Could not load the voice');
  } catch (e) {
    replies.send('$e');
    return;
  }
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    if (message case (
      int id,
      String text,
      String language,
      int speaker,
      double speed,
      String path,
    )) {
      try {
        final audio = tts.generateWithConfig(
          text: text,
          config: OfflineTtsGenerationConfig(
            sid: speaker,
            speed: speed,
            extra: {'lang': language},
          ),
        );
        if (audio.samples.isEmpty) throw StateError('No audio for "$text"');
        writeWave(
          filename: path,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        replies.send((id, null));
      } catch (e) {
        replies.send((id, '$e'));
      }
    } else {
      tts.free();
      requests.close();
    }
  });
}
