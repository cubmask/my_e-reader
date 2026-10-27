import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/metadata_sources.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'breakpoints.dart';
import 'delete_books.dart';
import 'library_screen.dart' show BookDetailsDialog;
import 'theme.dart';

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

/// "154 / 300 pages" with the current page in coral, or "34% read" when the
/// page count isn't known.
class PagesRead extends StatelessWidget {
  const PagesRead({super.key, required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progressOf(book, services) ?? 0;
    final pages = services.meta[book.driveFileId]?.pageCount;
    final style = theme.textTheme.titleMedium;
    final accent = style?.copyWith(color: theme.colorScheme.primary);
    return Text.rich(
      pages != null && pages > 0
          ? TextSpan(
              children: [
                TextSpan(
                  text: '${(fraction * pages).round().clamp(1, pages)}',
                  style: accent,
                ),
                TextSpan(text: ' / $pages pages'),
              ],
            )
          : TextSpan(
              children: [
                TextSpan(text: progressLabel(book, services), style: accent),
                const TextSpan(text: ' read'),
              ],
            ),
      style: style,
    );
  }
}

/// Opens a book's page: its cover, title and author, the main actions, the
/// description and the publication details.
Future<void> showBookSheet(
  BuildContext context,
  Book book,
  ReaderServices services,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => BookPage(book: book, services: services),
  ),
);

class BookPage extends StatelessWidget {
  const BookPage({super.key, required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([
          services.cache,
          services.meta,
          services.covers,
        ]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) => box.maxWidth >= Breakpoints.medium
              ? _wide(context, box.maxWidth)
              : _narrow(context),
        ),
      ),
    );
  }

  /// The tablet layout: the cover straddling a lighter panel that holds the
  /// actions and details, as in a printed catalogue.
  Widget _wide(BuildContext context, double width) {
    final theme = Theme.of(context);
    final coverWidth = width >= 1400 ? 300.0 : 240.0;
    const top = 88.0;
    // Where the lighter panel starts, part-way down the cover.
    final band = top + coverWidth / coverAspectRatio * 0.62;
    final side = ((width - 1120) / 2).clamp(32.0, double.infinity);
    return Stack(
      children: [
        SingleChildScrollView(
          child: Stack(
            children: [
              Positioned(
                top: band,
                left: side - 24,
                right: side - 24,
                bottom: 0,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerLowest,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(side + 48, top, side + 48, 56),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BookCover(
                          book: book,
                          services: services,
                          width: coverWidth,
                        ),
                        const SizedBox(width: 64),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: band - top - 8,
                                ),
                                child: _Heading(book: book, services: services),
                              ),
                              const SizedBox(height: 32),
                              _Actions(book: book, services: services),
                              const SizedBox(height: 20),
                              const Divider(height: 1),
                              const SizedBox(height: 20),
                              _Progress(book: book, services: services),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _Description(book: book, services: services),
                        ),
                        const SizedBox(width: 64),
                        Expanded(
                          flex: 2,
                          child: _Facts(book: book, services: services),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _BackButton(),
      ],
    );
  }

  Widget _narrow(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 40),
          children: [
            Center(
              child: BookCover(book: book, services: services, width: 180),
            ),
            const SizedBox(height: 32),
            _Heading(book: book, services: services),
            const SizedBox(height: 24),
            _Actions(book: book, services: services),
            const SizedBox(height: 20),
            _Progress(book: book, services: services),
            const SizedBox(height: 28),
            _Description(book: book, services: services),
            const SizedBox(height: 28),
            _Facts(book: book, services: services),
          ],
        ),
        const _BackButton(),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: CircleIconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = services.meta.authorOf(book);
    final subjects = services.meta[book.driveFileId]?.subjects ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(services.meta.titleOf(book), style: theme.textTheme.displaySmall),
        if (author.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            author,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            subjects.take(4).join(' · '),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Read, and round buttons to download, look up details, edit and delete.
class _Actions extends StatelessWidget {
  const _Actions({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final cache = services.cache;
    final started = progressOf(book, services) != null;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton(
          onPressed: () => openBook(context, book, services),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(started ? 'Continue reading' : 'Start reading'),
              const SizedBox(width: 6),
              const Icon(Icons.north_east, size: 16),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (cache.isDownloading(book))
          SizedBox.square(
            dimension: 48,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: cache.downloadProgress(book),
              ),
            ),
          )
        else
          CircleIconButton(
            tooltip: cache.isDownloaded(book) ? 'Remove download' : 'Download',
            selected: cache.isDownloaded(book),
            icon: Icon(
              cache.isDownloaded(book) ? Icons.download_done : Icons.download,
            ),
            onPressed: () => cache.isDownloaded(book)
                ? cache.removeDownload(book)
                : cache.download(book).catchError((_) {}),
          ),
        CircleIconButton(
          tooltip: 'Find details and cover online',
          icon: const Icon(Icons.travel_explore),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => MetadataPicker(book: book, services: services),
          ),
        ),
        CircleIconButton(
          tooltip: 'Edit title, author and collections',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => BookDetailsDialog(book: book, meta: services.meta),
          ),
        ),
        CircleIconButton(
          tooltip: 'Delete from Google Drive',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final deleted = await confirmAndDelete(context, [book], services);
            if (deleted.isNotEmpty) navigator.pop();
          },
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progressOf(book, services);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fraction != null) ...[
          PagesRead(book: book, services: services),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          services.cache.isDownloaded(book)
              ? 'Kept on this device for offline reading.'
              : 'Streams from Google Drive when you open it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The book's description, folded to a few lines until tapped.
class _Description extends StatefulWidget {
  const _Description({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = widget.services.meta[widget.book.driveFileId];
    final description = meta?.description ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Description',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        if (description.isEmpty)
          Text(
            'No description yet. Use the search button to find details and a '
            'cover from Google Books or Open Library.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.7,
            ),
          )
        else ...[
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              description,
              maxLines: _expanded ? null : 8,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.75),
            ),
          ),
          if (!_expanded && description.length > 500)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => setState(() => _expanded = true),
              child: const Text('More'),
            ),
        ],
        if (meta?.source.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Details from ${meta!.source}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Publication and file details in a column of labelled facts.
class _Facts extends StatelessWidget {
  const _Facts({required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = services.meta[book.driveFileId];
    final collections = services.meta.collectionsOf(book);
    final facts = [
      if (m != null && m.publisher.isNotEmpty)
        (
          'Publisher',
          [m.publisher, if (m.published.isNotEmpty) m.published].join(', '),
        )
      else if (m != null && m.published.isNotEmpty)
        ('Published', m.published),
      if (m?.pageCount != null) ('Length', '${m!.pageCount} pages'),
      if (m != null && m.isbn.isNotEmpty) ('ISBN', m.isbn),
      if (m?.rating != null) ('Rating', '${m!.rating!.toStringAsFixed(1)} / 5'),
      (
        'File',
        [
          book.format.label,
          _size(book.sizeBytes),
          if (book.folderPath.isNotEmpty) book.folderPath,
        ].where((s) => s.isNotEmpty).join(' · '),
      ),
      if (collections.isNotEmpty) ('Collections', collections.join(', ')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in facts) ...[
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          const SizedBox(height: 24),
        ],
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
