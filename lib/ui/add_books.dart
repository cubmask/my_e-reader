import 'package:flutter/material.dart';

import '../core/platform_bridge.dart';
import '../library/book_uploader.dart';
import '../library/library_controller.dart';
import 'book_sheet.dart' show openBook;

/// Lets the user pick books on the device and adds them to the library.
Future<void> pickAndAddBooks(
  BuildContext context,
  LibraryController controller,
) async {
  final files = await PlatformBridge.instance.pickBooks();
  if (files.isEmpty || !context.mounted) return;
  await addBooks(context, controller, files);
}

/// Uploads [files] to the library with a progress dialog, then says what
/// happened. When [open] is set and there is one book, it opens, whether
/// it was added now or was already there.
Future<void> addBooks(
  BuildContext context,
  LibraryController controller,
  List<IncomingFile> files, {
  bool open = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (controller.status != LibraryStatus.ready) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Sign in and choose your library folder first.'),
      ),
    );
    for (final f in files) {
      await f.file.delete().catchError((_) => f.file);
    }
    return;
  }
  final progress = ValueNotifier<(int, int)>((0, files.length));
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 24),
              Expanded(
                child: Text(
                  value.$2 == 1
                      ? 'Adding to your library…'
                      : 'Adding ${value.$1 + 1} of ${value.$2}…',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  List<UploadResult> results;
  try {
    results = await controller.addBooks(
      files,
      onProgress: (done, total) => progress.value = (done, total),
    );
  } catch (e) {
    navigator.pop();
    progress.dispose();
    messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
    return;
  }
  navigator.pop();
  progress.dispose();
  final added = results.where((r) => r.skipped == null).length;
  final there = results.where((r) => r.skipped == UploadSkip.alreadyThere);
  final notBooks = results.where((r) => r.skipped == UploadSkip.notABook);
  final services = controller.services;
  final single = results.length == 1 ? results.single.book : null;
  if (open && single != null && services != null && context.mounted) {
    openBook(context, single, services);
  }
  final parts = [
    if (added > 0) 'Added $added ${added == 1 ? 'book' : 'books'}',
    if (there.isNotEmpty)
      there.length == 1 && results.length == 1
          ? 'Already in your library'
          : '${there.length} already in your library',
    if (notBooks.isNotEmpty)
      notBooks.length == 1
          ? '"${notBooks.single.name}" is not a book file'
          : '${notBooks.length} files are not books',
  ];
  messenger.showSnackBar(SnackBar(content: Text(parts.join('. '))));
}
