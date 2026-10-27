import 'package:ebook_reader/reader/book_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSearch extends BookSearch {
  final started = <String>[];
  int cancelled = 0;
  SearchHit? shown;

  @override
  void start(String query) => started.add(query);

  @override
  void cancel() => cancelled++;

  @override
  Future<void> goTo(SearchHit hit) async => shown = hit;

  void report(List<SearchHit> hits, double progress, {bool done = false}) {
    addHits(hits);
    setProgress(progress, done: done);
  }
}

SearchHit _hit(String label, String match) => SearchHit(
  location: 'epubcfi(/6/2)',
  label: label,
  pre: 'before ',
  match: match,
  post: ' after',
);

void main() {
  test('a search collects matches until it is done', () {
    final search = _FakeSearch();
    search.search('  whale ');
    expect(search.started, ['whale']);
    expect(search.query, 'whale');
    expect(search.searching, isTrue);

    search.report([_hit('Chapter 1', 'whale')], 0.5);
    search.report([_hit('Chapter 2', 'Whale')], 1, done: true);
    expect(search.hits.map((h) => h.label), ['Chapter 1', 'Chapter 2']);
    expect(search.searching, isFalse);
  });

  test('repeating a query does nothing; clearing cancels', () {
    final search = _FakeSearch()..search('whale');
    search.search('whale');
    expect(search.started, ['whale']);
    search.clear();
    expect(search.cancelled, 1);
    expect(search.hits, isEmpty);
    expect(search.searching, isFalse);
  });

  testWidgets('the panel lists matches by chapter and opens one', (
    tester,
  ) async {
    final search = _FakeSearch()..search('whale');
    search.report(
      [
        _hit('Chapter 1', 'whale'),
        _hit('Chapter 1', 'whale'),
        _hit('Chapter 2', 'whale'),
      ],
      1,
      done: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => SearchPanel(search: search),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('3 matches'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('Chapter 2'), findsOneWidget);
    await tester.tap(find.byType(ListTile).last);
    await tester.pumpAndSettle();
    expect(search.shown?.label, 'Chapter 2');
  });
}
