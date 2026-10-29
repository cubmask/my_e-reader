import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../reader/ask.dart';

/// Settings for asking about the page: the reader's own API key or Ollama
/// server, the model, how much of the book goes with a question, and the
/// agreement to send it.
class AskSettingsSection extends StatefulWidget {
  const AskSettingsSection({
    super.key,
    required this.settings,
    required this.client,
  });

  final AskSettings settings;
  final AskClient client;

  @override
  State<AskSettingsSection> createState() => _AskSettingsSectionState();
}

class _AskSettingsSectionState extends State<AskSettingsSection> {
  AskSettings get s => widget.settings;
  List<String>? _models;
  bool _finding = false;
  String? _error;

  Future<String?> _prompt({
    required String title,
    required String label,
    required String initial,
    bool secret = false,
    String? help,
    String? helpUrl,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: label),
            ),
            if (help != null && helpUrl != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(help),
                onPressed: () => launchUrl(
                  Uri.parse(helpUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _findModels() async {
    setState(() {
      _finding = true;
      _error = null;
    });
    try {
      final models = await widget.client.models(s);
      if (!mounted) return;
      setState(() => _models = models);
      if (models.isEmpty) {
        setState(() => _error = 'No models found');
      } else if (!models.contains(s.model)) {
        await s.setModel(models.first);
      }
    } on AskException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _finding = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final provider = s.provider;
        final models = {...?_models, if (s.model.isNotEmpty) s.model}.toList()
          ..sort();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Ask about the page', style: theme.textTheme.titleMedium),
            const ListTile(
              leading: Icon(Icons.question_answer_outlined),
              title: Text('Questions about what you\'re reading'),
              subtitle: Text(
                'Ask about the page or a passage you select, answered by '
                'Claude, OpenAI or OpenRouter with your own key, or by your '
                'own Ollama server. Only the pages around where you are go '
                'with a question.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('API key')),
                  ButtonSegment(value: true, label: Text('Ollama server')),
                ],
                selected: {s.useOllama},
                onSelectionChanged: (v) {
                  _models = null;
                  s.setUseOllama(v.first);
                },
              ),
            ),
            if (!s.useOllama)
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API key'),
                subtitle: Text(
                  s.apiKey.isEmpty
                      ? 'A Claude, OpenAI or OpenRouter key'
                      : '${provider!.label} key, kept in this device\'s '
                            'secure storage',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final key = await _prompt(
                      title: 'API key',
                      label: 'Claude, OpenAI or OpenRouter key',
                      initial: s.apiKey,
                      secret: true,
                      help: 'Get a Claude key',
                      helpUrl: AskProvider.claude.keysUrl,
                    );
                    if (key != null) {
                      _models = null;
                      await s.setKey(key);
                    }
                  },
                  child: Text(s.apiKey.isEmpty ? 'Add' : 'Change'),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server address'),
                subtitle: Text(
                  s.ollamaUrl.isEmpty
                      ? 'Your Ollama server on your network or VPN'
                      : s.ollamaUrl,
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final url = await _prompt(
                      title: 'Ollama server',
                      label: 'Address, such as 192.168.1.20:11434',
                      initial: s.ollamaUrl,
                    );
                    if (url != null) {
                      _models = null;
                      await s.setOllamaUrl(url);
                    }
                  },
                  child: Text(s.ollamaUrl.isEmpty ? 'Add' : 'Change'),
                ),
              ),
            if (provider != null) ...[
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Model'),
                subtitle: _error != null
                    ? Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    : Text(
                        s.model.isEmpty
                            ? 'Find the models to pick one'
                            : s.model,
                      ),
                trailing: _finding
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _findModels,
                        child: const Text('Find models'),
                      ),
              ),
              if (_models case final found? when found.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                  child: DropdownButton<String>(
                    value: models.contains(s.model) ? s.model : null,
                    isExpanded: true,
                    items: [
                      for (final m in models)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (m) => m == null ? null : s.setModel(m),
                  ),
                ),
              const ListTile(
                leading: Icon(Icons.article_outlined),
                title: Text('Sent with a question'),
                subtitle: Text(
                  'About a page and a half around where you are, or up to '
                  'five pages of the chapter, mostly before it.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: SegmentedButton<AskContext>(
                  showSelectedIcon: false,
                  segments: [
                    for (final c in AskContext.values)
                      ButtonSegment(value: c, label: Text(c.label)),
                  ],
                  selected: {s.context},
                  onSelectionChanged: (v) => s.setContext(v.first),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Questions may leave this device'),
                subtitle: Text(
                  s.anyAllowed
                      ? 'You agreed to send pages to ${s.allowed ? s.address : 'another address'}. '
                            'Turn off to be asked again.'
                      : 'You\'ll be asked before the first question goes out.',
                ),
                value: s.anyAllowed,
                onChanged: s.anyAllowed ? (_) => s.revoke() : null,
              ),
            ],
          ],
        );
      },
    );
  }
}
