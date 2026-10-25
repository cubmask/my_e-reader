import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_spread.dart';

/// Native PDF viewer (PDFium). Locations are page numbers.
class PdfBookView extends StatefulWidget {
  const PdfBookView({
    super.key,
    required this.file,
    required this.initialPage,
    required this.spread,
    required this.onPageChanged,
    required this.onToggleControls,
  });

  final File file;
  final int initialPage;
  final bool spread;
  final void Function(int page, int pageCount) onPageChanged;
  final VoidCallback onToggleControls;

  @override
  State<PdfBookView> createState() => _PdfBookViewState();
}

class _PdfBookViewState extends State<PdfBookView> {
  final _controller = PdfViewerController();

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
