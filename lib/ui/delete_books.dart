import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../library/book.dart';
import '../reader/reader_services.dart';

/// Asks before deleting [books] from Google Drive, then deletes them.
/// Returns the books deleted; failures are shown in a snack bar.
/// [onConfirmed] runs once the user agrees, before deleting starts.
Future<List<Book>> confirmAndDelete(
  BuildContext context,
  List<Book> books,
  ReaderServices services, {
  VoidCallback? onConfirmed,
}) async {
  if (books.isEmpty) return const [];
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDelete(books: books, services: services),
  );
  if (ok != true) return const [];
  onConfirmed?.call();

  final deleted = <Book>[];
  final failed = <String>[];
  for (final book in books) {
    try {
      await services.cache.deleteFromDrive(book);
      deleted.add(book);
    } catch (e) {
      failed.add('${book.fileName}: ${_reason(e)}');
    }
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        failed.isEmpty
            ? deleted.length == 1
                  ? 'Deleted ${deleted.single.fileName}.'
                  : 'Deleted ${deleted.length} files.'
            : 'Couldn\'t delete ${failed.join('; ')}',
      ),
    ),
  );
  return deleted;
}

String _reason(Object error) => switch (error) {
  drive.DetailedApiRequestError(status: 403) => 'only its owner can delete it',
  drive.DetailedApiRequestError(:final message?) => message,
  _ => 'no connection to Google Drive',
};

class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.books, required this.services});

  final List<Book> books;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final one = books.length == 1;
    const shown = 6;
    return AlertDialog(
      icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
      title: Text(
        one
            ? 'Delete this file permanently?'
            : 'Delete ${books.length} files '
                  'permanently?',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in books.take(shown))
              Text(
                '• ${b.folderPath.isEmpty ? '' : '${b.folderPath}/'}'
                '${b.fileName}',
              ),
            if (books.length > shown) Text('and ${books.length - shown} more'),
            const SizedBox(height: 16),
            Text(
              '${one ? 'It is' : 'They are'} deleted from your Google Drive '
              'straight away, without going to the Drive trash, and can\'t '
              'be recovered.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(one ? 'Delete' : 'Delete ${books.length}'),
        ),
      ],
    );
  }
}
