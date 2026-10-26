import 'package:flutter/material.dart';

import '../library/library_controller.dart';
import '../reader/book_cache.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Library folder'),
            subtitle: Text(controller.folderId ?? 'Not set'),
          ),
          if (controller.services?.cache case final cache?)
            _StorageSection(cache: cache),
          if (controller.status != LibraryStatus.signedOut)
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out of Google'),
              onTap: controller.signOut,
            ),
        ],
      ),
    );
  }
}

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Space used by downloads and by temporarily streamed books.
class _StorageSection extends StatelessWidget {
  const _StorageSection({required this.cache});

  final BookCache cache;

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) => FutureBuilder(
        future: cache.usage(),
        builder: (context, snapshot) {
          final usage = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text('Storage', style: Theme.of(context).textTheme.titleMedium),
              ListTile(
                leading: const Icon(Icons.download_done),
                title: const Text('Downloaded books'),
                subtitle: Text(
                  usage == null
                      ? '...'
                      : '${_size(usage.downloads)} kept for offline reading',
                ),
                trailing: TextButton(
                  onPressed: usage == null || usage.downloads == 0
                      ? null
                      : () async {
                          if (await _confirm(
                            context,
                            'Remove all downloads?',
                            'Books will stream from Google Drive again. '
                                'Your progress, notes and highlights stay.',
                          )) {
                            await cache.removeAllDownloads();
                          }
                        },
                  child: const Text('Remove all'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Streaming cache'),
                subtitle: Text(
                  usage == null
                      ? '...'
                      : '${_size(usage.streams)} of recently opened books, '
                            'cleared automatically past '
                            '${_size(cache.streamMaxBytes)}',
                ),
                trailing: TextButton(
                  onPressed: usage == null || usage.streams == 0
                      ? null
                      : cache.clearStreams,
                  child: const Text('Clear'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
