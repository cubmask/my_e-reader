import 'package:flutter/material.dart';

import 'library/library_controller.dart';
import 'ui/home_shell.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My E-Reader',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeShell(controller: controller),
    );
  }

  /// A calm, Apple Books-like look: plain white (or black) pages, an orange
  /// accent, rounded controls and no tinted surfaces.
  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF9500),
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          surface: dark ? Colors.black : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xFF1C1C1E)
              : const Color(0xFFF5F5F7),
          surfaceContainerHigh: dark
              ? const Color(0xFF2C2C2E)
              : const Color(0xFFEDEDF0),
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
    );
  }
}
