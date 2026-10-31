import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../reader/tts/cloud_voices.dart';
import '../reader/tts/voice_pack.dart';
import '../reader/tts/voice_store.dart';

const _samples = {
  'en': 'This is how I sound when I read your books aloud.',
  'de': 'So klinge ich, wenn ich dir deine Bücher vorlese.',
  'fr': 'Voici ma voix quand je vous lis vos livres à haute voix.',
  'es': 'Así sueno cuando leo tus libros en voz alta.',
  'it': 'Ecco come suono quando leggo ad alta voce i tuoi libri.',
  'pt': 'É assim que eu soo quando leio os seus livros em voz alta.',
  'nl': 'Zo klink ik als ik je boeken voorlees.',
  'ru': 'Вот так я звучу, когда читаю ваши книги вслух.',
  'ja': 'あなたの本を読み上げるときは、こんな声です。',
  'ko': '책을 소리 내어 읽어 드릴 때 이런 목소리예요.',
};

String _megabytes(int bytes) => '${(bytes / 1000000).round()} MB';

/// Download and choose the offline read-aloud voice.
class VoiceSettings extends StatefulWidget {
  const VoiceSettings({super.key, required this.voices, this.preview = true});

  final VoiceStore voices;

  /// Whether to offer a spoken sample, which can't play while reading.
  final bool preview;

  @override
  State<VoiceSettings> createState() => _VoiceSettingsState();
}

class _VoiceSettingsState extends State<VoiceSettings> {
  bool _previewing = false;

  VoiceStore get voices => widget.voices;

