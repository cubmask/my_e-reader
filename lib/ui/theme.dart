import 'package:flutter/material.dart';

/// The bundled faces: an elegant serif for headings and a clean geometric
/// sans for everything else.
abstract final class AppFonts {
  static const serif = 'Newsreader';
  static const sans = 'Montserrat';
}

/// Warm paper colours with a coral accent, in light and dark.
abstract final class AppColors {
  static const coral = Color(0xFFD9625D);
  static const coralDark = Color(0xFFE8857F);

  /// Near-black ink, used for text and the main buttons.
  static const ink = Color(0xFF23262D);
  static const inkDark = Color(0xFFEDE9E1);
}

/// The app's look: cream pages, serif headings, dark pill buttons and a
/// coral accent for the current item.
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? AppColors.inkDark : AppColors.ink;
  final coral = dark ? AppColors.coralDark : AppColors.coral;
  final canvas = dark ? const Color(0xFF1B1A18) : const Color(0xFFF0EDE5);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.coral,
        brightness: brightness,
      ).copyWith(
        primary: coral,
        onPrimary: Colors.white,
        primaryContainer: coral.withValues(alpha: dark ? 0.28 : 0.16),
        onPrimaryContainer: ink,
        secondary: ink,
        onSecondary: canvas,
        surface: canvas,
        onSurface: ink,
        onSurfaceVariant: dark
            ? const Color(0xFFADA89E)
            : const Color(0xFF6E6B65),
        // The lighter side panel, like a page laid on the desk.
        surfaceContainerLowest: dark
            ? const Color(0xFF232220)
            : const Color(0xFFFAF9F5),
        surfaceContainerLow: dark
            ? const Color(0xFF262522)
            : const Color(0xFFE9E5DB),
        surfaceContainer: dark
            ? const Color(0xFF2A2926)
            : const Color(0xFFE6E2D7),
        surfaceContainerHigh: dark
            ? const Color(0xFF302E2B)
            : const Color(0xFFE2DDD1),
        outline: dark ? const Color(0xFF6A665E) : const Color(0xFFB9B3A6),
        outlineVariant: dark
            ? const Color(0xFF3A3834)
            : const Color(0xFFDCD7CB),
        surfaceTint: Colors.transparent,
      );

  final base = ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: AppFonts.sans,
  );
  TextStyle? serif(TextStyle? s, double size) => s?.copyWith(
    fontFamily: AppFonts.serif,
    fontSize: size,
    fontWeight: FontWeight.w500,
    height: 1.12,
    letterSpacing: -0.4,
    color: ink,
  );
  final text = base.textTheme;
  final textTheme = text.copyWith(
    displayLarge: serif(text.displayLarge, 64),
    displayMedium: serif(text.displayMedium, 52),
    displaySmall: serif(text.displaySmall, 44),
    headlineLarge: serif(text.headlineLarge, 40),
    headlineMedium: serif(text.headlineMedium, 32),
    headlineSmall: serif(text.headlineSmall, 26),
    titleLarge: serif(text.titleLarge, 24),
  );
  final pill = WidgetStatePropertyAll<OutlinedBorder>(const StadiumBorder());

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: canvas,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: coral,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Colors.white : ink,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? ink.withValues(alpha: 0.12)
              : ink,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? ink.withValues(alpha: 0.38)
              : canvas,
        ),
        shape: pill,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: AppFonts.sans,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: pill,
        foregroundColor: WidgetStatePropertyAll(ink),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(coral)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: coral,
      linearTrackColor: scheme.outlineVariant,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: coral,
      thumbColor: coral,
      inactiveTrackColor: scheme.outlineVariant,
      trackHeight: 3,
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: Colors.transparent,
      selectedColor: ink,
      checkmarkColor: canvas,
      labelStyle: textTheme.labelLarge?.copyWith(color: ink),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(color: canvas),
      iconTheme: IconThemeData(color: ink, size: 18),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
      hintStyle: WidgetStatePropertyAll(
        TextStyle(color: scheme.onSurfaceVariant, fontFamily: AppFonts.sans),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// A round, quiet icon button used beside the main action, like the
/// bookmark, share and download buttons in the book page.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.size = 48,
  });

  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: IconButton.styleFrom(
        fixedSize: Size.square(size),
        backgroundColor: selected
            ? scheme.primary
            : scheme.surfaceContainerLow.withValues(alpha: 0.7),
        foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
      ),
    );
  }
}
