import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_spread.dart';
import 'read_aloud.dart';

/// Native PDF viewer (PDFium). Locations are page numbers.
class PdfBookView extends StatefulWidget {
  const PdfBookView({
    super.key,
    required this.file,
    required this.controller,
    required this.initialPage,
    required this.spread,
    required this.onPageChanged,
    required this.onToggleControls,
  });

  final File file;
  final PdfViewerController controller;
  final int initialPage;
  final bool spread;
  final void Function(int page, int pageCount) onPageChanged;
  final VoidCallback onToggleControls;

  @override
  State<PdfBookView> createState() => _PdfBookViewState();
}

class _PdfBookViewState extends State<PdfBookView> {
  PdfViewerController get _controller => widget.controller;

  @override
  void didUpdateWidget(PdfBookView old) {
    super.didUpdateWidget(old);
    if (old.spread != widget.spread && _controller.isReady) {
      _controller.invalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      widget.file.path,
      controller: _controller,
      initialPageNumber: widget.initialPage,
      params: PdfViewerParams(
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
        onGeneralTap: (context, controller, details) {
          if (details.type != PdfViewerGeneralTapType.tap) return false;
          widget.onToggleControls();
          return true;
        },
      ),
    );
  }
}

/// Reads a PDF aloud page by page, turning pages as it goes.
class PdfSpeechSource implements SpeechSource {
  PdfSpeechSource(this._controller);

  final PdfViewerController _controller;
  int _page = 1;

  Future<List<SpeechSegment>?> _read(int page) async {
    if (!_controller.isReady || page > _controller.pageCount) return null;
    _page = page;
    await _controller.goToPage(pageNumber: page);
    final text = await _controller.document.pages[page - 1]
        .loadStructuredText();
    return sentencesOf(text.fullText);
  }

  @override
  Future<List<SpeechSegment>?> start() => _read(_controller.pageNumber ?? 1);

  @override
  Future<List<SpeechSegment>?> next() => _read(_page + 1);

  @override
  void onSegment(SpeechSegment segment) {}

  @override
  void stop() {}
}
