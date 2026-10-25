import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Serves the bundled reader page and the open book over loopback HTTP.
///
/// foliate-js is made of ES modules, which WebViews refuse to load from
/// file:// URLs, so the page needs a real origin. A random path token keeps
/// other apps on the device from reading the book through the port.
class ReaderServer {
  ReaderServer({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  static const _assetRoot = 'assets/reader';
  static const _types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
  };

  final AssetBundle _bundle;
  final String _token = List.generate(
    24,
    (_) => Random.secure().nextInt(36).toRadixString(36),
  ).join();

  HttpServer? _server;
  File? _book;

  /// Starts the server if needed and returns the page URL for [book].
  Future<Uri> serve(File book) async {
    _book = book;
    final server = _server ??=
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          ..listen(_handle);
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/index.html');
  }

  /// URL of the book file, relative to the page.
  static const bookPath = 'book';

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final segments = request.uri.pathSegments;
    try {
      if (segments.isEmpty || segments.first != _token) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final path = segments.skip(1).join('/');
      if (path == bookPath && _book != null) {
        response.headers.contentType = ContentType.binary;
        await response.addStream(_book!.openRead());
        return;
      }
      if (path.contains('..')) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }
      final data = await _bundle.load('$_assetRoot/$path');
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _types[p.extension(path)] ?? 'application/octet-stream',
      );
      response.add(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }
}
