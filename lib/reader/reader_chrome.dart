import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../notes/annotation_store.dart';
import '../ui/theme.dart';

/// Highlight colours as drawn on the page and in lists.
const highlightSwatches = {
  HighlightColor.yellow: Color(0xFFF9D71C),
  HighlightColor.green: Color(0xFF5FD068),
  HighlightColor.blue: Color(0xFF4AA8FF),
  HighlightColor.pink: Color(0xFFFF6FAE),
};

/// A frosted pill that floats over the page, tinted like the paper so it
/// sits quietly on the book.
class FloatingPill extends StatelessWidget {
  const FloatingPill({
    super.key,
    required this.paper,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  final Color paper;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(40);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 30,
            offset: Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Material(
            color: Color.alphaBlend(
              Colors.white.withValues(
                alpha: paper.computeLuminance() > 0.5 ? 0.5 : 0.06,
              ),
              paper,
            ).withValues(alpha: 0.9),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// One button in the [ReaderToolbar].
class ToolbarItem {
  const ToolbarItem({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Drawn on a coral disc, like the current tab in the rail.
  final bool selected;
}

/// The reader's floating toolbar: a row of round icon buttons with the
/// reading position at the end.
class ReaderToolbar extends StatelessWidget {
  const ReaderToolbar({
    super.key,
    required this.paper,
    required this.items,
    this.trailing,
  });

  final Color paper;
  final List<ToolbarItem> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ink = _inkOn(paper);
    return FloatingPill(
      paper: paper,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: RoundToolButton(item: item, ink: ink),
            ),
          if (trailing case final trailing?) ...[
            Container(
              width: 1,
              height: 28,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: ink.withValues(alpha: 0.15),
            ),
            DefaultTextStyle.merge(
              style: TextStyle(color: ink, fontWeight: FontWeight.w500),
              child: IconTheme.merge(
                data: IconThemeData(color: ink),
                child: trailing,
              ),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class RoundToolButton extends StatelessWidget {
  const RoundToolButton({super.key, required this.item, required this.ink});

  final ToolbarItem item;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final coral = Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: item.tooltip,
      onPressed: item.onPressed,
      icon: Icon(item.icon),
      iconSize: 24,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(52),
        foregroundColor: item.selected ? Colors.white : ink,
        backgroundColor: item.selected ? coral : Colors.transparent,
      ),
    );
  }
}

/// The popover over selected text: copy, look up, share, read aloud,
/// highlight colours and a note.
class SelectionPopover extends StatelessWidget {
  const SelectionPopover({
    super.key,
    required this.paper,
    required this.onCopy,
    required this.onReadAloud,
    required this.onHighlight,
    required this.onNote,
    this.onLookUp,
    this.onShare,
  });

  final Color paper;
  final VoidCallback onCopy;
  final VoidCallback? onLookUp;
  final VoidCallback? onShare;
  final VoidCallback onReadAloud;
  final ValueChanged<HighlightColor> onHighlight;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) {
    final ink = _inkOn(paper);
    return FloatingPill(
      paper: paper,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundToolButton(
            ink: ink,
            item: ToolbarItem(
              icon: Icons.copy_outlined,
              tooltip: 'Copy',
              onPressed: onCopy,
            ),
          ),
          if (onLookUp != null)
            RoundToolButton(
              ink: ink,
              item: ToolbarItem(
                icon: Icons.menu_book_outlined,
                tooltip: 'Look up',
                onPressed: onLookUp,
              ),
            ),
          if (onShare != null)
            RoundToolButton(
              ink: ink,
              item: ToolbarItem(
                icon: Icons.share_outlined,
                tooltip: 'Share',
                onPressed: onShare,
              ),
            ),
          RoundToolButton(
            ink: ink,
            item: ToolbarItem(
              icon: Icons.volume_up_outlined,
              tooltip: 'Read aloud',
              selected: true,
              onPressed: onReadAloud,
            ),
          ),
          Container(
            width: 1,
            height: 28,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: ink.withValues(alpha: 0.15),
          ),
          for (final MapEntry(key: color, value: swatch)
              in highlightSwatches.entries)
            IconButton(
              tooltip: 'Highlight ${color.name}',
              onPressed: () => onHighlight(color),
              icon: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(color: ink.withValues(alpha: 0.12)),
                ),
              ),
            ),
          RoundToolButton(
            ink: ink,
            item: ToolbarItem(
              icon: Icons.edit_outlined,
              tooltip: 'Highlight with a note',
              onPressed: onNote,
            ),
          ),
        ],
      ),
    );
  }
}

Color _inkOn(Color paper) =>
    paper.computeLuminance() > 0.4 ? AppColors.ink : AppColors.inkDark;
