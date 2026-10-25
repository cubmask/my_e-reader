import 'package:flutter/material.dart';

import '../core/book_format.dart';
import '../library/book.dart';
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
          LibraryStatus.ready => _buildLibrary(context, c.books),
        };
      },
    );
  }

  Widget _buildLibrary(BuildContext context, List<Book> books) {
    final present = {for (final b in books) b.format}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final q = _query.toLowerCase();
    final shown = books
        .where((b) => _format == null || b.format == _format)
        .where((b) => q.isEmpty || b.displayTitle.toLowerCase().contains(q))
        .toList();

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
                      hintText: 'Search titles',
                      leading: const Icon(Icons.search),
                      onChanged: (v) => setState(() => _query = v),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.services});

  final Book book;
  final ReaderServices? services;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
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
            book.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (book.folderPath.isNotEmpty)
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