  Future<void> _preview() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    final language = voices.language ?? 'en';
    final known = _samples.containsKey(language);
    final engine = await voices.engineFor(known ? language : 'en');
    try {
      await engine.setLanguage(known ? language : 'en');
      await engine.setSpeed(1.0);
      await engine.speak(_samples[known ? language : 'en']!);
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voices,
      builder: (context, _) {
        final pack = voices.pack;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(
                'Read aloud',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _OnlineVoices(
              voices: voices,
              onPreview: widget.preview && !_previewing ? _preview : null,
            ),
            const Divider(indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Offline voice',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _statusTile(context, pack),
            if (voices.error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (voices.status == VoiceStatus.downloading ||
                voices.status == VoiceStatus.installing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(value: voices.progress),
              ),
            if (voices.installed) ...[
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: Text('Read with ${pack.name}'),
                subtitle: const Text(
                  'Other languages, and everything when this is off, use '
                  'the system voice.',
                ),
                value: voices.useNeural,
                onChanged: voices.setUseNeural,
              ),
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: const Text('Voice'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<int>(
                      value: voices.speaker,
                      underline: const SizedBox(),
                      items: [
                        for (var i = 0; i < pack.speakers.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(pack.speakers[i]),
                          ),
                      ],
                      onChanged: (v) => v == null ? null : voices.setSpeaker(v),
                    ),
                    if (widget.preview)
                      IconButton(
                        tooltip: 'Play a sample',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed:
                            _previewing ||
                                !voices.useNeural ||
                                voices.cloud.ready
                            ? null
                            : _preview,
                      ),
                  ],
                ),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('Language'),
              subtitle: const Text(
                'Automatic follows the book and the script of its text.',
              ),
              trailing: DropdownButton<String?>(
                value: voices.language,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(child: Text('Automatic')),
                  for (final e
                      in (pack.languages.entries.toList()
                        ..sort((a, b) => a.value.compareTo(b.value))))
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: voices.setLanguage,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusTile(BuildContext context, VoicePack pack) {
    final description =
        'Natural offline voice for ${pack.languages.length} languages';
    return switch (voices.status) {
      VoiceStatus.notInstalled => ListTile(
        leading: const Icon(Icons.download_outlined),
        title: Text(pack.name),
        subtitle: Text(
          '$description. ${_megabytes(pack.downloadBytes)} download; '
          'until then the system voice reads.',
        ),
        trailing: FilledButton.tonal(
          onPressed: voices.download,
          child: const Text('Download'),
        ),
      ),
      VoiceStatus.downloading => ListTile(
        leading: const Icon(Icons.downloading),
        title: Text(pack.name),
        subtitle: Text(
          'Downloading: ${((voices.progress ?? 0) * 100).round()}% of '
          '${_megabytes(pack.downloadBytes)}',
        ),
        trailing: TextButton(
          onPressed: voices.cancel,
          child: const Text('Cancel'),
        ),
      ),
      VoiceStatus.installing => ListTile(
        leading: const Icon(Icons.downloading),
        title: Text(pack.name),
        subtitle: const Text('Unpacking...'),
      ),
      VoiceStatus.installed => FutureBuilder(
        future: voices.sizeOnDisk(),
        builder: (context, size) => ListTile(
          leading: const Icon(Icons.download_done),
          title: Text(pack.name),
          subtitle: Text(
            '$description'
            '${size.hasData ? ' · ${_megabytes(size.data!)} on this device' : ''}',
          ),
          trailing: TextButton(
            onPressed: voices.remove,
            child: const Text('Remove'),
          ),
        ),
      ),
    };
  }
}

/// ElevenLabs, Fish Audio or Azure, with the reader's own API key.
class _OnlineVoices extends StatelessWidget {
  const _OnlineVoices({required this.voices, this.onPreview});

  final VoiceStore voices;
  final VoidCallback? onPreview;

  CloudVoiceSettings get cloud => voices.cloud;

  Future<void> _editKey(BuildContext context, CloudProvider provider) async {
    final controller = TextEditingController(text: cloud.keyFor(provider));
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${provider.label} API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Get a key'),
              onPressed: () => launchUrl(
                Uri.parse(provider.keysUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
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
    if (key != null) await cloud.setKey(provider, key);
  }

  Future<void> _pickVoice(BuildContext context, CloudProvider provider) async {
    final voice = await showDialog<CloudVoice>(
      context: context,
      builder: (context) => _VoicePicker(
        load: (search) => voices.cloudClient.voices(
          provider,
          cloud.keyFor(provider)!,
          search: search,
          region: cloud.modelFor(provider),
        ),
      ),
    );
    if (voice != null) await cloud.setVoice(provider, voice);
  }

  @override
  Widget build(BuildContext context) {
    final provider = cloud.provider;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Online voice'),
          subtitle: const Text(
            'Studio-quality voices while connected; the offline voice takes '
            'over without a connection. The text being read is sent to the '
            'service and billed to your account (a novel is roughly 500,000 '
            'characters; Azure gives 500,000 free each month).',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Scrolls rather than overflowing on a narrow phone.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<CloudProvider?>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: null, label: Text('Off')),
                for (final p in CloudProvider.values)
                  ButtonSegment(value: p, label: Text(p.label)),
              ],
              selected: {provider},
              onSelectionChanged: (v) => cloud.setProvider(v.first),
            ),
          ),
        ),
        if (provider != null) ...[
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('API key'),
            subtitle: Text(
              cloud.hasKey(provider)
                  ? 'Saved in this device\'s secure storage'
                  : 'Needed to use ${provider.label}',
            ),
            trailing: TextButton(
              onPressed: () => _editKey(context, provider),
              child: Text(cloud.hasKey(provider) ? 'Change' : 'Add'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(provider.modelLabel),
            trailing: DropdownButton<String>(
              value: cloud.modelFor(provider),
              underline: const SizedBox(),
              items: [
                for (final m in provider.models)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => v == null ? null : cloud.setModel(provider, v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Voice'),
            subtitle: Text(
              cloud.voiceFor(provider)?.name ??
                  switch (provider) {
                    CloudProvider.fishAudio => 'Fish Audio\'s default voice',
                    CloudProvider.azure => 'Emma (Multilingual), the default',
                    CloudProvider.elevenLabs => 'Pick a voice to start',
                  },
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: cloud.hasKey(provider)
                      ? () => _pickVoice(context, provider)
                      : null,
                  child: const Text('Choose'),
                ),
                IconButton(
                  tooltip: 'Play a sample',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: cloud.ready ? onPreview : null,
                ),
              ],
            ),
          ),
          FutureBuilder(
            future: voices.audioCache.size(),
            builder: (context, size) => ListTile(
              leading: const Icon(Icons.save_outlined),
              title: const Text('Saved audio'),
              subtitle: Text(
                '${size.hasData ? _megabytes(size.data!) : '...'} of read '
                'passages, replayed without using credits',
              ),
              trailing: TextButton(
                onPressed: (size.data ?? 0) == 0
                    ? null
                    : voices.clearAudioCache,
                child: const Text('Clear'),
              ),
            ),
          ),
          if (voices.cloudError case final error?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Last time: $error. Read with the offline voice instead.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ],
    );
  }
}

/// Searches a provider's voices, or takes a voice ID typed in.
class _VoicePicker extends StatefulWidget {
  const _VoicePicker({required this.load});

  final Future<List<CloudVoice>> Function(String search) load;

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  final _search = TextEditingController();
  late Future<List<CloudVoice>> _voices = widget.load('');

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typed = _search.text.trim();
    return AlertDialog(
      title: const Text('Choose a voice'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search, or paste a voice ID',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) =>
                  setState(() => _voices = widget.load(v.trim())),
            ),
            if (typed.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text('Use "$typed" as the voice ID'),
                onTap: () => Navigator.pop(context, CloudVoice(typed, typed)),
              ),
            Expanded(
              child: FutureBuilder(
                future: _voices,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('${snapshot.error}'));
                  }
                  final voices = snapshot.data;
                  if (voices == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (voices.isEmpty) {
                    return const Center(child: Text('No voices found'));
                  }
                  return ListView(
                    children: [
                      for (final v in voices)
                        ListTile(
                          title: Text(v.name),
                          subtitle: v.details.isEmpty
                              ? null
                              : Text(
                                  v.details,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, v),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
