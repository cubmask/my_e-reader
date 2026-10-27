import 'package:flutter/material.dart';

import '../library/library_controller.dart';
import 'breakpoints.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';

/// Top-level navigation: a slim icon rail on tablets and desktops, a bottom
/// bar on phones.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final LibraryController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.import_contacts_outlined, Icons.import_contacts, 'Library'),
    (Icons.bookmark_border, Icons.bookmark, 'Notes'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final page = switch (_index) {
      0 => HomeScreen(controller: widget.controller),
      1 => LibraryScreen(controller: widget.controller),
      2 => NotesScreen(controller: widget.controller),
      _ => SettingsScreen(controller: widget.controller),
    };

    if (width < Breakpoints.medium) {
      return Scaffold(
        body: SafeArea(child: page),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          height: 68,
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

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            AppRail(
              selectedIndex: _index,
              onSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
            ),
            Expanded(child: page),
          ],
        ),
      ),
    );
  }
}

/// The icon rail down the left edge: the app mark at the top, the
/// destinations centred, and a coral disc behind the current one.
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, IconData, String)> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 112,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Icon(
              Icons.auto_stories_outlined,
              size: 34,
              color: scheme.onSurface,
            ),
            const Spacer(),
            for (final (i, (icon, selected, label)) in destinations.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Semantics(
                  selected: i == selectedIndex,
                  button: true,
                  child: IconButton(
                    tooltip: label,
                    iconSize: 28,
                    isSelected: i == selectedIndex,
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    style:
                        IconButton.styleFrom(
                          fixedSize: const Size.square(64),
                          foregroundColor: scheme.onSurface,
                          backgroundColor: Colors.transparent,
                        ).copyWith(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? scheme.primary
                                : Colors.transparent,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                    onPressed: () => onSelected(i),
                  ),
                ),
              ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}
