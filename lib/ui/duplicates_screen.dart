import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/duplicates.dart';
import '../library/library_controller.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'book_sheet.dart' show progressLabel, progressOf;
import 'delete_books.dart';

/// Duplicates in [controller]'s library.
List<DuplicateGroup> duplicatesIn(LibraryController controller) {
  final services = controller.services;
  return findDuplicates(
    controller.books,
    titleOf: (b) => services?.meta.titleOf(b) ?? b.displayTitle,
    authorOf: (b) => services?.meta.authorOf(b) ?? '',
    opened: (b) => progressOf(b, services) != null,
  );
}

/// Lists duplicate books and deletes the copies the user picks from Drive.
///
/// Identical copies start out ticked for deletion, all but the one to keep;
/// the same book in another format starts unticked. One copy of each book
/// always stays.
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  /// Drive ids ticked for deletion.
  Set<String>? _picked;
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final services = widget.controller.services;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicates'),
        actions: [
          if (services != null)
            TextButton(
              onPressed: () => setState(() {
                _picked = {
                  for (final g in duplicatesIn(widget.controller))
                    for (final b in g.extras) b.driveFileId,
                };
              }),
              child: const Text('Tick all extra copies'),
            ),
        ],
      ),
      body: services == null
          ? const SizedBox()
          : ListenableBuilder(
              listenable: Listenable.merge([widget.controller, services.meta]),
              builder: (context, _) => _build(context, services),
            ),
    );
  }

  Widget _build(BuildContext context, ReaderServices services) {
    final theme = Theme.of(context);
    final groups = duplicatesIn(widget.controller);
    final present = {
      for (final g in groups)
        for (final b in g.books) b.driveFileId,
    };
    final picked = (_picked ??= {
      for (final g in groups)
        for (final b in g.suggested) b.driveFileId,
    })..retainAll(present);
    if (groups.isEmpty) {
      return const Center(child: Text('No duplicates in your library.'));
    }
    final toDelete = [
      for (final g in groups)
        for (final b in g.books)
          if (picked.contains(b.driveFileId)) b,
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Tick the copies to delete from Google Drive. One copy of '
                  'each book is always kept.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final g in groups)
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Text(
                            services.meta.titleOf(g.books.first),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            g.identical
                                ? 'Identical files'
                                : 'Same title, different files',
                          ),
                        ),
                        for (final b in g.books)
                          _CopyTile(
                            book: b,
                            services: services,
                            picked: picked.contains(b.driveFileId),
                            // Never let every copy be ticked.
                            enabled:
                                picked.contains(b.driveFileId) ||
                                g.books
                                        .where(
                                          (c) =>
                                              !picked.contains(c.driveFileId),
                                        )
                                        .length >
                                    1,
                            onChanged: (on) => setState(
                              () => on
                                  ? picked.add(b.driveFileId)
                                  : picked.remove(b.driveFileId),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: _deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined),
              label: Text(
                toDelete.isEmpty
                    ? 'Nothing ticked'
                    : toDelete.length == 1
                    ? 'Delete 1 file'
                    : 'Delete ${toDelete.length} files',
              ),
              onPressed: toDelete.isEmpty || _deleting
                  ? null
                  : () async {
                      await confirmAndDelete(
                        context,
                        toDelete,
                        services,
                        onConfirmed: () => setState(() => _deleting = true),
                      );
                      if (mounted) setState(() => _deleting = false);
                    },
            ),
          ),
        ),
      ],
    );
  }
}

String _size(int? bytes) => bytes == null
    ? ''
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).round()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

String _date(DateTime? d) => d == null
    ? ''
    : 'added ${d.year}-${'${d.month}'.padLeft(2, '0')}-'
          '${'${d.day}'.padLeft(2, '0')}';

class _CopyTile extends StatelessWidget {
  const _CopyTile({
    required this.book,
    required this.services,
    required this.picked,
    required this.enabled,
    required this.onChanged,
  });

  final Book book;
  final ReaderServices services;
  final bool picked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final details = [
      book.format.label,
      _size(book.sizeBytes),
      if (book.folderPath.isNotEmpty) book.folderPath,
      _date(book.createdTime ?? book.modifiedTime),
      if (progressOf(book, services) != null) progressLabel(book, services),
    ].where((s) => s.isNotEmpty).join(' · ');
    return CheckboxListTile(
      value: picked,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      secondary: BookCover(book: book, services: services, width: 36),
      title: Text(book.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(details),
    );
  }
}
