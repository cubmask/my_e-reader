import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/book_format.dart';
import 'read_aloud.dart';
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

  Future<void> addHighlight(String cfi, String color) async =>
      _web?.callAsyncJavaScript(
        functionBody: 'window.reader.addAnnotation(a)',
        arguments: {
          'a': {'cfi': cfi, 'color': color},
        },
      );

  Future<void> removeHighlight(String cfi) async => _web?.callAsyncJavaScript(
    functionBody: 'window.reader.removeAnnotation(cfi)',
    arguments: {'cfi': cfi},
  );

  Future<void> clearSelection() => _run('window.reader.clearSelection()');

  Future<List<SpeechSegment>?> _tts(String fn) async {
    final result = await _web?.callAsyncJavaScript(
      functionBody: 'return await window.reader.$fn()',
    );
    final value = result?.value;
    if (value is! List) return null;
    return [
      for (final s in value)
        if (s is Map) SpeechSegment('${s['text']}', s['mark']?.toString()),
    ];
  }
}

/// Reads the open web book aloud, highlighting each sentence.
class WebSpeechSource implements SpeechSource {
  WebSpeechSource(this._controller);

  final WebBookController _controller;

  @override
  Future<List<SpeechSegment>?> start() => _controller._tts('ttsStart');

  @override
  Future<List<SpeechSegment>?> next() => _controller._tts('ttsNext');

  @override
  void onSegment(SpeechSegment segment) {
    if (segment.mark case final mark?) {
      _controller._web?.callAsyncJavaScript(
        functionBody: 'window.reader.ttsMark(m)',
        arguments: {'m': mark},
      );
    }
  }

  @override
  void stop() => _controller._run('window.reader.ttsStop()');
}

/// A highlight to draw: its CFI and colour name.
typedef WebHighlight = ({String cfi, String color});

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
    this.highlights = const [],
    required this.onRelocate,
    required this.onSelection,
    required this.onHighlightTapped,
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
  final List<WebHighlight> highlights;

  /// Selected text and its CFI, or null when the selection is cleared.
  final void Function(({String cfi, String text})? selection) onSelection;
  final void Function(String cfi) onHighlightTapped;
  final void Function(String cfi, double fraction, String chapter) onRelocate;
  final void Function(String title, String author, List<TocItem> toc) onOpened;
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
        widget.onOpened('${d['title'] ?? ''}', '${d['author'] ?? ''}', [
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
      handlerName: 'selection',
      callback: (args) {
        final d = args.firstOrNull;
        widget.onSelection(
          d is Map ? (cfi: '${d['cfi']}', text: '${d['text']}') : null,
        );
      },
    );
    web.addJavaScriptHandler(
      handlerName: 'annotationTapped',
      callback: (args) {
        final d = args.firstOrNull;
        if (d is Map) widget.onHighlightTapped('${d['cfi']}');
      },
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
            'lastLocation': widget.initialLocation,
            'columns': widget.columns,
            'theme': widget.settings.theme.name,
            'fontSize': widget.settings.fontSize,
            'annotations': [
              for (final h in widget.highlights)
                {'cfi': h.cfi, 'color': h.color},
            ],
          },
        },
      ),
    );
  }
}
