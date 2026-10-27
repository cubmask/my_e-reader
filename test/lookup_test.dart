import 'dart:convert';

import 'package:ebook_reader/reader/lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('selections are trimmed of quotes and punctuation', () {
    expect(cleanQuery('“Whale,”'), 'Whale');
    expect(cleanQuery('  the  white\nwhale. '), 'the white whale');
    expect(cleanQuery('(Ahab)'), 'Ahab');
  });

  test('looks a word up in the dictionary and Wikipedia', () async {
    final asked = <Uri>[];
    final service = LookupService(
      MockClient((req) async {
        asked.add(req.url);
        if (req.url.host == 'api.dictionaryapi.dev') {
          return http.Response(
            jsonEncode([
              {
                'word': 'whale',
                'phonetic': '/weɪl/',
                'meanings': [
                  {
                    'partOfSpeech': 'noun',
                    'definitions': [
                      {
                        'definition': 'A very large sea mammal.',
                        'example': 'a whale of a time',
                      },
                    ],
                  },
                ],
              },
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          jsonEncode({
            'type': 'standard',
            'title': 'Whale',
            'extract': 'Whales are marine mammals.',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await service.lookUp('“Whale.”', language: 'en-GB');
    expect(result.word, 'whale');
    expect(result.phonetic, '/weɪl/');
    expect(result.definitions.single.partOfSpeech, 'noun');
    expect(result.definitions.single.example, 'a whale of a time');
    expect(result.wikiTitle, 'Whale');
    expect(asked.map((u) => u.host), contains('en.wikipedia.org'));

    // The answer is kept for the session.
    await service.lookUp('whale', language: 'en');
    expect(asked, hasLength(2));
  });

  test('other languages and phrases skip the English dictionary', () async {
    final asked = <String>[];
    final service = LookupService(
      MockClient((req) async {
        asked.add(req.url.host);
        return http.Response('{"type":"disambiguation","extract":"x"}', 200);
      }),
    );
    final result = await service.lookUp('Moby Dick', language: 'de');
    expect(asked, ['de.wikipedia.org']);
    expect(result.isEmpty, isTrue);
  });
}
