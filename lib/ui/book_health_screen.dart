import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/book.dart';
import '../library/book_health.dart';
import '../library/library_controller.dart';
import '../reader/reader_services.dart';
import 'book_cover.dart';
import 'book_sheet.dart' show showBookSheet;

/// "3 found", "None found" or "Not checked yet", for the settings entry.
String bookHealthSummary(LibraryController controller) {
  final health = controller.services?.health;
  if (health == null) return '';
  final found = health.problemsIn(controller.books).length;
  if (found == 0 && health.lastScan == null) return 'Not checked yet';
  return switch (found) {
    0 => 'None found',
    1 => '1 book will not open',
    final n => '$n books will not open',
  };
}

/// Checks every book in the library and lists the ones that will not open,
/// grouped by why.
class BookHealthScreen extends StatelessWidget {
  const BookHealthScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    final services = controller.services;
    if (services == null) return const Scaffold();
    final health = services.health;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, health, services.meta]),
      builder: (context, _) {
        final problems = health.problemsIn(controller.books);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Books that won\'t open'),
            actions: [
              if (problems.isNotEmpty)
                IconButton(
                  tooltip: 'Copy the list',
                  icon: const Icon(Icons.copy_all_outlined),
                  onPressed: () => _copy(context, services, problems),
                ),
              PopupMenuButton<void>(
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: !health.scanning,
                    onTap: () => health.scan(controller.books, all: true),
                    child: const Text('Check every book again'),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _ScanCard(health: health, books: controller.books),
              if (problems.isEmpty && health.lastScan != null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Every book should open.')),
                ),
              for (final kind in ProblemKind.values)
                if (problems.where((p) => p.$2.kind == kind).toList()
                    case final group when group.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                    child: Text(
                      '${kind.label} (${group.length})',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final (book, problem) in group)
                    _ProblemTile(
                      book: book,
                      problem: problem,
                      services: services,
                    ),
                ],
            ],
          ),
        );
      },
    );
  }

  void _copy(
    BuildContext context,
    ReaderServices services,
    List<(Book, BookProblem)> problems,
  ) {
    final text = [
      for (final (book, problem) in problems)
        '${services.meta.titleOf(book)}\n'
            '  ${[if (book.folderPath.isNotEmpty) book.folderPath, book.fileName].join('/')}\n'
            '  ${problem.kind.label}: ${problem.message}',
    ].join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Copied ${problems.length} books')));
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.health, required this.books});

  final BookHealth health;
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final todo = health.unchecked(books).length;
    final last = health.lastScan;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Each book is checked by reading a little from the start and '
              'end of its file in Google Drive. Books that fail in the reader '
              'are listed here too.',
              style: muted,
            ),
            const SizedBox(height: 16),
            if (health.scanning) ...[
              LinearProgressIndicator(
                value: health.total == 0 ? null : health.done / health.total,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text('Checked ${health.done} of ${health.total}'),
                  ),
                  TextButton(onPressed: health.stop, child: const Text('Stop')),
                ],
              ),
            ] else ...[
              FilledButton.icon(
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(switch (todo) {
                  0 => 'Every book is checked',
                  _ when last == null => 'Check all $todo books',
                  1 => 'Check 1 new or changed book',
                  _ => 'Check $todo new or changed books',
                }),
                onPressed: todo == 0 ? null : () => health.scan(books),
              ),
              if (last != null) ...[
                const SizedBox(height: 8),
                Text('Last checked ${_date(last)}', style: muted),
              ],
            ],
            if (health.skipped > 0 && !health.scanning) ...[
              const SizedBox(height: 8),
              Text(
                health.skipped == 1
                    ? '1 book could not be checked this time.'
                    : '${health.skipped} books could not be checked this time.',
                style: muted,
              ),
            ],
            if (health.scanError case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')} '
    '${'${d.hour}'.padLeft(2, '0')}:${'${d.minute}'.padLeft(2, '0')}';

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({
    required this.book,
    required this.problem,
    required this.services,
  });

  final Book book;
  final BookProblem problem;
  final ReaderServices services;

  @override
  Widget build(BuildContext context) {
    final where = [
      if (book.folderPath.isNotEmpty) book.folderPath,
      book.fileName,
    ].join('/');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: BookCover(book: book, services: services, width: 36),
      title: Text(
        services.meta.titleOf(book),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$where\n${problem.message}'),
      isThreeLine: true,
      onTap: () => showBookSheet(context, book, services),
    );
  }
}
