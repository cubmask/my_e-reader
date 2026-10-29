import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A file handed to the app, copied to its cache: picked, opened with the
/// app, or shared to it.
typedef IncomingFile = ({File file, String name});

/// The Android side of the app (MainActivity): screen brightness, keeping
/// the screen on, picking and receiving books, sharing and saving files.
///
/// Elsewhere these do nothing and [available] is false, so callers hide
/// what depends on them.
class PlatformBridge {
  PlatformBridge._();

  static final instance = PlatformBridge._();

  static const _channel = MethodChannel('ebook_reader/platform');

  /// Whether the native side exists on this platform.
  bool get available => Platform.isAndroid;

  final _incoming = StreamController<List<IncomingFile>>.broadcast();
  bool _listening = false;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  /// Overrides the screen brightness (0 to 1); null follows the system.
  Future<void> setBrightness(double? value) =>
      _call('setBrightness', {'value': value});

  Future<void> keepScreenOn(bool on) => _call('keepScreenOn', {'on': on});

  /// Lets the user pick files; an empty list when they cancel.
  Future<List<IncomingFile>> pickBooks() async =>
      _files(await _call<List<Object?>>('pickBooks'));

  /// Books opened with the app or shared to it, as they arrive. The first
  /// listener also gets any that arrived before it.
  Stream<List<IncomingFile>> get incoming {
    if (!_listening && available) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'incoming') await _takeIncoming();
      });
      scheduleMicrotask(_takeIncoming);
    }
    return _incoming.stream;
  }

  Future<void> _takeIncoming() async {
    final files = _files(await _call<List<Object?>>('takeIncoming'));
    if (files.isNotEmpty) _incoming.add(files);
  }

  /// Where files to share are written: the share sheet can only hand out
  /// files from here.
  Future<Directory> sharedDir() async {
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'shared'),
    );
    return dir.create(recursive: true);
  }

  /// Opens the share sheet for [file], which must be in [sharedDir].
  Future<bool> shareFile(File file, {String? mimeType, String? title}) async =>
      await _call<bool>('shareFile', {
        'path': file.path,
        'mimeType': mimeType,
        'title': title,
      }) ??
      false;

  Future<bool> shareText(String text, {String? title}) async =>
      await _call<bool>('shareText', {'text': text, 'title': title}) ?? false;

  /// Asks where to save a copy of [file]; false when cancelled.
  Future<bool> saveFile(
    File file, {
    required String name,
    String? mimeType,
  }) async =>
      await _call<bool>('saveFile', {
        'path': file.path,
        'name': name,
        'mimeType': mimeType,
      }) ??
      false;

  /// The device's name as its owner set it, such as "Galaxy Tab S9 Ultra",
  /// or else its model.
  Future<String?> deviceName() => _call<String>('deviceName');

  /// Hands [text] to the Google Translate app; false when it isn't
  /// installed.
  Future<bool> translate(String text) async =>
      await _call<bool>('translate', {'text': text}) ?? false;

  static List<IncomingFile> _files(List<Object?>? list) => [
    for (final item in list ?? const [])
      if (item case {'path': final String path, 'name': final String name})
        (file: File(path), name: name),
  ];
}
