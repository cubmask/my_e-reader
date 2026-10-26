import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/library_controller.dart';
import '../notes/annotation_store.dart';
import '../reader/reader_screen.dart';
import 'library_screen.dart' show largeTitle;

/// Every highlight, note and bookmark across the library.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = widget.controller.services;
    if (services == null) {
      return const Center(
        child: Text('Sign in to see your highlights and notes.'),
      );
    }
    return ListenableBuilder(
      listenable: services.annotations,
      builder: (context, _) {
        final q = _query.toLowerCase();
        final items = services.annotations.all
            .where(
              (a) =>
                  q.isEmpty ||
                  a.text.toLowerCase().contains(q) ||
                  a.note.toLowerCase().contains(q) ||
                  a.bookTitle.toLowerCase().contains(q),
            )
            .toList();
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text('Notes', style: largeTitle(context)),
                    const SizedBox(width: 16),
                    Text('${items.length}'),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy as Markdown',
                      icon: const Icon(Icons.copy_all),
                      onPressed: items.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(
                                ClipboardData(
                                  text: annotationsToMarkdown(items),
                                ),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied as Markdown'),
                                ),
                              );
                            },
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 280,
                      child: SearchBar(
                        hintText: 'Search notes',
                        leading: const Icon(Icons.search),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Highlights and notes from all your books will appear '
                    'here. Select text while reading to add one.',
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => AnnotationTile(
                  annotation: items[i],
                  subtitle: items[i].bookTitle,
                  onTap: () => _open(items[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  void _open(Annotation a) {
    final services = widget.controller.services!;
    final book = widget.controller.books
        .where((b) => b.driveFileId == a.bookId)
        .firstOrNull;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${a.bookTitle}" is not in the library now.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ReaderScreen(book: book, services: services, openAt: a.location),
      ),
    );
  }
}
