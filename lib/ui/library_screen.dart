import 'package:flutter/material.dart';

import '../core/book_format.dart';
import '../library/book.dart';
import '../library/book_meta_store.dart';
import '../library/library_controller.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'book_sheet.dart';
import 'breakpoints.dart';
import 'duplicates_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  BookFormat? _format;
  String? _collection;
  bool _downloadedOnly = false;
  _Sort _sort = _Sort.recent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return switch (c.status) {
          LibraryStatus.signedOut => _Message(
            icon: Icons.cloud_outlined,
            text: 'Sign in with Google to open your Drive library.',
            action: FilledButton(
              onPressed: c.signIn,
              child: const Text('Sign in with Google'),
            ),
          ),
          LibraryStatus.needsFolder => _FolderPrompt(controller: c),
          LibraryStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          LibraryStatus.error => _Message(
            icon: Icons.error_outline,
            text: c.error ?? 'Something went wrong.',
            action: FilledButton(
              onPressed: c.folderId == null ? c.signIn : c.refresh,
              child: const Text('Try again'),
            ),
          ),
          LibraryStatus.ready => ListenableBuilder(
            listenable: Listenable.merge([
              c.services?.meta,
              c.services?.cache,
              c.services?.covers,
            ]),
            builder: (context, _) => _buildLibrary(context, c.books),
          ),
        };
      },
    );
  }

  Widget _buildLibrary(BuildContext context, List<Book> books) {
    final present = {for (final b in books) b.format}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final meta = widget.controller.services?.meta;
    final collections = meta?.collections ?? const <String>[];
    if (!collections.contains(_collection)) _collection = null;
    final q = _query.toLowerCase();
    bool matches(Book b) =>
        q.isEmpty ||
        (meta?.titleOf(b) ?? b.displayTitle).toLowerCase().contains(q) ||
        (meta?.authorOf(b) ?? '').toLowerCase().contains(q);
    final cache = widget.controller.services?.cache;
    final shown = books
        .where((b) => _format == null || b.format == _format)
        .where((b) => !_downloadedOnly || (cache?.isDownloaded(b) ?? false))
        .where(
          (b) =>
              _collection == null ||
              (meta?.collectionsOf(b).contains(_collection) ?? false),
        )
        .where(matches)
        .toList();
    String title(Book b) => (meta?.titleOf(b) ?? b.displayTitle).toLowerCase();
    String author(Book b) => (meta?.authorOf(b) ?? '').toLowerCase();
    DateTime opened(Book b) =>
        widget.controller.services?.progress[b.driveFileId]?.updatedAt ??
        DateTime(0);
    shown.sort(switch (_sort) {
      _Sort.recent => (a, b) {
        final byDate = opened(b).compareTo(opened(a));
        return byDate != 0 ? byDate : title(a).compareTo(title(b));
      },
      _Sort.title => (a, b) => title(a).compareTo(title(b)),
      _Sort.author => (a, b) {
        // Books without an author go last.
        final x = author(a), y = author(b);
        if (x.isEmpty != y.isEmpty) return x.isEmpty ? 1 : -1;
        final byAuthor = x.compareTo(y);
        return byAuthor != 0 ? byAuthor : title(a).compareTo(title(b));
      },
      _Sort.added => (a, b) => (b.modifiedTime ?? DateTime(0)).compareTo(
        a.modifiedTime ?? DateTime(0),
      ),
    });

    final services = widget.controller.services;
    final duplicates = duplicatesIn(widget.controller).length;
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final pad = wide ? 48.0 : 20.0;
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, wide ? 56 : 24, pad, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: Text(
                                'Library',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: largeTitle(context),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${books.length}'.padLeft(2, '0'),
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: books.length == 1
                                        ? ' book'
                                        : ' books',
                                  ),
                                ],
                              ),
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<_Sort>(
                        tooltip: 'Sort',
                        icon: const Icon(Icons.sort),
                        initialValue: _sort,
                        onSelected: (v) => setState(() => _sort = v),
                        itemBuilder: (_) => [
                          for (final v in _Sort.values)
                            CheckedPopupMenuItem(
                              value: v,
                              checked: v == _sort,
                              child: Text(v.label),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SearchBar(
                      hintText: 'Search book name, author …',
                      leading: const Icon(Icons.search),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Row(
                children: [
                  for (final chip in <Widget>[
                    ChoiceChip(
                      label: Text('All · ${books.length}'),
                      selected:
                          _format == null &&
                          _collection == null &&
                          !_downloadedOnly,
                      onSelected: (_) => setState(() {
                        _format = null;
                        _collection = null;
                        _downloadedOnly = false;
                      }),
                    ),
                    FilterChip(
                      avatar: const Icon(Icons.download_done),
                      label: const Text('Downloaded'),
                      selected: _downloadedOnly,
                      onSelected: (on) => setState(() => _downloadedOnly = on),
                    ),
                    if (duplicates > 0)
                      ActionChip(
                        avatar: const Icon(Icons.file_copy_outlined),
                        label: Text('Duplicates · $duplicates'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DuplicatesScreen(controller: widget.controller),
                          ),
                        ),
                      ),
                    if (meta != null)
                      for (final name in collections)
                        GestureDetector(
                          onLongPress: () => _manageCollection(meta, name),
                          onSecondaryTap: () => _manageCollection(meta, name),
                          child: ChoiceChip(
                            avatar: const Icon(
                              Icons.collections_bookmark_outlined,
                            ),
                            label: Text(name),
                            selected: _collection == name,
                            onSelected: (on) =>
                                setState(() => _collection = on ? name : null),
                          ),
                        ),
                    if (present.length > 1)
                      for (final f in present)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: _format == f,
                          onSelected: (on) =>
                              setState(() => _format = on ? f : null),
                        ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: chip,
                    ),
                ],
              ),
            ),
          ),
          if (shown.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No books match.')),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 24, pad, 32),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: wide ? 200 : 150,
                // Cover, title and author, and one status row.
                childAspectRatio: wide ? 0.47 : 0.44,
                crossAxisSpacing: wide ? 36 : 20,
                mainAxisSpacing: wide ? 36 : 24,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) =>
                  LibraryBookTile(book: shown[i], services: services),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manageCollection(BookMetaStore meta, String name) async {
    final field = TextEditingController(text: name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Collection'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    field.dispose();
    if (result == null) return;
    // Deleting a collection only removes the grouping, not the books.
    await meta.renameCollection(name, result);
    if (result.trim().isNotEmpty && _collection == name) {
      setState(() => _collection = result.trim());
    }
  }
}

enum _Sort {
  recent('Recently read'),
  title('Title'),
  author('Author'),
  added('Recently added');

  const _Sort(this.label);
  final String label;
}

/// The big serif page title used across the app.
TextStyle? largeTitle(BuildContext context) =>
    Theme.of(context).textTheme.displaySmall;

/// A cover on a Home shelf with its title and, in italics, its author.
/// Tap to read; long-press for the book's details.
class ShelfBook extends StatelessWidget {
  const ShelfBook({super.key, required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => openBook(context, book, services),
          onLongPress: () => showBookSheet(context, book, services),
          onSecondaryTap: () => showBookSheet(context, book, services),
          child: Semantics(
            button: true,
            label: services.meta.titleOf(book),
            child: BookCover(book: book, services: services),
          ),
        ),
        const SizedBox(height: 16),
        _TitleAndAuthor(book: book, services: services),
      ],
    );
  }
}

