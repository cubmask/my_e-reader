import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Where questions about the page are answered: a model behind the
/// reader's own API key, or their own Ollama server.
enum AskProvider {
  claude('Claude', 'https://console.anthropic.com/settings/keys'),
  openAI('OpenAI', 'https://platform.openai.com/api-keys'),
  openRouter('OpenRouter', 'https://openrouter.ai/settings/keys'),
  ollama('Ollama', 'https://ollama.com/download');

  const AskProvider(this.label, this.keysUrl);

  final String label;

  /// Where the reader gets a key (or Ollama itself).
  final String keysUrl;

  /// The provider a key belongs to, from its prefix.
  static AskProvider forKey(String key) {
    if (key.startsWith('sk-ant-')) return claude;
    if (key.startsWith('sk-or-')) return openRouter;
    return openAI;
  }
}

/// How much of the book goes with a question.
enum AskContext {
  /// About a page and a half around the reading position.
  passage('This passage'),

  /// Up to about five pages of the chapter, mostly before the position.
  chapter('Whole chapter');

  const AskContext(this.label);

  final String label;
}

/// One question and its answer.
typedef AskTurn = ({String question, String answer});

/// What the model is told about the book.
typedef AskBook = ({
  String title,
  String author,
  String where,
  String passage,
  String? selection,
});

/// A request the provider refused or that couldn't reach it.
class AskException implements Exception {
  const AskException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Which model answers, and the reader's agreement to send it pages.
///
/// The API key lives in the platform's secure storage; agreement is kept
/// per address, so a new server or provider asks again.
class AskSettings extends ChangeNotifier {
  AskSettings({FlutterSecureStorage? secrets})
    : _secrets =
          secrets ??
          FlutterSecureStorage(
            mOptions: const MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _keySecret = 'ask.apiKey';
  static const _useOllamaKey = 'ask.useOllama';
  static const _ollamaKey = 'ask.ollamaUrl';
  static const _modelKey = 'ask.model';
  static const _contextKey = 'ask.context';
  static const _allowedKey = 'ask.allowed';

  /// Picked when the reader hasn't chosen a Claude model.
  static const defaultClaudeModel = 'claude-opus-5-5';

  final FlutterSecureStorage _secrets;
  String _key = '';
  bool _useOllama = false;
  String _ollamaUrl = '';
  String _model = '';
  AskContext _context = AskContext.passage;
  Set<String> _allowed = {};

  String get apiKey => _key;
  bool get useOllama => _useOllama;

  /// The Ollama server, such as `http://192.168.1.20:11434`.
  String get ollamaUrl => _ollamaUrl;
  AskContext get context => _context;

  AskProvider? get provider {
    if (_useOllama) return _ollamaUrl.isEmpty ? null : AskProvider.ollama;
    return _key.isEmpty ? null : AskProvider.forKey(_key);
  }

  /// The model to ask; Claude has a default, the others need one picked.
  String get model => _model.isNotEmpty
      ? _model
      : provider == AskProvider.claude
      ? defaultClaudeModel
      : '';

  /// Whether questions can be asked.
  bool get ready => provider != null && model.isNotEmpty;

  /// The host questions go to, as the reader is asked to agree to it.
  String? get address => switch (provider) {
    null => null,
    AskProvider.ollama => Uri.tryParse(_ollamaUrl)?.authority ?? _ollamaUrl,
    AskProvider.claude => 'api.anthropic.com',
    AskProvider.openAI => 'api.openai.com',
    AskProvider.openRouter => 'openrouter.ai',
  };

  /// Whether the reader agreed to send pages to [address].
  bool get allowed => _allowed.contains(address);

  /// Whether the reader agreed to send pages anywhere.
  bool get anyAllowed => _allowed.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _useOllama = prefs.getBool(_useOllamaKey) ?? false;
    _ollamaUrl = prefs.getString(_ollamaKey) ?? '';
    _model = prefs.getString(_modelKey) ?? '';
    _context =
        AskContext.values.asNameMap()[prefs.getString(_contextKey)] ??
        AskContext.passage;
    _allowed = {...?prefs.getStringList(_allowedKey)};
    try {
      _key = await _secrets.read(key: _keySecret) ?? '';
    } catch (e) {
      debugPrint('Could not read the question key: $e');
    }
    notifyListeners();
  }

