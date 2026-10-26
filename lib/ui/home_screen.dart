import 'package:flutter/material.dart';

import '../library/book.dart';
import '../library/library_controller.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'book_sheet.dart';
import 'breakpoints.dart';
import 'library_screen.dart';

/// The first screen, like Apple Books' Home: the book you're reading, then
/// shelves of recent, downloaded and newly added books.
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
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final pad = wide ? 32.0 : 16.0;
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

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, wide ? 32 : 16, 0, 32),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Text('Home', style: largeTitle(context)),
          ),
          const SizedBox(height: 20),
          if (fresh.isNotEmpty) ...[
            _NewBooksHero(
              books: fresh,
              services: services,
              pad: pad,
              wide: wide,
            ),
            const SizedBox(height: 28),
          ],
          if (current != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _ContinueCard(
                book: current,
                services: services,
                wide: wide,
              ),
            )
          else if (books.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: const Text('Pick a book from your library to start.'),
            ),
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
        ],
      ),
    );
  }
}

/// The hero at the top of Home for books that recently arrived in Drive.
/// One new book fills the width; several scroll sideways.
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
          padding: EdgeInsets.fromLTRB(pad, 0, pad - 8, 8),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  single
                      ? 'NEW IN YOUR DRIVE'
                      : 'NEW IN YOUR DRIVE · ${books.length}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
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
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
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
      borderRadius: BorderRadius.circular(20),
      // A warm wash of the accent colour sets the hero apart.
      color: Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.10),
        theme.colorScheme.surfaceContainerLow,
      ),
      child: InkWell(
        onTap: () => showBookSheet(context, book, services),
        child: Padding(
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Row(
            children: [
              BookCover(book: book, services: services),
              SizedBox(width: wide ? 24 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      services.meta.titleOf(book),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (wide
                                  ? theme.textTheme.headlineSmall
                                  : theme.textTheme.titleLarge)
                              ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (author.isNotEmpty)
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(details, style: theme.textTheme.bodySmall),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Flexible(
                        child: Text(
                          description,
                          maxLines: wide ? 4 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.menu_book),
                          label: const Text('Read'),
                          onPressed: () => openBook(context, book, services),
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

/// The large "Continue reading" card at the top of Home.
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
    final fraction = progressOf(book, services) ?? 0;
    final author = services.meta.authorOf(book);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openBook(context, book, services),
        onLongPress: () => showBookSheet(context, book, services),
        child: Padding(
          padding: EdgeInsets.all(wide ? 28 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCover(
                book: book,
                services: services,
                width: wide ? 170 : 110,
              ),
              SizedBox(width: wide ? 32 : 18),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CONTINUE READING',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          services.meta.titleOf(book),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (wide
                                      ? theme.textTheme.headlineMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(fontWeight: FontWeight.w700),
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
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(progressLabel(book, services)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          icon: const Icon(Icons.menu_book),
                          label: const Text('Resume'),
                          onPressed: () => openBook(context, book, services),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled, horizontally scrolling row of covers.
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
    final coverWidth = wide ? 140.0 : 104.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 36, pad, 12),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: coverWidth / coverAspectRatio + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: books.length,
            separatorBuilder: (_, _) => SizedBox(width: wide ? 24 : 16),
            itemBuilder: (context, i) => SizedBox(
              width: coverWidth,
              child: LibraryBookTile(book: books[i], services: services),
            ),
          ),
        ),
      ],
    );
  }
}
