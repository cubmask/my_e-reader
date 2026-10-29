import 'package:flutter/material.dart';

import '../reader/ask.dart';

/// Questions about the page the reader is on, answered by their own model.
///
/// Only the pages around the reading position go with a question, so the
/// answer can't give away the ending. Nothing is kept once the sheet
/// closes.
class AskSheet extends StatefulWidget {
  const AskSheet({
    super.key,
    required this.settings,
    required this.client,
    required this.title,
    required this.author,
    required this.where,
    required this.passage,
    this.selection,
    this.scroll,
  });

  final AskSettings settings;
  final AskClient client;
  final String title;
  final String author;

  /// Where the reader is, such as "Chapter 3, 40% through the book".
  final String where;

  /// The text around the reading position, as much as [AskContext] says.
  final Future<String> Function(AskContext context) passage;

  /// Words the reader selected, which go with every question.
  final String? selection;
  final ScrollController? scroll;

  @override
  State<AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<AskSheet> {
  final _field = TextEditingController();
  final _turns = <AskTurn>[];
  String? _asking;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  List<String> get _suggestions => widget.selection == null
      ? const [
          'Explain this page',
          'What happens on this page?',
          'Who are the people here?',
        ]
      : const ['Explain this passage', 'What does this mean here?'];

  /// The first question to a provider or server says where the words go,
  /// and asks once.
  Future<bool> _agree(String passage) async {
    final s = widget.settings;
    if (s.allowed) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Before your first question'),
        content: Text(
          'Your question, the book\'s title and about '
          '${wordCount(passage)} words from around this page will be sent '
          'to ${s.address} (${s.provider!.label}, model ${s.model}). '
          '${s.provider == AskProvider.ollama ? '' : 'It is billed to your account. '}'
          'Nothing else from the book or your library is sent. You can '
          'withdraw this in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await s.allow();
    return true;
  }

  Future<void> _ask(String question) async {
    question = question.trim();
    if (question.isEmpty || _asking != null) return;
    final s = widget.settings;
    final passage = await widget.passage(s.context);
    if (!mounted) return;
    if (passage.trim().isEmpty) {
      setState(() => _error = 'There is no text on this page to ask about.');
      return;
    }
    if (!await _agree(passage) || !mounted) return;
    _field.clear();
    setState(() {
      _asking = question;
      _error = null;
    });
    try {
      final answer = await widget.client.ask(
        s,
        book: (
          title: widget.title,
          author: widget.author,
          where: widget.where,
          passage: passage,
          selection: widget.selection,
        ),
        question: question,
        // The last few exchanges, so follow-up questions make sense.
        history: _turns.length > 4
            ? _turns.sublist(_turns.length - 4)
            : List.of(_turns),
      );
      if (mounted) _turns.add((question: question, answer: answer));
    } on AskException catch (e) {
      if (mounted) _error = e.message;
    }
    if (mounted) setState(() => _asking = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget question(String text) => Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 16, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text),
      ),
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            children: [
              Text('Ask about this page', style: theme.textTheme.titleLarge),
              if (widget.selection case final selection?) ...[
                const SizedBox(height: 8),
                Text(
                  '“$selection”',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: quote,
                ),
              ],
              for (final t in _turns) ...[
                question(t.question),
                const SizedBox(height: 12),
                SelectableText(t.answer),
              ],
              if (_asking case final asking?) ...[
                question(asking),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_turns.isEmpty && _asking == null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(label: Text(s), onPressed: () => _ask(s)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Answers come from the pages around where you are, so they '
                  'won\'t give away what happens later.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              8 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: TextField(
              controller: _field,
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              decoration: InputDecoration(
                hintText: 'Ask a question',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Ask',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _asking == null ? () => _ask(_field.text) : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