  /// Saves [key], or forgets it when empty. A key for another provider
  /// clears the model picked for the old one.
  Future<void> setKey(String key) async {
    final trimmed = key.trim();
    final before = provider;
    _key = trimmed;
    if (trimmed.isEmpty) {
      await _secrets.delete(key: _keySecret);
    } else {
      await _secrets.write(key: _keySecret, value: trimmed);
    }
    if (provider != before) await setModel('');
    notifyListeners();
  }

  Future<void> setUseOllama(bool value) async {
    _useOllama = value;
    _model = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useOllamaKey, value);
    await prefs.remove(_modelKey);
  }

  /// Saves the Ollama address, adding `http://` and the usual port when
  /// they are left out.
  Future<void> setOllamaUrl(String url) async {
    var value = url.trim();
    if (value.isNotEmpty && !value.contains('://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty && !uri.hasPort) {
      value = uri.replace(port: 11434).toString();
    }
    if (value.endsWith('/')) value = value.substring(0, value.length - 1);
    _ollamaUrl = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_ollamaKey, value);
  }

  Future<void> setModel(String model) async {
    _model = model;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (model.isEmpty) {
      await prefs.remove(_modelKey);
    } else {
      await prefs.setString(_modelKey, model);
    }
  }

  Future<void> setContext(AskContext context) async {
    _context = context;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _contextKey,
      context.name,
    );
  }

  /// Records that the reader agreed to send pages to [address].
  Future<void> allow() async {
    final to = address;
    if (to == null) return;
    _allowed = {..._allowed, to};
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _allowedKey,
      _allowed.toList(),
    );
  }

  /// Withdraws every agreement; the next question asks again.
  Future<void> revoke() async {
    _allowed = {};
    notifyListeners();
    await (await SharedPreferences.getInstance()).remove(_allowedKey);
  }
}

/// Asks Claude, OpenAI, OpenRouter or an Ollama server about a passage.
class AskClient {
  AskClient(this._http, {this.timeout = const Duration(minutes: 2)});

  final http.Client _http;
  final Duration timeout;

  static const _anthropicVersion = '2026-10-21';

  /// Claude models that can fall back to another model when a safety
  /// check declines a passage, which happens with some fiction.
  static const _claudeFallbacks = {
    'claude-fable-5-1',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-sonnet-5-5',
  };

  Future<http.Response> _send(Future<http.Response> request) async {
    final http.Response response;
    try {
      response = await request.timeout(timeout);
    } on TimeoutException {
      throw const AskException('The answer took too long');
    } on SocketException {
      throw const AskException('No connection');
    } on http.ClientException catch (e) {
      throw AskException('No connection (${e.message})');
    }
    if (response.statusCode == 200) return response;
    throw AskException(switch (response.statusCode) {
      401 || 403 => 'The API key was refused',
      402 => 'The account is out of credit',
      404 => 'The model or address wasn\'t found',
      429 => 'Too many questions; try again shortly',
      final code => 'The service failed ($code${_reason(response)})',
    });
  }

