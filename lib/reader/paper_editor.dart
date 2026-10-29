import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reader_settings.dart';

/// The papers to read on: the built-in three, the reader's own, and a
/// button to make another. Long-press one of your own to edit or delete it.
class PaperPicker extends StatelessWidget {
  const PaperPicker({super.key, required this.settings});

  final ReaderSettings settings;

  Future<void> _edit(BuildContext context, {int? index}) async {
    final paper = await showDialog<Paper>(
      context: context,
      builder: (context) =>
          PaperEditor(initial: index == null ? null : settings.papers[index]),
    );
    if (paper != null) await settings.savePaper(paper, index: index);
  }

  Future<void> _menu(BuildContext context, int index, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit paper')),
        PopupMenuItem(value: 'delete', child: Text('Delete paper')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'edit':
        await _edit(context, index: index);
      case 'delete':
        await settings.deletePaper(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final custom = settings.customPaper;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final MapEntry(key: theme, value: paper) in Paper.builtIn.entries)
          PaperSwatch(
            paper: paper,
            selected: custom == null && settings.theme == theme,
            onTap: () => settings.setTheme(theme),
          ),
        for (final (i, paper) in settings.papers.indexed)
          GestureDetector(
            onLongPressStart: (d) => _menu(context, i, d.globalPosition),
            child: PaperSwatch(
              paper: paper,
              selected: custom == i,
              onTap: () => settings.usePaper(i),
            ),
          ),
        Tooltip(
          message: 'Make a paper',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _edit(context),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1.5,
                ),
              ),
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }
}

/// A round sample of a paper: "Aa" in its ink, with its name below.
class PaperSwatch extends StatelessWidget {
  const PaperSwatch({
    super.key,
    required this.paper,
    required this.selected,
    required this.onTap,
  });

  final Paper paper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: '${paper.name} paper',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: paper.page,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Text(
                  'Aa',
                  style: TextStyle(
                    color: paper.text,
                    fontSize: 18,
                    fontFamily: 'serif',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                paper.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Makes or changes a paper: its page and text colours, chosen by hue,
/// intensity and lightness or typed as hex, and a name. The contrast ratio
/// warns when text would be hard to read.
class PaperEditor extends StatefulWidget {
  const PaperEditor({super.key, this.initial});

  /// The paper to change, or null to make a new one.
  final Paper? initial;

  @override
  State<PaperEditor> createState() => _PaperEditorState();
}

class _PaperEditorState extends State<PaperEditor> {
  late Paper _paper = widget.initial ?? Paper.starters.first;
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  final _hex = TextEditingController();
  bool _editingText = false;

  Color get _color => _editingText ? _paper.text : _paper.page;

  @override
  void initState() {
    super.initState();
    _showHex();
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _showHex() => _hex.text = cssColor(_color).substring(1).toUpperCase();

  void _setColor(Color color, {bool fromHex = false}) {
    setState(() {
      _paper = _editingText
          ? _paper.copyWith(text: color)
          : _paper.copyWith(page: color);
    });
    if (!fromHex) _showHex();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hsl = HSLColor.fromColor(_color);
    final contrast = _paper.contrast;
    final hard = contrast < 4.5;
    Widget slider(
      String label,
      double value,
      double max,
      HSLColor Function(double) apply,
    ) => Row(
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            onChanged: (v) => _setColor(apply(v).toColor()),
          ),
        ),
      ],
    );
    return AlertDialog(
      title: Text(widget.initial == null ? 'New paper' : 'Edit paper'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _paper.page,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(
                  'It was the best of times, it was the worst of times, it '
                  'was the age of wisdom, it was the age of foolishness.',
                  style: TextStyle(
                    color: _paper.text,
                    fontSize: 16,
                    height: 1.5,
                    fontFamily: 'serif',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Contrast ${contrast.toStringAsFixed(1)} to 1'
                '${hard ? ' · Hard to read' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hard ? theme.colorScheme.error : null,
                ),
              ),
              if (widget.initial == null) ...[
                const SizedBox(height: 16),
                Text('Start from', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final starter in Paper.starters)
                      ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: starter.page),
                        label: Text(starter.name),
                        selected:
                            _paper.page == starter.page &&
                            _paper.text == starter.text,
                        onSelected: (_) {
                          setState(() => _paper = starter);
                          _showHex();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Page')),
                  ButtonSegment(value: true, label: Text('Text')),
                ],
                selected: {_editingText},
                onSelectionChanged: (v) {
                  setState(() => _editingText = v.first);
                  _showHex();
                },
              ),
              const SizedBox(height: 8),
              slider('Hue', hsl.hue, 360, hsl.withHue),
              slider('Intensity', hsl.saturation, 1, hsl.withSaturation),
              slider('Lightness', hsl.lightness, 1, hsl.withLightness),
              TextField(
                controller: _hex,
                decoration: const InputDecoration(
                  labelText: 'Hex',
                  prefixText: '#',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (text) {
                  if (text.length == 6) {
                    _setColor(
                      Color(0xFF000000 | int.parse(text, radix: 16)),
                      fromHex: true,
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            Navigator.pop(
              context,
              _paper.copyWith(name: name.isEmpty ? _paper.name : name),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
