import 'dart:convert';

import 'package:ebook_reader/reader/ask.dart';
import 'package:ebook_reader/ui/ask_settings.dart';
import 'package:ebook_reader/ui/ask_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _book = (
  title: 'Emma',
  author: 'Jane Austen',
  where: 'Chapter 3',
  passage: 'Emma Woodhouse, handsome, clever, and rich.',
  selection: null,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('the key decides the provider, and agreement is per address', () async {
    final s = AskSettings();
    await s.load();
    expect(s.ready, isFalse);

    await s.setKey('sk-ant-api03-abc');
    expect(s.provider, AskProvider.claude);
    expect(s.model, AskSettings.defaultClaudeModel);
    expect(s.ready, isTrue);
    expect(s.allowed, isFalse);
    await s.allow();
    expect(s.allowed, isTrue);

    await s.setKey('sk-or-v1-xyz');
    expect(s.provider, AskProvider.openRouter);
    expect(s.ready, isFalse, reason: 'OpenRouter needs a model picked');
    expect(s.allowed, isFalse, reason: 'a new address asks again');

    await s.setUseOllama(true);
    await s.setOllamaUrl('192.168.1.20');
    expect(s.ollamaUrl, 'http://192.168.1.20:11434');
    expect(s.address, '192.168.1.20:11434');

    final again = AskSettings();
    await again.load();
    expect(again.useOllama, isTrue);
    expect(again.apiKey, 'sk-or-v1-xyz');
    expect(again.anyAllowed, isTrue);
    await again.revoke();
    expect(again.anyAllowed, isFalse);
  });

  test('Claude is asked with the passage in the system prompt', () async {
    final s = AskSettings();
    await s.load();
    await s.setKey('sk-ant-key');
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final client = AskClient(
      MockClient((request) async {
        headers = request.headers;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': 'She is twenty-one.'},
            ],
          }),
          200,
        );
      }),
    );
    final answer = await client.ask(
      s,
      book: _book,
      question: 'How old is Emma?',
      history: [(question: 'Who is Emma?', answer: 'The heroine.')],
    );
    expect(answer, 'She is twenty-one.');
    expect(headers['x-api-key'], 'sk-ant-key');
    expect(headers['anthropic-version'], '2026-10-21');
    expect(sent['model'], 'claude-opus-5-5');
    expect(sent['fallbacks'], 'default');
    expect(sent['system'], contains('Emma Woodhouse, handsome'));
    expect(sent['system'], contains('"Emma" by Jane Austen'));
    expect((sent['messages'] as List).length, 3);
  });

  test('a declined passage and a refused key read plainly', () async {
    final s = AskSettings();
    await s.load();
    await s.setKey('sk-ant-key');
    var refusal = true;
    final client = AskClient(
      MockClient(
        (_) async => refusal
            ? http.Response(
                jsonEncode({'stop_reason': 'refusal', 'content': []}),
                200,
              )
            : http.Response('{"error":{"message":"bad key"}}', 401),
      ),
    );
    Future<String> ask() => client.ask(s, book: _book, question: 'Why?');
    await expectLater(
      ask(),
      throwsA(
        isA<AskException>().having(
          (e) => e.message,
          'message',
          contains('declined'),
        ),
      ),
    );
    refusal = false;
    await expectLater(
      ask(),
      throwsA(
        isA<AskException>().having(
          (e) => e.message,
          'message',
          'The API key was refused',
        ),
      ),
    );
  });

  test(
    'OpenAI models are limited to chat models; Ollama lists its own',
    () async {
      final s = AskSettings();
      await s.load();
      await s.setKey('sk-proj-1');
      final client = AskClient(
        MockClient((request) async {
          if (request.url.host == 'api.openai.com') {
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'whisper-1'},
                  {'id': 'gpt-5-mini'},
                  {'id': 'o4-mini'},
                ],
              }),
              200,
            );
          }
          expect(request.url.toString(), 'http://nas:11434/api/tags');
          return http.Response(
            jsonEncode({
              'models': [
                {'name': 'llama4:8b'},
              ],
            }),
            200,
          );
        }),
      );
      expect(await client.models(s), ['gpt-5-mini', 'o4-mini']);
      await s.setUseOllama(true);
      await s.setOllamaUrl('nas');
      expect(await client.models(s), ['llama4:8b']);
    },
  );

  testWidgets('the sheet asks once before sending, then shows the answer', (
    tester,
  ) async {
    final s = AskSettings();
    await s.load();
    await s.setKey('sk-ant-key');
    var calls = 0;
    final client = AskClient(
      MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'Emma is matchmaking.'},
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AskSheet(
            settings: s,
            client: client,
            title: 'Emma',
            author: 'Jane Austen',
            where: 'Chapter 1',
            passage: (_) async => 'Emma Woodhouse, handsome, clever, and rich.',
          ),
        ),
      ),
    );
    await tester.tap(find.text('What happens on this page?'));
    await tester.pumpAndSettle();
    expect(find.text('Before your first question'), findsOneWidget);
    expect(find.textContaining('about 6 words'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(find.text('Emma is matchmaking.'), findsOneWidget);
    expect(calls, 1);

    await tester.enterText(find.byType(TextField), 'And then?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.text('Before your first question'), findsNothing);
    expect(calls, 2);
  });

  for (final width in [400.0, 900.0]) {
    testWidgets('the settings lay out at ${width.round()} wide', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AskSettings();
      await s.load();
      await s.setKey('sk-ant-key');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                AskSettingsSection(
                  settings: s,
                  client: AskClient(
                    MockClient((_) async => http.Response('{}', 200)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text('Claude key, kept in this device\'s secure storage'),
        findsOneWidget,
      );
      expect(find.text('Whole chapter'), findsOneWidget);
    });
  }
}
