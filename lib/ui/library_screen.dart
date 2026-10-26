import 'package:flutter/material.dart';

import '../core/book_format.dart';
import '../library/book.dart';
import '../library/book_meta_store.dart';
import '../library/library_controller.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_services.dart';

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
            listenable: c.services?.meta ?? c,
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
    final shown = books
        .where((b) => _format == null || b.format == _format)
        .where(
          (b) =>
              _collection == null ||
              (meta?.collectionsOf(b).contains(_collection) ?? false),
        )
        .where(matches)
        .toList();
    if (meta != null) {
      shown.sort(
        (a, b) => meta
            .titleOf(a)
            .toLowerCase()
            .compareTo(meta.titleOf(b).toLowerCase()),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Text(
                    'Library',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${books.length} books',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 280,
                    child: SearchBar(
                      hintText: 'Search titles and authors',
                      leading: const Icon(Icons.search),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (collections.isNotEmpty && meta != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.collections_bookmark_outlined),
                      label: const Text('All books'),
                      selected: _collection == null,
                      onSelected: (_) => setState(() => _collection = null),
                    ),
                    for (final name in collections)
                      GestureDetector(
                        onLongPress: () => _manageCollection(meta, name),
                        onSecondaryTap: () => _manageCollection(meta, name),
                        child: ChoiceChip(
                          label: Text(name),
                          selected: _collection == name,
                          onSelected: (_) => setState(() => _collection = name),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _format == null,
                    onSelected: (_) => setState(() => _format = null),
                  ),
                  for (final f in present)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _format == f,
                      onSelected: (_) => setState(() => _format = f),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.62,
                crossAxisSpacing: 20,
                mainAxisSpacing: 24,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) => _BookCard(
                book: shown[i],
                services: widget.controller.services,
                onEdit: meta == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            BookDetailsDialog(book: shown[i], meta: meta),
                      ),
              ),
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

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.services, this.onEdit});

  final Book book;
  final ReaderServices? services;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = services?.meta;
    final author = meta?.authorOf(book) ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onLongPress: onEdit,
      onSecondaryTap: onEdit,
      onTap: services == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReaderScreen(book: book, services: services!),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(8),
              child: Chip(
                label: Text(book.format.label),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta?.titleOf(book) ?? book.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (book.folderPath.isNotEmpty)
            Text(
              book.folderPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
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
