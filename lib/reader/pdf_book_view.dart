import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../notes/annotation_store.dart';
import '../notes/ink_store.dart';
import 'ink_layer.dart';
import 'pdf_errors.dart';
import 'pdf_highlights.dart';
import 'pdf_speech.dart';
import 'pdf_spread.dart';
import 'read_aloud.dart';

/// Native PDF viewer (PDFium). Locations are page numbers.
class PdfBookView extends StatefulWidget {
  const PdfBookView({
    super.key,
    required this.file,
    this.streamUrl,
    required this.controller,
    required this.initialPage,
    required this.spread,
    required this.onPageChanged,
    required this.onToggleControls,
    this.onStreamFailed,
    required this.bookId,
    this.paintSearch,
    this.highlighter,
    this.spoken,
    this.onSelection,
    this.onHighlightTapped,
    this.onReady,
    this.onFailed,
    required this.ink,
    required this.inkController,
  });

  /// The local copy, or null when streaming from [streamUrl].
  final File? file;

  /// A URL that answers range requests, so pages load as they are needed.
  final Uri? streamUrl;
  final String bookId;

  /// Draws search matches on a page.
  final PdfViewerPagePaintCallback? paintSearch;

  /// Draws text highlights and finds the one tapped.
  final PdfHighlighter? highlighter;

  /// Draws the sentence being read aloud.
  final PdfHighlighter? spoken;

  /// Selected text and its location, or null when the selection is cleared.
  final void Function(({String location, String text})? selection)? onSelection;
  final void Function(String location)? onHighlightTapped;

  /// Called once the document has opened.
  final void Function(PdfDocument document)? onReady;

  /// Called with the message shown when the document will not open.
  final void Function(String message)? onFailed;
  final InkStore ink;
  final InkController inkController;
  final PdfViewerController controller;
  final int initialPage;
  final bool spread;
  final void Function(int page, int pageCount) onPageChanged;
  final VoidCallback onToggleControls;

  /// Called when the book will not open from [streamUrl], so the caller can
  /// fetch the whole file and open that instead.
  ///
  /// Streaming hands PDFium the book one range request at a time, and PDFium
  /// reports any failed request while opening as a damaged file, so the
  /// error says nothing about the book itself.
  final VoidCallback? onStreamFailed;

  @override
  State<PdfBookView> createState() => _PdfBookViewState();
}

class _PdfBookViewState extends State<PdfBookView> {
  PdfViewerController get _controller => widget.controller;
  bool _streamFailed = false;
  bool _failed = false;
  Timer? _selectionTimer;

  @override
  void dispose() {
    _selectionTimer?.cancel();
    super.dispose();
  }

  /// Reports the selection once it has settled, as the web reader does.
  void _selectionChanged(PdfTextSelection selection) {
    final onSelection = widget.onSelection;
    if (onSelection == null) return;
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(milliseconds: 400), () async {
      final result = await pdfSelection(selection);
      if (mounted) onSelection(result);
    });
  }

  @override
  void didUpdateWidget(PdfBookView old) {
    super.didUpdateWidget(old);
    if (old.spread != widget.spread && _controller.isReady) {
      _controller.invalidate();
    }
  }

  Widget _errorBanner(BuildContext context, Object error) {
    final onStreamFailed = widget.onStreamFailed;
    if (widget.streamUrl != null && onStreamFailed != null) {
      if (!_streamFailed) {
        _streamFailed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => onStreamFailed());
      }
      return const Center(child: CircularProgressIndicator());
    }
    final file = widget.file;
    return FutureBuilder(
      future: file == null ? Future.value(true) : looksLikePdf(file),
      builder: (context, isPdf) {
        final message = isPdf.hasData
            ? pdfErrorMessage(error, isPdf: isPdf.data!)
            : '';
        if (isPdf.hasData && !_failed) {
          _failed = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onFailed?.call(message),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(message, textAlign: TextAlign.center),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      errorBannerBuilder: (context, error, _, _) =>
          _errorBanner(context, error),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      layoutPages: widget.spread
          ? (pages, params) {
              final layout = spreadLayout([
                for (final p in pages) Size(p.width, p.height),
              ], params.margin);
              return PdfPageLayout(
                pageLayouts: layout.rects,
                documentSize: layout.size,
              );
            }
          : null,
      onPageChanged: (page) {
        if (page != null && _controller.isReady) {
          widget.onPageChanged(page, _controller.pageCount);
        }
      },
      pagePaintCallbacks: [
        ?widget.paintSearch,
        ?widget.highlighter?.paint,
        ?widget.spoken?.paint,
      ],
      textSelectionParams: PdfTextSelectionParams(
        enabled: !widget.inkController.enabled,
        onTextSelectionChange: _selectionChanged,
      ),
      // The reader shows its own popover for selected text.
      buildContextMenu: widget.onSelection == null ? null : (_, _) => null,
      onViewerReady: (document, _) => widget.onReady?.call(document),
      pageOverlaysBuilder: (context, rect, page) => [
        InkPageLayer(
          key: ValueKey(page.pageNumber),
          bookId: widget.bookId,
          page: page.pageNumber,
          store: widget.ink,
          controller: widget.inkController,
        ),
      ],
      onGeneralTap: (context, controller, details) {
        if (details.type != PdfViewerGeneralTapType.tap) return false;
        final hit = widget.highlighter?.hitTest(details.documentPosition);
        if (hit != null) {
          widget.onHighlightTapped?.call(hit.toString());
        } else {
          widget.onToggleControls();
        }
        return true;
      },
    );
    final url = widget.streamUrl;
    if (url != null) {
      return PdfViewer.uri(
        url,
        controller: _controller,
        initialPageNumber: widget.initialPage,
        preferRangeAccess: true,
        timeout: const Duration(seconds: 30),
        params: params,
      );
    }
    return PdfViewer.file(
      widget.file!.path,
      controller: _controller,
      initialPageNumber: widget.initialPage,
      params: params,
    );
  }
}

