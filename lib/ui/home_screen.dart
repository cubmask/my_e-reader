import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/duplicates.dart';
import '../library/library_controller.dart';
import '../notes/annotation_store.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'book_sheet.dart';
import 'breakpoints.dart';
import 'stats_screen.dart';
import 'delete_books.dart';
import 'duplicates_screen.dart';
import 'library_screen.dart';

/// The first screen: a "Happy reading" greeting with the book you're in the
/// middle of, shelves of large covers, and on tablets a side panel with that
/// book's details and your latest highlights.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final services = controller.services;
        // Sign-in, folder choice, loading and errors look the same as in
        // the library.
        if (controller.status != LibraryStatus.ready || services == null) {
          return LibraryScreen(controller: controller);
        }
        return ListenableBuilder(
          listenable: Listenable.merge([
            services.meta,
            services.cache,
            services.covers,
            services.newBooks,
            services.duplicates,
            services.annotations,
          ]),
          builder: (context, _) =>
              _buildShelves(context, controller.books, services),
        );
      },
    );
  }

  Widget _buildShelves(
    BuildContext context,
    List<Book> books,
    ReaderServices services,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.medium;
    // The Tab S9 Ultra has room for the reading panel beside the shelves.
    final twoPane = width >= Breakpoints.expanded;
    final pad = wide ? 48.0 : 20.0;
    DateTime? opened(Book b) => services.progress[b.driveFileId]?.updatedAt;

    final started =
        books
            .where(
              (b) =>
                  opened(b) != null && progressLabel(b, services) != 'Finished',
            )
            .toList()
          ..sort((a, b) => opened(b)!.compareTo(opened(a)!));
    final current = started.firstOrNull;
    final recent = started.skip(1).take(15).toList();
    final downloaded = books.where(services.cache.isDownloaded).toList();
    final fresh = services.newBooks.of(books, opened: (b) => opened(b) != null);
    final added = books.where((b) => opened(b) == null).toList()
      ..sort(
        (a, b) => (b.modifiedTime ?? DateTime(0)).compareTo(
          a.modifiedTime ?? DateTime(0),
        ),
      );
    final byId = {for (final b in books) b.driveFileId: b};
    final highlights =
        services.annotations.all
            .where((a) => !a.isBookmark && byId.containsKey(a.bookId))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final latest = highlights.take(4).toList();
    final panel = twoPane && (current != null || latest.isNotEmpty);

    final shelves = RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, wide ? 56 : 24, 0, 40),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: _Greeting(
              current: current,
              books: books,
              empty: books.isEmpty,
              services: services,
              wide: wide,
            ),
          ),
          SizedBox(height: wide ? 40 : 28),
          if (services.duplicates.unseen(duplicatesIn(controller))
              case final found when found.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _DuplicatesBanner(
                groups: found,
                controller: controller,
                services: services,
              ),
            ),
            const SizedBox(height: 28),
          ],
          if (current != null && !panel) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _ContinueCard(
                book: current,
                services: services,
                wide: wide,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (fresh.isNotEmpty) ...[
            _NewBooksHero(
              books: fresh,
              services: services,
              pad: pad,
              wide: wide,
            ),
            const SizedBox(height: 12),
          ],
          if (recent.isNotEmpty)
            _Shelf(
              title: 'Recent',
              books: recent,
              services: services,
              pad: pad,
              wide: wide,
            ),
          if (downloaded.isNotEmpty)
            _Shelf(
              title: 'On this device',
              books: downloaded,
              services: services,
              pad: pad,
              wide: wide,
            ),
          if (added.isNotEmpty)
            _Shelf(
              title: 'Not started yet',
              books: added.take(20).toList(),
              services: services,
              pad: pad,
              wide: wide,
            ),
          if (!panel && latest.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 44, pad, 0),
              child: _Highlights(
                items: latest,
                books: byId,
                services: services,
              ),
            ),
        ],
      ),
    );
    if (!panel) return shelves;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: shelves),
        SizedBox(
          width: width >= 1500 ? 480 : 400,
          child: _ReadingPanel(
            book: current,
            highlights: latest,
            books: byId,
            services: services,
          ),
        ),
      ],
    );
  }
}

