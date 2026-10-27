import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/platform_bridge.dart';

/// One sense of a word, such as "noun: a large marine mammal".
typedef Definition = ({String partOfSpeech, String text, String? example});

/// A dictionary entry and a Wikipedia summary for selected text.
class LookupResult {
  const LookupResult({
    this.word,
    this.phonetic,
    this.definitions = const [],
    this.wikiTitle,
    this.wikiSummary,
  });

  final String? word;
  final String? phonetic;
  final List<Definition> definitions;
  final String? wikiTitle;
  final String? wikiSummary;

  bool get isEmpty => definitions.isEmpty && wikiSummary == null;
}

/// Looks words up in the free Dictionary API (English) and Wikipedia's
/// page summaries. Neither needs a key; answers are kept for the session.
class LookupService {
  LookupService(this._client);

  final http.Client _client;
  final _cache = <String, Future<LookupResult>>{};

  /// [language] is the book's, such as 'en-GB'; English when unknown.
  Future<LookupResult> lookUp(String text, {String? language}) {
    final query = cleanQuery(text);
    final lang = (language ?? 'en').split(RegExp('[-_]')).first.toLowerCase();
    return _cache['$lang:${query.toLowerCase()}'] ??= _lookUp(query, lang);
  }

  Future<LookupResult> _lookUp(String query, String lang) async {
    final results = await Future.wait([
      // The dictionary only has single English words.
      if (lang == 'en' && !query.contains(' '))
        _define(query)
      else
        Future.value(null),
      _wiki(query, lang),
    ]);
    final dict = results[0];
    final wiki = results[1];
    return LookupResult(
      word: dict?.word ?? query,
      phonetic: dict?.phonetic,
      definitions: dict?.definitions ?? const [],
      wikiTitle: wiki?.wikiTitle,
      wikiSummary: wiki?.wikiSummary,
    );
  }

  Future<LookupResult?> _define(String word) async {
    try {
      final res = await _client
          .get(
            Uri.https(
              'api.dictionaryapi.dev',
              '/api/v2/entries/en/${Uri.encodeComponent(word.toLowerCase())}',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parseDictionary(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {
      return null;
    }
  }

  Future<LookupResult?> _wiki(String query, String lang) async {
    try {
      final title = Uri.encodeComponent(query.replaceAll(' ', '_'));
      final res = await _client
          .get(
            Uri.parse(
              'https://$lang.wikipedia.org/api/rest_v1/page/summary/$title',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return parseWikiSummary(jsonDecode(utf8.decode(res.bodyBytes)));
    } catch (_) {
      return null;
    }
  }
}

/// Trims punctuation and quotes off a selection and keeps it short.
String cleanQuery(String text) {
  final trimmed = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(
        RegExp(r'''^[\s"'“”‘’«»(\[{.,;:!?—–-]+|[\s"'“”‘’«»)\]}.,;:!?—–-]+$'''),
        '',
      );
  return trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed;
}

LookupResult? parseDictionary(Object? json) {
  if (json is! List || json.isEmpty) return null;
  final definitions = <Definition>[];
  String? word, phonetic;
  for (final entry in json) {
    if (entry is! Map) continue;
    word ??= entry['word'] as String?;
    phonetic ??= entry['phonetic'] as String?;
    for (final meaning in (entry['meanings'] as List? ?? const [])) {
      if (meaning is! Map) continue;
      for (final d in (meaning['definitions'] as List? ?? const [])) {
        if (d is Map && d['definition'] is String) {
          definitions.add((
            partOfSpeech: '${meaning['partOfSpeech'] ?? ''}',
            text: d['definition'] as String,
            example: d['example'] as String?,
          ));
        }
      }
    }
  }
  if (definitions.isEmpty) return null;
  return LookupResult(
    word: word,
    phonetic: phonetic,
    definitions: definitions.take(8).toList(),
  );
}

LookupResult? parseWikiSummary(Object? json) {
  if (json is! Map) return null;
  // A disambiguation page lists other articles rather than explaining.
  if (json['type'] == 'disambiguation') return null;
  final extract = json['extract'];
  if (extract is! String || extract.trim().isEmpty) return null;
  return LookupResult(
    wikiTitle: json['title'] as String?,
    wikiSummary: extract.trim(),
  );
}

/// The look-up sheet for selected text: definitions, a Wikipedia summary,
/// and buttons to translate or read more.
class LookupSheet extends StatelessWidget {
  const LookupSheet({
    super.key,
    required this.service,
    required this.text,
    this.language,
  });

  final LookupService service;
  final String text;
  final String? language;

  String get _lang =>
      (language ?? 'en').split(RegExp('[-_]')).first.toLowerCase();

  Future<void> _translate() async {
    final query = cleanQuery(text);
    if (await PlatformBridge.instance.translate(query)) return;
    final target = PlatformDispatcher.instance.locale.languageCode;
    await launchUrl(
      Uri.https('translate.google.com', '/', {
        'sl': 'auto',
        'tl': target,
        'text': query,
      }),
      mode: LaunchMode.inAppBrowserView,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = cleanQuery(text);
    return FutureBuilder(
      future: service.lookUp(text, language: language),
      builder: (context, snapshot) {
        final result = snapshot.data;
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(result?.word ?? query, style: theme.textTheme.headlineSmall),
            if (result?.phonetic case final phonetic?)
              Text(phonetic, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.translate),
                  label: const Text('Translate'),
                  onPressed: _translate,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.public),
                  label: const Text('Wikipedia'),
                  onPressed: () => launchUrl(
                    Uri.https('$_lang.wikipedia.org', '/wiki/Special:Search', {
                      'search': query,
                    }),
                    mode: LaunchMode.inAppBrowserView,
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Web'),
                  onPressed: () => launchUrl(
                    Uri.https('www.google.com', '/search', {'q': query}),
                    mode: LaunchMode.inAppBrowserView,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (result == null || result.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No definition found.'),
              )
            else ...[
              for (final d in result.definitions)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (d.partOfSpeech.isNotEmpty)
                          TextSpan(
                            text: '${d.partOfSpeech}  ',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        TextSpan(text: d.text),
                        if (d.example case final example?)
                          TextSpan(
                            text: '\n“$example”',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (result.wikiSummary case final summary?) ...[
                const SizedBox(height: 20),
                Text(
                  result.wikiTitle ?? 'Wikipedia',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(summary, maxLines: 8, overflow: TextOverflow.ellipsis),
              ],
            ],
          ],
        );
      },
    );
  }
}