class _TitleAndAuthor extends StatelessWidget {
  const _TitleAndAuthor({required this.book, required this.services});

  final Book book;
  final ReaderServices? services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = services?.meta.authorOf(book) ?? '';
    // Always two lines tall, so covers in a row line up.
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.45,
    );
    return SizedBox(
      height: 2 * 1.45 * (style?.fontSize ?? 14) + 2,
      child: Text.rich(
        TextSpan(
          text: services?.meta.titleOf(book) ?? book.displayTitle,
          children: [
            if (author.isNotEmpty)
              TextSpan(
                text: '\n$author',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// A cover in the library grid, with its progress and a "more" button.
/// Tap to read; long-press or "more" for the book's details.
class LibraryBookTile extends StatelessWidget {
  const LibraryBookTile({
    super.key,
    required this.book,
    required this.services,
  });

  final Book book;
  final ReaderServices? services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = this.services;
    final cache = services?.cache;
    final label = progressLabel(book, services);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: services == null
                  ? null
                  : () => openBook(context, book, services),
              onLongPress: services == null
                  ? null
                  : () => showBookSheet(context, book, services),
              onSecondaryTap: services == null
                  ? null
                  : () => showBookSheet(context, book, services),
              child: Semantics(
                button: true,
                label: services?.meta.titleOf(book) ?? book.displayTitle,
                child: BookCover(book: book, services: services),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _TitleAndAuthor(book: book, services: services),
        SizedBox(
          height: 32,
          child: Row(
            children: [
              if (label == 'New')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'NEW',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 6),
              if (cache != null && cache.isDownloading(book))
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: cache.downloadProgress(book),
                  ),
                )
              else if (cache?.isDownloaded(book) ?? false)
                Tooltip(
                  message: 'Available offline',
                  child: Icon(
                    Icons.download_done,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const Spacer(),
              if (services != null)
                IconButton(
                  tooltip: 'More',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => showBookSheet(context, book, services),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Edits a book's title, author and collections. Opened by a long press (or
/// right click) on its card.
class BookDetailsDialog extends StatefulWidget {
  const BookDetailsDialog({super.key, required this.book, required this.meta});

  final Book book;
  final BookMetaStore meta;

  @override
  State<BookDetailsDialog> createState() => _BookDetailsDialogState();
}

class _BookDetailsDialogState extends State<BookDetailsDialog> {
  late final _title = TextEditingController(
    text: widget.meta.titleOf(widget.book),
  );
  late final _author = TextEditingController(
    text: widget.meta.authorOf(widget.book),
  );
  final _newCollection = TextEditingController();
  late final _all = {...widget.meta.collections};
  late final _chosen = {...widget.meta.collectionsOf(widget.book)};

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _newCollection.dispose();
    super.dispose();
  }

  void _add() {
    final name = _newCollection.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _all.add(name);
      _chosen.add(name);
      _newCollection.clear();
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    await widget.meta.set(
      widget.book.driveFileId,
      // Saving the file name unchanged keeps following the file name.
      title: title == widget.book.displayTitle ? '' : title,
      author: _author.text,
      collections: [
        for (final c in _all)
          if (_chosen.contains(c)) c,
      ],
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Book details'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _author,
                decoration: const InputDecoration(labelText: 'Author'),
              ),
              const SizedBox(height: 20),
              Text(
                'Collections',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _all)
                    FilterChip(
                      label: Text(c),
                      selected: _chosen.contains(c),
                      onSelected: (on) => setState(
                        () => on ? _chosen.add(c) : _chosen.remove(c),
                      ),
                    ),
                ],
              ),
              TextField(
                controller: _newCollection,
                decoration: InputDecoration(
                  labelText: 'New collection',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _add,
                  ),
                ),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 12),
              Text(
                widget.book.fileName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _FolderPrompt extends StatefulWidget {
  const _FolderPrompt({required this.controller});

  final LibraryController controller;

  @override
  State<_FolderPrompt> createState() => _FolderPromptState();
}

class _FolderPromptState extends State<_FolderPrompt> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.folder_open_outlined,
      text: 'Paste the link to your Google Drive books folder.',
      action: SizedBox(
        width: 480,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                decoration: const InputDecoration(
                  hintText: 'https://drive.google.com/drive/folders/...',
                ),
                onSubmitted: widget.controller.setFolder,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => widget.controller.setFolder(_field.text),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.action,
  });

  final IconData icon;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}