/// "Happy reading" and a line about where you are in your current book.
class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.current,
    required this.books,
    required this.empty,
    required this.services,
    required this.wide,
  });

  final Book? current;
  final List<Book> books;
  final bool empty;
  final ReaderServices services;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = current;
    final String line;
    if (book != null) {
      final author = services.meta.authorOf(book);
      line =
          "You're ${progressLabel(book, services)} of the way through "
          '${services.meta.titleOf(book)}'
          '${author.isEmpty ? '' : ' by $author'}. '
          'Pick up where you left off and step back into the story.';
    } else if (empty) {
      line =
          'Your library is empty. Add books to your Google Drive folder and '
          "they'll appear here.";
    } else {
      line = 'Choose a book from your library and lose yourself in a story.';
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Happy reading',
            style: wide
                ? theme.textTheme.displayLarge
                : theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 20),
          Text(line, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
          const SizedBox(height: 16),
          StatsChip(services: services, books: books),
          if (book != null) ...[
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => openBook(context, book, services),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Continue reading'),
                  SizedBox(width: 6),
                  Icon(Icons.north_east, size: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The lighter column on the right of Home on tablets: the book you're
/// reading, large, with its description, and your latest highlights.
class _ReadingPanel extends StatelessWidget {
  const _ReadingPanel({
    required this.book,
    required this.highlights,
    required this.books,
    required this.services,
  });

  final Book? book;
  final List<Annotation> highlights;
  final Map<String, Book> books;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = this.book;
    final description = book == null
        ? ''
        : services.meta[book.driveFileId]?.description ?? '';
    final author = book == null ? '' : services.meta.authorOf(book);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(40, 56, 40, 40),
        children: [
          if (book != null) ...[
            Center(
              child: GestureDetector(
                onTap: () => openBook(context, book, services),
                onLongPress: () => showBookSheet(context, book, services),
                child: BookCover(book: book, services: services, width: 200),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              services.meta.titleOf(book),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 14),
            PagesRead(book: book, services: services),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progressOf(book, services) ?? 0,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                description,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
              ),
            ],
            if (author.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '– $author',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
          if (highlights.isNotEmpty) ...[
            SizedBox(height: book == null ? 0 : 44),
            _Highlights(items: highlights, books: books, services: services),
          ],
        ],
      ),
    );
  }
}

/// The latest highlights across the library on a dotted timeline, each
/// opening its book at the passage.
class _Highlights extends StatelessWidget {
  const _Highlights({
    required this.items,
    required this.books,
    required this.services,
  });

  final List<Annotation> items;
  final Map<String, Book> books;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your highlights', style: theme.textTheme.titleLarge),
        const SizedBox(height: 20),
        for (final (i, a) in items.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 20,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: highlightSwatches[a.color],
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (i < items.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: scheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      final book = books[a.bookId];
                      if (book == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReaderScreen(
                            book: book,
                            services: services,
                            openAt: a.location,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.bookTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '“${a.text.trim()}”',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              height: 1.6,
                            ),
                          ),
                          if (a.note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              a.note,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            timeAgo(a.updatedAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "just now", "5 min ago", "3 h ago", "2 days ago" or a date.
String timeAgo(DateTime when, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${when.day}/${when.month}/${when.year}';
}

/// The section for books that recently arrived in Drive. One new book fills
/// the width; several scroll sideways.
class _NewBooksHero extends StatelessWidget {
  const _NewBooksHero({
    required this.books,
    required this.services,
    required this.pad,
    required this.wide,
  });

  final List<Book> books;
  final ReaderServices services;
  final double pad;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final single = books.length == 1;
    final height = wide ? 300.0 : 236.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 28, pad - 8, 16),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'New in your Drive',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (!single) ...[
                const SizedBox(width: 10),
                Text(
                  '${books.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: () => services.newBooks.dismiss(books),
                child: Text(single ? 'Dismiss' : 'Dismiss all'),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final full = box.maxWidth - 2 * pad;
            // Several books: show a sliver of the next card as a hint.
            final width = single
                ? full
                : (wide ? 620.0 : full - 32).clamp(0.0, full);
            return SizedBox(
              height: height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                clipBehavior: Clip.none,
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 20),
                itemBuilder: (context, i) => SizedBox(
                  width: width,
                  child: _NewBookCard(
                    book: books[i],
                    services: services,
                    wide: wide,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NewBookCard extends StatelessWidget {
  const _NewBookCard({
    required this.book,
    required this.services,
    required this.wide,
  });

  final Book book;
  final ReaderServices services;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = services.meta[book.driveFileId];
    final author = services.meta.authorOf(book);
    final description = meta?.description ?? '';
    final details = [
      book.format.label,
      if (meta?.published.isNotEmpty ?? false) meta!.published.split('-').first,
      if (meta?.pageCount != null) '${meta!.pageCount} pages',
    ].join(' · ');
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(24),
      color: theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: () => showBookSheet(context, book, services),
        child: Padding(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Row(
            children: [
              BookCover(book: book, services: services),
              SizedBox(width: wide ? 28 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      services.meta.titleOf(book),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: wide
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleLarge,
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Flexible(
                        child: Text(
                          description,
                          maxLines: wide ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Flexible(
                          child: FilledButton(
                            onPressed: () => openBook(context, book, services),
                            child: Text(
                              wide ? 'Start reading' : 'Read',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Not interested',
                          icon: const Icon(Icons.close),
                          onPressed: () => services.newBooks.dismiss([book]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The book you're reading, on phones and narrow windows where there's no
/// side panel.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.services,
    required this.wide,
  });

  final Book book;
  final ReaderServices services;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = services.meta.authorOf(book);
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openBook(context, book, services),
        onLongPress: () => showBookSheet(context, book, services),
        child: Padding(
          padding: EdgeInsets.all(wide ? 28 : 20),
          child: Row(
            children: [
              BookCover(book: book, services: services, width: wide ? 150 : 96),
              SizedBox(width: wide ? 32 : 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      services.meta.titleOf(book),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: wide
                          ? theme.textTheme.headlineMedium
                          : theme.textTheme.titleLarge,
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        author,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    PagesRead(book: book, services: services),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progressOf(book, services) ?? 0,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled, horizontally scrolling row of large covers with the title and
/// author underneath each.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.books,
    required this.services,
    required this.pad,
    required this.wide,
  });

  final String title;
  final List<Book> books;
  final ReaderServices services;
  final double pad;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverWidth = wide ? 156.0 : 112.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 36, pad, 20),
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        SizedBox(
          height: coverWidth / coverAspectRatio + 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            clipBehavior: Clip.none,
            itemCount: books.length,
            separatorBuilder: (_, _) => SizedBox(width: wide ? 40 : 24),
            itemBuilder: (context, i) => SizedBox(
              width: coverWidth,
              child: ShelfBook(book: books[i], services: services),
            ),
          ),
        ),
      ],
    );
  }
}

/// Raised on Home when the library has duplicates the user hasn't
/// dismissed: deletes every extra identical copy in one go, or opens the
/// Duplicates screen to review the rest.
class _DuplicatesBanner extends StatefulWidget {
  const _DuplicatesBanner({
    required this.groups,
    required this.controller,
    required this.services,
  });

  final List<DuplicateGroup> groups;
  final LibraryController controller;
  final ReaderServices services;

  @override
  State<_DuplicatesBanner> createState() => _DuplicatesBannerState();
}

class _DuplicatesBannerState extends State<_DuplicatesBanner> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = widget.groups;
    final extras = [for (final g in groups) ...g.suggested];
    final formats = groups.where((g) => !g.identical).length;
    final bytes = extras.fold<int>(0, (sum, b) => sum + (b.sizeBytes ?? 0));
    String plural(int n, String one, String many) => n == 1 ? one : many;
    final lines = [
      if (extras.isNotEmpty)
        '${extras.length} identical extra '
            '${plural(extras.length, 'copy', 'copies')}'
            '${bytes > 0 ? ' (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)' : ''}',
      if (formats > 0)
        '$formats ${plural(formats, 'book', 'books')} in more than one format',
    ];
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_copy_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Duplicates found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.services.duplicates.dismiss(groups),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 8),
              child: Text(lines.join(' and ')),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (extras.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep_outlined),
                    label: Text(
                      'Delete ${extras.length} extra '
                      '${plural(extras.length, 'copy', 'copies')}',
                    ),
                    onPressed: _deleting
                        ? null
                        : () async {
                            await confirmAndDelete(
                              context,
                              extras,
                              widget.services,
                              onConfirmed: () =>
                                  setState(() => _deleting = true),
                            );
                            if (mounted) setState(() => _deleting = false);
                          },
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          DuplicatesScreen(controller: widget.controller),
                    ),
                  ),
                  child: const Text('Review'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
