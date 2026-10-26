import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/book_meta_store.dart';
import '../library/metadata_sources.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'delete_books.dart';
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
              if (services.meta[book.driveFileId] case final meta?)
                _AboutBook(meta: meta),
              const SizedBox(height: 16),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.travel_explore),
                title: const Text('Find details and cover online'),
                subtitle: const Text('Google Books and Open Library'),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      MetadataPicker(book: book, services: services),
                ),
              ),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                iconColor: theme.colorScheme.error,
                textColor: theme.colorScheme.error,
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete from Google Drive'),
                subtitle: const Text('Removes the file for good'),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  final deleted = await confirmAndDelete(context, [
                    book,
                  ], services);
                  if (deleted.isNotEmpty) navigator.pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Description and publication details, when known.
class _AboutBook extends StatefulWidget {
  const _AboutBook({required this.meta});

  final BookMeta meta;

  @override
  State<_AboutBook> createState() => _AboutBookState();
}

class _AboutBookState extends State<_AboutBook> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.meta;
    final facts = [
      if (m.publisher.isNotEmpty) ('Publisher', m.publisher),
      if (m.published.isNotEmpty) ('Published', m.published),
      if (m.pageCount != null) ('Pages', '${m.pageCount}'),
      if (m.isbn.isNotEmpty) ('ISBN', m.isbn),
      if (m.rating != null) ('Rating', '${m.rating!.toStringAsFixed(1)} / 5'),
    ];
    if (m.description.isEmpty && facts.isEmpty && m.subjects.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        if (m.description.isNotEmpty) ...[
          Text('About', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              m.description,
              maxLines: _expanded ? null : 5,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (!_expanded && m.description.length > 300)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => setState(() => _expanded = true),
              child: const Text('More'),
            ),
        ],
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 28,
            runSpacing: 10,
            children: [
              for (final (label, value) in facts)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ],
                ),
            ],
          ),
        ],
        if (m.subjects.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final subject in m.subjects.take(8))
                Chip(
                  label: Text(subject),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (m.source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Details from ${m.source}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Searches online sources for a book and lets the user pick the right
/// match, like Calibre's metadata download dialog.
class MetadataPicker extends StatefulWidget {
  const MetadataPicker({super.key, required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  State<MetadataPicker> createState() => _MetadataPickerState();
}

class _MetadataPickerState extends State<MetadataPicker> {
  late final MetadataQuery _initial = widget.services.metadata.queryFor(
    widget.book,
  );
  late final _title = TextEditingController(text: _initial.title);
  late final _author = TextEditingController(text: _initial.author);
  Future<List<(MetadataResult, double)>>? _results;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  void _search() {
    final text = _title.text.trim();
    final isbn = RegExp(r'^[\dXx-]{10,17}$').hasMatch(text)
        ? text.replaceAll('-', '')
        : '';
    setState(() {
      _results = widget.services.metadata.search(
        MetadataQuery(
          title: isbn.isEmpty ? text : '',
          author: _author.text.trim(),
          isbn: isbn,
        ),
      );
    });
  }

  Future<void> _choose(
    MetadataResult result,
    List<(MetadataResult, double)> all,
  ) async {
    setState(() => _applying = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.services.metadata.choose(widget.book, result, [
        for (final (r, score) in all)
          if (score >= MetadataService.confident) r,
      ]);
      navigator.pop();
    } catch (e) {
      setState(() => _applying = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Find details online'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title or ISBN',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _author,
                    decoration: const InputDecoration(labelText: 'Author'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder(
                future: _results,
                builder: (context, snapshot) {
                  if (_applying ||
                      snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        "Couldn't reach Google Books or Open Library.",
                      ),
                    );
                  }
                  final all = snapshot.data ?? const [];
                  if (all.isEmpty) {
                    return const Center(child: Text('No matches found.'));
                  }
                  return ListView.separated(
                    itemCount: all.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final (r, score) = all[i];
                      final cover = r.coverUrl;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: SizedBox(
                          width: 44,
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: cover == null
                                ? Container(
                                    color:
                                        theme.colorScheme.surfaceContainerHigh,
                                  )
                                : Image.network(
                                    cover.toString(),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHigh,
                                    ),
                                  ),
                          ),
                        ),
                        title: Text(r.title),
                        subtitle: Text(
                          [
                            if (r.author.isNotEmpty) r.author,
                            if (r.published.isNotEmpty)
                              r.published.split('-').first,
                            r.source,
                          ].join(' · '),
                        ),
                        trailing: score >= MetadataService.confident
                            ? Tooltip(
                                message: 'Good match',
                                child: Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : null,
                        onTap: () => _choose(r, all),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
