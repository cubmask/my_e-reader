import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/book_format.dart';
import 'reader_server.dart';
import 'reader_settings.dart';

class TocItem {
  const TocItem(this.label, this.href, this.depth);

  final String label;
  final String href;
  final int depth;
}

/// Commands the reader screen sends to the web reader.
class WebBookController {
  InAppWebViewController? _web;

  Future<void> _run(String js) async => _web?.evaluateJavascript(source: js);

  Future<void> next() => _run('window.reader.next()');
  Future<void> prev() => _run('window.reader.prev()');

  Future<void> goTo(String href) async => _web?.callAsyncJavaScript(
    functionBody: 'await window.reader.goTo(target)',
    arguments: {'target': href},
  );

  Future<void> goToFraction(double fraction) async => _web?.callAsyncJavaScript(
    functionBody: 'await window.reader.goToFraction(f)',
    arguments: {'f': fraction},
  );
}

/// Reflowable and comic books rendered by foliate-js in a WebView:
/// EPUB, MOBI, AZW3, FB2, TXT and CBZ.
class WebBookView extends StatefulWidget {
  const WebBookView({
    super.key,
    required this.file,
    required this.fileName,
    required this.format,
    required this.server,
    required this.controller,
    required this.settings,
    required this.columns,
    this.initialLocation,
    required this.onRelocate,
    required this.onOpened,
    required this.onError,
    required this.onToggleControls,
  });

  final File file;
  final String fileName;
  final BookFormat format;
  final ReaderServer server;
  final WebBookController controller;
  final ReaderSettings settings;
  final int columns;
  final String? initialLocation;
  final void Function(String cfi, double fraction, String chapter) onRelocate;
  final void Function(String title, List<TocItem> toc) onOpened;
  final void Function(String message) onError;
  final VoidCallback onToggleControls;

  @override
  State<WebBookView> createState() => _WebBookViewState();
}

class _WebBookViewState extends State<WebBookView> {
  Uri? _url;

  @override
  void initState() {
    super.initState();
    widget.server.serve(widget.file).then((url) {
      if (mounted) setState(() => _url = url);
    }, onError: (Object e) => widget.onError('$e'));
    widget.settings.addListener(_applyStyle);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_applyStyle);
    super.dispose();
  }

  @override
  void didUpdateWidget(WebBookView old) {
    super.didUpdateWidget(old);
    if (old.columns != widget.columns) {
      widget.controller._run('window.reader.setColumns(${widget.columns})');
    }
  }

  void _applyStyle() {
    widget.controller._web?.callAsyncJavaScript(
      functionBody: 'window.reader.setStyle(s)',
      arguments: {
        's': {
          'theme': widget.settings.theme.name,
          'fontSize': widget.settings.fontSize,
        },
      },
    );
  }

  void _addHandlers(InAppWebViewController web) {
    web.addJavaScriptHandler(
      handlerName: 'relocate',
      callback: (args) {
        final d = args.first as Map;
        widget.onRelocate(
          '${d['cfi']}',
          (d['fraction'] as num?)?.toDouble() ?? 0,
          '${d['chapter'] ?? ''}',
        );
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'opened',
      callback: (args) {
        final d = args.first as Map;
        widget.onOpened('${d['title']}', [
          for (final item in (d['toc'] as List? ?? const []))
            if (item is Map)
              TocItem(
                '${item['label']}',
                '${item['href']}',
                (item['depth'] as num?)?.toInt() ?? 0,
              ),
        ]);
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'error',
      callback: (args) => widget.onError('${args.firstOrNull}'),
    );
    web.addJavaScriptHandler(
      handlerName: 'toggleControls',
      callback: (_) => widget.onToggleControls(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) return const Center(child: CircularProgressIndicator());
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(url)),
      initialSettings: InAppWebViewSettings(
        supportZoom: false,
        transparentBackground: true,
        disableHorizontalScroll: true,
        disableVerticalScroll: true,
        useHybridComposition: true,
      ),
      onWebViewCreated: (web) {
        widget.controller._web = web;
        _addHandlers(web);
      },
      onLoadStop: (web, _) => web.callAsyncJavaScript(
        functionBody: 'await window.reader.open(args)',
        arguments: {
          'args': {
            'url': ReaderServer.bookPath,
            'name': widget.fileName,
            'format': widget.format.name,
            'lastLocation': widget.initialLocation,
            'columns': widget.columns,
            'theme': widget.settings.theme.name,
            'fontSize': widget.settings.fontSize,
          },
        },
      ),
    );
  }
}