  static String _reason(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final error = body is Map ? body['error'] : null;
      final message = error is Map ? error['message'] : error;
      return message is String && message.isNotEmpty ? ': $message' : '';
    } catch (_) {
      return '';
    }
  }

  static Object? _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Map<String, String> _headers(AskSettings s) => switch (s.provider) {
    AskProvider.claude => {
      'x-api-key': s.apiKey,
      'anthropic-version': _anthropicVersion,
    },
    AskProvider.openAI ||
    AskProvider.openRouter => {'Authorization': 'Bearer ${s.apiKey}'},
    _ => const {},
  };

  /// The models the key or server offers, by id.
  Future<List<String>> models(AskSettings s) async {
    final url = switch (s.provider) {
      AskProvider.claude => 'https://api.anthropic.com/v1/models?limit=100',
      AskProvider.openAI => 'https://api.openai.com/v1/models',
      AskProvider.openRouter => 'https://openrouter.ai/api/v1/models',
      AskProvider.ollama => '${s.ollamaUrl}/api/tags',
      null => throw const AskException('Add an API key or a server first'),
    };
    final body = _json(
      await _send(_http.get(Uri.parse(url), headers: _headers(s))),
    );
    final list = body is Map ? body['data'] ?? body['models'] : null;
    final ids = [
      for (final m in list is List ? list : const [])
        if (m is Map && (m['id'] ?? m['name']) is String)
          (m['id'] ?? m['name']) as String,
    ];
    if (s.provider == AskProvider.openAI) {
      // Only the chat models; the list also holds speech, images and more.
      ids.retainWhere((id) => RegExp(r'^(gpt|o\d|chatgpt)').hasMatch(id));
    }
    return ids..sort();
  }

  /// Answers [question] about [book], following on from [history].
  Future<String> ask(
    AskSettings s, {
    required AskBook book,
    required String question,
    List<AskTurn> history = const [],
  }) async {
    final system = systemPrompt(book);
    final messages = [
      for (final t in history) ...[
        {'role': 'user', 'content': t.question},
        {'role': 'assistant', 'content': t.answer},
      ],
      {'role': 'user', 'content': question},
    ];
    switch (s.provider) {
      case AskProvider.claude:
        final fallback = _claudeFallbacks.contains(s.model);
        final body = _json(
          await _send(
            _http.post(
              Uri.parse('https://api.anthropic.com/v1/messages'),
              headers: {
                ..._headers(s),
                'content-type': 'application/json',
                if (fallback)
                  'anthropic-beta': 'server-side-fallback-2026-07-01',
              },
              body: jsonEncode({
                'model': s.model,
                'max_tokens': 16000,
                'system': system,
                'messages': messages,
                if (fallback) 'fallbacks': 'default',
              }),
            ),
          ),
        );
        if (body is! Map) throw const AskException('No answer came back');
        if (body['stop_reason'] == 'refusal') {
          throw const AskException(
            'The model declined this passage; try rephrasing or another page',
          );
        }
        final text = [
          for (final block in body['content'] as List? ?? const [])
            if (block is Map && block['type'] == 'text') block['text'],
        ].join().trim();
        if (text.isEmpty) throw const AskException('No answer came back');
        return text;
      case AskProvider.openAI || AskProvider.openRouter:
        final url = s.provider == AskProvider.openAI
            ? 'https://api.openai.com/v1/chat/completions'
            : 'https://openrouter.ai/api/v1/chat/completions';
        final body = _json(
          await _send(
            _http.post(
              Uri.parse(url),
              headers: {..._headers(s), 'content-type': 'application/json'},
              body: jsonEncode({
                'model': s.model,
                'messages': [
                  {'role': 'system', 'content': system},
                  ...messages,
                ],
              }),
            ),
          ),
        );
        final choices = body is Map ? body['choices'] : null;
        final first = choices is List && choices.isNotEmpty
            ? choices.first
            : null;
        final text = switch (first) {
          {'message': {'content': final String text}} => text,
          _ => null,
        };
        if (text is! String || text.trim().isEmpty) {
          throw const AskException('No answer came back');
        }
        return text.trim();
      case AskProvider.ollama:
        final body = _json(
          await _send(
            _http.post(
              Uri.parse('${s.ollamaUrl}/api/chat'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'model': s.model,
                'stream': false,
                'messages': [
                  {'role': 'system', 'content': system},
                  ...messages,
                ],
              }),
            ),
          ),
        );
        final text = switch (body) {
          {'message': {'content': final String text}} => text,
          _ => null,
        };
        if (text is! String || text.trim().isEmpty) {
          throw const AskException('No answer came back');
        }
        return text.trim();
      case null:
        throw const AskException('Add an API key or a server first');
    }
  }
}

/// Tells the model what it is reading and keeps it to the passage, so it
/// can't give away what happens later.
String systemPrompt(AskBook book) {
  final by = book.author.isEmpty ? '' : ' by ${book.author}';
  return '''
You are helping someone while they read "${book.title}"$by. They are at ${book.where}.

Answer from the passage below, which is the part of the book around where they are reading. If the passage doesn't answer the question, say so plainly instead of guessing, and don't reveal anything that happens later in the book, even if you know it. Keep answers short, a few sentences, unless they ask for more, and answer in the language of their question.

<passage>
${book.passage}
</passage>${book.selection == null ? '' : '''


They selected these words:
<selection>
${book.selection}
</selection>'''}''';
}

/// About how many words [text] holds, for the agreement card.
int wordCount(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
