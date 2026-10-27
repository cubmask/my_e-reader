import 'package:flutter/material.dart';

import '../core/platform_bridge.dart';
import '../library/book.dart';
import '../library/converter.dart';
import '../notes/export.dart' show writeShared;
import '../reader/reader_services.dart';

/// Picks a format, converts [book] to it and saves the copy to Drive next
/// to the book, where it joins the library.
Future<void> showConvertDialog(
  BuildContext context,
  Book book,
  ReaderServices services,
) => showDialog<void>(
  context: context,
  builder: (_) => _ConvertDialog(book: book, services: services),
);

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  String? _stage;

  Future<void> _convert(ConvertTarget target) async {
    final services = widget.services;
    final book = widget.book;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _stage = 'Fetching the book');
    try {
      final file = book.format.needsConversion
          ? null
          : await services.cache.open(book);
      final name = convertedName(services.meta.titleOf(book), target);
      final out = await writeShared(name, const <int>[]);
      await services.converter!.convert(
        book,
        file,
        book.format,
        target,
        out,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (mounted) setState(() => _stage = 'Saving to Drive');
      final added = await services.uploader!.uploadNextTo(
        book.driveFileId,
        out,
        name,
      );
      services.added.value = added;
      services.meta.set(
        added.driveFileId,
        title: services.meta.titleOf(book),
        author: services.meta.authorOf(book),
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved "$name" to Drive, next to the book'),
          action: PlatformBridge.instance.available
              ? SnackBarAction(
                  label: 'Share',
                  onPressed: () => PlatformBridge.instance.shareFile(
                    out,
                    mimeType: target.mimeType,
                  ),
                )
              : null,
        ),
      );
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Could not convert: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = ConvertTarget.forFormat(widget.book.format);
    final stage = _stage;
    return AlertDialog(
      title: const Text('Convert to'),
      content: SizedBox(
        width: 380,
        child: stage != null
            ? Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 24),
                  Expanded(child: Text('$stage…')),
                ],
              )
            : targets.isEmpty
            ? const Text(
                'Comics and scanned books are pictures, so there is no text '
                'to convert.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in targets)
                    ListTile(
                      title: Text(t.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _convert(t),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Google Docs does the conversion. Text, headings, lists '
                    'and tables come across; pictures and the book\'s own '
                    'styling don\'t.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      actions: [
        if (stage == null)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
