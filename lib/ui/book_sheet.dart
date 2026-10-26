import 'package:flutter/material.dart';

import '../library/book.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'library_screen.dart' show BookDetailsDialog;

void openBook(BuildContext context, Book book, ReaderServices services) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReaderScreen(book: book, services: services),
    ),
  );
}

/// How far through [book] the reader is, 0 to 1, or null if never opened.
double? progressOf(Book book, ReaderServices? services) =>
    services?.progress[book.driveFileId]?.fraction;

/// "34%", "Finished" or "New".
String progressLabel(Book book, ReaderServices? services) {
  final fraction = progressOf(book, services);
  if (fraction == null) return 'New';
  if (fraction >= 0.995) return 'Finished';
  return '${(fraction * 100).round()}%';
}

String _size(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A book's details, like the sheet Apple Books shows when you tap a cover:
/// cover, title and author, progress, and the main actions.
Future<void> showBookSheet(
  BuildContext context,
  Book book,
  ReaderServices services,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 680),
  builder: (context) => _BookSheet(book: book, services: services),
);

class _BookSheet extends StatelessWidget {
  const _BookSheet({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.cache, services.meta]),
      builder: (context, _) {
        final fraction = progressOf(book, services);
        final cache = services.cache;
        final author = services.meta.authorOf(book);
        final collections = services.meta.collectionsOf(book);
        final details = [
          book.format.label,
          _size(book.sizeBytes),
          if (book.folderPath.isNotEmpty) book.folderPath,
        ].where((s) => s.isNotEmpty).join(' · ');
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BookCover(book: book, services: services, width: 140),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          services.meta.titleOf(book),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (author.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            author,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(details, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (fraction != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: fraction,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(progressLabel(book, services)),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.menu_book),
                      label: Text(fraction == null ? 'Read' : 'Continue'),
                      onPressed: () {
                        Navigator.pop(context);
                        openBook(context, book, services);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: cache.isDownloading(book)
                        ? OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: null,
                            icon: SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: cache.downloadProgress(book),
                              ),
                            ),
                            label: const Text('Downloading'),
                          )
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: Icon(
                              cache.isDownloaded(book)
                                  ? Icons.delete_outline
                                  : Icons.download_for_offline_outlined,
                            ),
                            label: Text(
                              cache.isDownloaded(book)
                                  ? 'Remove download'
                                  : 'Download',
                            ),
                            onPressed: () => cache.isDownloaded(book)
                                ? cache.removeDownload(book)
                                : cache.download(book).catchError((_) {}),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                cache.isDownloaded(book)
                    ? 'Kept on this device for offline reading.'
                    : 'Streams from Google Drive when you open it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit title, author and collections'),
                subtitle: collections.isEmpty
                    ? null
                    : Text(collections.join(', ')),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      BookDetailsDialog(book: book, meta: services.meta),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
