import 'package:flutter/material.dart';

import '../library/library_controller.dart';
import 'breakpoints.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';

/// Top-level navigation: a rail on tablets and desktops, a bottom bar on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.local_library_outlined, Icons.local_library, 'Library'),
    (Icons.sticky_note_2_outlined, Icons.sticky_note_2, 'Notes'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final page = switch (_index) {
      0 => LibraryScreen(controller: widget.controller),
      1 => NotesScreen(controller: widget.controller),
      _ => SettingsScreen(controller: widget.controller),
    };

    if (width < Breakpoints.medium) {
      return Scaffold(
        body: SafeArea(child: page),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      );
    }

    final extended = width >= Breakpoints.expanded;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              labelType: extended ? null : NavigationRailLabelType.all,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      ),
    );
  }
}