/// Reads a PDF aloud page by page, turning pages as it goes.
///
/// Running heads, page numbers, footnotes, reference marks and web
/// addresses are skipped, and a sentence that runs onto the next page is
/// read in one piece with that page. Each sentence carries its place on the
/// page as a [PdfTextLocation], so it can be highlighted while it is read.
class PdfSpeechSource implements SpeechSource {
  /// Reads the PDF on screen from the page in view, or from [from], such as
  /// the start of the selected text. [onSpoken] is told where each
  /// sentence is as it is read, and null when reading stops; without it,
  /// the viewer turns to each page as reading reaches it.
  PdfSpeechSource(
    PdfViewerController controller, {
    PdfTextLocation? from,
    void Function(PdfTextLocation? location)? onSpoken,
  }) : this.pages(
         pageCount: () => controller.isReady ? controller.pageCount : 0,
         page: (n) => controller.document.pages[n - 1],
         startPage: () => controller.pageNumber ?? 1,
         turnTo: onSpoken != null
             ? (_) async {}
             : (n) => controller.goToPage(pageNumber: n),
         from: from,
         onSpoken: onSpoken,
       );

  /// Reads a PDF that may not be on screen, such as one started in the car.
  /// [turnTo] is called as reading reaches each page.
  PdfSpeechSource.pages({
    required this._pageCount,
    required PdfPage Function(int number) page,
    required this._startPage,
    required this._turnTo,
    PdfTextLocation? this._from,
    void Function(PdfTextLocation? location)? this._onSpoken,
  }) : _pageOf = page;

  final int Function() _pageCount;
  final PdfPage Function(int number) _pageOf;
  final int Function() _startPage;
  final Future<void> Function(int number) _turnTo;
  final void Function(PdfTextLocation? location)? _onSpoken;
  final PdfTextLocation? _from;
  int _page = 1;

  /// The page reading has reached, as last passed to [_turnTo].
  int? _shown;

  /// The start of a sentence the previous page broke off, and where it is.
  String _carry = '';
  List<({int page, int start, int end})> _carryAt = const [];

  @override
  String? get language => null;

  Future<List<SpeechSegment>?> _read(int page, {int? fromChar}) async {
    final count = _pageCount();
    if (page > count) {
      if (_carry.isEmpty) return null;
      final rest = [_segment(_carry, _carryAt, page - 1)];
      _carry = '';
      _carryAt = const [];
      return rest;
    }
    _page = page;
    final pdfPage = _pageOf(page);
    final text = await pdfPage.loadStructuredText();
    final lines = pdfLines(text.fullText, text.charRects);
    final words = speakable(
      lines.isEmpty ? text.fullText : readablePdfText(lines, pdfPage.height),
    );
    final sentences = [for (final s in sentencesOf(words)) s.text];
    final found = locateSentences(text.fullText, sentences);
    final at = [
      for (final f in found)
        [if (f != null) (page: page, start: f.start, end: f.end)],
    ];
    if (fromChar != null) {
      // Starts with the sentence the reader picked, not the page's first.
      final first = found.indexWhere((f) => f != null && f.end > fromChar);
      if (first > 0) {
        sentences.removeRange(0, first);
        at.removeRange(0, first);
      }
    } else if (_carry.isNotEmpty && sentences.isNotEmpty) {
      sentences[0] = '$_carry ${sentences[0]}';
      at[0] = [..._carryAt, ...at[0]];
      _carry = '';
      _carryAt = const [];
    }
    if (page < count &&
        sentences.isNotEmpty &&
        !RegExp(r'[.!?…。！？]["”’」)\]]*$').hasMatch(sentences.last)) {
      _carry = sentences.removeLast();
      _carryAt = at.removeLast();
    }
    return [
      for (var i = 0; i < sentences.length; i++)
        _segment(sentences[i], at[i], page),
    ];
  }

  SpeechSegment _segment(
    String text,
    List<({int page, int start, int end})> at,
    int page,
  ) => SpeechSegment(
    text,
    // An empty range still says which page the sentence is on.
    PdfTextLocation(at.isEmpty ? [(page: page, start: 0, end: 0)] : at)
        .toString(),
  );

  @override
  Future<List<SpeechSegment>?> start() {
    _carry = '';
    _carryAt = const [];
    final from = _from?.ranges.first;
    return _read(from?.page ?? _startPage(), fromChar: from?.start);
  }

  @override
  Future<List<SpeechSegment>?> next() => _read(_page + 1);

  @override
  void onSegment(SpeechSegment segment) {
    final location = PdfTextLocation.parse(segment.mark ?? '');
    if (location == null) return;
    final page = location.ranges.first.page;
    if (page != _shown) {
      _shown = page;
      _turnTo(page);
    }
    _onSpoken?.call(location);
  }

  @override
  void stop() => _onSpoken?.call(null);
}
