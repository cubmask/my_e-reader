import 'package:flutter/material.dart';

import '../library/library_controller.dart';

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
