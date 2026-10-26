import 'package:flutter/material.dart';

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
                        onPressed: _previewing || !voices.useNeural
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
