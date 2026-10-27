import 'package:flutter/material.dart';

import '../core/platform_bridge.dart';
import 'reader_settings.dart';

/// Reading appearance: theme, typography, layout and screen.
///
/// Sliders apply when let go, since restyling lays the chapter out again;
/// brightness follows the finger.
class AppearanceSheet extends StatefulWidget {
  const AppearanceSheet({
    super.key,
    required this.settings,
    required this.reflowable,
    this.scroll,
  });

  final ReaderSettings settings;

  /// Whether the book reflows (not a PDF or a comic), so type and layout
  /// settings apply.
  final bool reflowable;
  final ScrollController? scroll;

  @override
  State<AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<AppearanceSheet> {
  ReaderSettings get settings => widget.settings;
  double? _fontSize;
  double? _lineHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final fontSize = _fontSize ?? settings.fontSize.toDouble();
        final lineHeight = _lineHeight ?? settings.lineHeight;
        final brightness = settings.brightness;
        return ListView(
          controller: widget.scroll,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            SegmentedButton<ReaderTheme>(
              segments: const [
                ButtonSegment(value: ReaderTheme.light, label: Text('Light')),
                ButtonSegment(value: ReaderTheme.sepia, label: Text('Sepia')),
                ButtonSegment(value: ReaderTheme.dark, label: Text('Dark')),
              ],
              selected: {settings.theme},
              onSelectionChanged: (s) => settings.setTheme(s.first),
            ),
            if (PlatformBridge.instance.available) ...[
              heading('Brightness'),
              Row(
                children: [
                  const Icon(Icons.brightness_low, size: 20),
                  Expanded(
                    child: Slider(
                      value: brightness ?? 0.5,
                      onChanged: (v) => settings.previewBrightness(v),
                      onChangeEnd: settings.saveBrightness,
                    ),
                  ),
                  const Icon(Icons.brightness_high, size: 20),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('System'),
                    selected: brightness == null,
                    onSelected: (on) =>
                        settings.saveBrightness(on ? null : 0.5),
                  ),
                ],
              ),
            ],
            if (widget.reflowable) ...[
              heading('Text size ${fontSize.round()}%'),
              Slider(
                min: ReaderSettings.minFont.toDouble(),
                max: ReaderSettings.maxFont.toDouble(),
                divisions: 13,
                value: fontSize,
                label: '${fontSize.round()}%',
                onChanged: (v) => setState(() => _fontSize = v),
                onChangeEnd: (v) {
                  _fontSize = null;
                  settings.setFontSize(v.round());
                },
              ),
              heading('Font'),
              SegmentedButton<ReaderFont>(
                showSelectedIcon: false,
                segments: [
                  for (final f in ReaderFont.values)
                    ButtonSegment(
                      value: f,
                      label: Text(
                        f.label,
                        style: TextStyle(
                          fontFamily: switch (f) {
                            ReaderFont.serif => 'serif',
                            ReaderFont.mono => 'monospace',
                            _ => null,
                          },
                        ),
                      ),
                    ),
                ],
                selected: {settings.font},
                onSelectionChanged: (s) => settings.setFont(s.first),
              ),
              heading('Line spacing ${lineHeight.toStringAsFixed(1)}'),
              Slider(
                min: ReaderSettings.minLineHeight,
                max: ReaderSettings.maxLineHeight,
                divisions: 10,
                value: lineHeight,
                label: lineHeight.toStringAsFixed(1),
                onChanged: (v) => setState(() => _lineHeight = v),
                onChangeEnd: (v) {
                  _lineHeight = null;
                  settings.setLineHeight(v);
                },
              ),
              heading('Margins'),
              SegmentedButton<ReaderMargins>(
                segments: [
                  for (final m in ReaderMargins.values)
                    ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {settings.margins},
                onSelectionChanged: (s) => settings.setMargins(s.first),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Justify text'),
                value: settings.justify,
                onChanged: settings.setJustify,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Scroll instead of turning pages'),
                value: settings.scrolled,
                onChanged: settings.setScrolled,
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Two pages side by side'),
              subtitle: const Text('On a wide screen held sideways'),
              value: settings.spread,
              onChanged: settings.setSpread,
            ),
            if (PlatformBridge.instance.available)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Keep the screen on'),
                value: settings.keepAwake,
                onChanged: settings.setKeepAwake,
              ),
          ],
        );
      },
    );
  }
}
