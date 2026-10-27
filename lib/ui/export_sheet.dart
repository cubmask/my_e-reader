import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform_bridge.dart';
import '../library/book.dart';
import '../notes/annotation_store.dart';
import '../notes/export.dart';
import '../reader/reader_services.dart';

/// Ways to take notes out of the app: copy or share them as Markdown, save
/// a Markdown file, and for a PDF with handwriting, a copy of the PDF with
/// the ink on its pages, shared or saved next to the book in Drive.
Future<void> showExportSheet(
  BuildContext context, {
  required String title,
  required List<Annotation> annotations,
  required ReaderServices services,
  Book? pdf,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final markdown = annotationsToMarkdown(annotations);
  final name = '${safeFileName(title)} notes.md';
  final bridge = PlatformBridge.instance;
  final hasInk =
      pdf != null && services.ink.pagesWithInk(pdf.driveFileId).isNotEmpty;

  void say(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (annotations.isNotEmpty) ...[
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: const Text('Copy as Markdown'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: markdown));
                say('Copied as Markdown');
              },
            ),
            if (bridge.available) ...[
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share as a Markdown file'),
                subtitle: const Text('To Notion, Obsidian, email…'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await writeShared(name, markdown);
                  await bridge.shareFile(
                    file,
                    mimeType: 'text/markdown',
                    title: 'Share notes',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save as a Markdown file'),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await writeShared(name, markdown);
                  if (await bridge.saveFile(
                    file,
                    name: name,
                    mimeType: 'text/markdown',
                  )) {
                    say('Notes saved');
                  }
                },
              ),
            ],
          ],
          if (hasInk && services.uploader != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Save a copy with handwriting to Drive'),
              subtitle: const Text('Next to the book, as a new PDF'),
              onTap: () {
                Navigator.pop(context);
                _inkCopy(services, pdf, say, share: false);
              },
            ),
            if (bridge.available)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share a copy with handwriting'),
                onTap: () {
                  Navigator.pop(context);
                  _inkCopy(services, pdf, say, share: true);
                },
              ),
          ],
        ],
      ),
    ),
  );
}

Future<void> _inkCopy(
  ReaderServices services,
  Book book,
  void Function(String) say, {
  required bool share,
}) async {
  say('Making a copy with your handwriting…');
  try {
    final source = await services.cache.open(book);
    final bytes = await pdfWithInk(source, {
      for (final page in services.ink.pagesWithInk(book.driveFileId))
        page: services.ink.forPage(book.driveFileId, page),
    });
    final name = '${book.displayTitle} (with notes).pdf';
    final file = await writeShared(name, bytes);
    if (share) {
      await PlatformBridge.instance.shareFile(
        file,
        mimeType: 'application/pdf',
        title: 'Share annotated copy',
      );
    } else {
      final added = await services.uploader!.uploadNextTo(
        book.driveFileId,
        file,
        name,
      );
      services.added.value = added;
      say('Saved "$name" to Drive, next to the book');
    }
  } catch (e) {
    say('Could not make the copy: $e');
  }
}
