/// A neural voice model the app can download and run offline.
class VoicePack {
  const VoicePack({
    required this.id,
    required this.name,
    required this.url,
    required this.downloadBytes,
    required this.languages,
    required this.speakers,
  });

  final String id;
  final String name;

  /// A .tar.bz2 holding one folder with the model files.
  final String url;
  final int downloadBytes;

  /// Language codes the model can read, with their names.
  final Map<String, String> languages;

  /// Voice names, in speaker id order.
  final List<String> speakers;

  bool speaks(String? language) =>
      language != null && languages.containsKey(language);
}

/// Supertonic 3 by Supertone (MIT), packaged for sherpa-onnx: one 99M
/// parameter model with ten voices for 31 languages, several times faster
/// than real time on a phone CPU.
const supertonic3 = VoicePack(
  id: 'supertonic-3',
  name: 'Supertonic 3',
  url:
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2',
  downloadBytes: 128774318,
  languages: {
    'ar': 'Arabic',
    'bg': 'Bulgarian',
    'hr': 'Croatian',
    'cs': 'Czech',
    'da': 'Danish',
    'nl': 'Dutch',
    'en': 'English',
    'et': 'Estonian',
    'fi': 'Finnish',
    'fr': 'French',
    'de': 'German',
    'el': 'Greek',
    'hi': 'Hindi',
    'hu': 'Hungarian',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'lv': 'Latvian',
    'lt': 'Lithuanian',
    'pl': 'Polish',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'es': 'Spanish',
    'sv': 'Swedish',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'vi': 'Vietnamese',
  },
  // Speaker ids 0-4 are the female voices, 5-9 the male ones.
  speakers: [
    'Female 1',
    'Female 2',
    'Female 3',
    'Female 4',
    'Female 5',
    'Male 1',
    'Male 2',
    'Male 3',
    'Male 4',
    'Male 5',
  ],
);

/// The primary language subtag of a BCP 47 tag: 'en-GB' becomes 'en'.
String? baseLanguage(String? tag) {
  final base = tag?.trim().split(RegExp('[-_]')).first.toLowerCase();
  return base == null || base.isEmpty ? null : base;
}

/// The language to read [sample] in. A script used by only a few languages
/// wins over the book's metadata, which is often missing or wrong; Latin
/// text goes by the book's language, then [fallback].
String resolveLanguage(String sample, {String? book, String fallback = 'en'}) {
  final declared = baseLanguage(book);
  final counts = <String, int>{};
  for (final rune in sample.runes) {
    final script = _scriptOf(rune);
    if (script != null) counts[script] = (counts[script] ?? 0) + 1;
  }
  // Japanese mixes kana with Han characters, so any kana means Japanese.
  if ((counts['kana'] ?? 0) > 0) return 'ja';
  final top = counts.entries.fold<MapEntry<String, int>?>(
    null,
    (best, e) => best == null || e.value > best.value ? e : best,
  );
  final fromScript = switch (top?.key) {
    'hangul' => 'ko',
    'han' => declared == 'ja' ? 'ja' : 'zh',
    'cyrillic' =>
      const {'ru', 'uk', 'bg', 'sr', 'mk', 'be'}.contains(declared)
          ? declared!
          : 'ru',
    'greek' => 'el',
    'arabic' => const {'ar', 'fa', 'ur'}.contains(declared) ? declared! : 'ar',
    'hebrew' => 'he',
    'devanagari' =>
      const {'hi', 'mr', 'ne'}.contains(declared) ? declared! : 'hi',
    'thai' => 'th',
    _ => null,
  };
  return fromScript ?? declared ?? fallback;
}

String? _scriptOf(int c) {
  if (c < 0x370) return null;
  if (c <= 0x3FF) return 'greek';
  if (c >= 0x400 && c <= 0x52F) return 'cyrillic';
  if (c >= 0x590 && c <= 0x5FF) return 'hebrew';
  if (c >= 0x600 && c <= 0x6FF) return 'arabic';
  if (c >= 0x900 && c <= 0x97F) return 'devanagari';
  if (c >= 0xE00 && c <= 0xE7F) return 'thai';
  if (c >= 0x3040 && c <= 0x30FF) return 'kana';
  if (c >= 0x4E00 && c <= 0x9FFF) return 'han';
  if (c >= 0xAC00 && c <= 0xD7AF) return 'hangul';
  return null;
}

const _otherLanguages = {
  'zh': 'Chinese',
  'he': 'Hebrew',
  'th': 'Thai',
  'fa': 'Persian',
  'ur': 'Urdu',
  'sr': 'Serbian',
  'mk': 'Macedonian',
  'be': 'Belarusian',
  'mr': 'Marathi',
  'ne': 'Nepali',
};

/// The English name of a base language code, or the code itself.
String languageName(String code) =>
    supertonic3.languages[code] ?? _otherLanguages[code] ?? code;
