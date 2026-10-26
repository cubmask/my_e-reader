import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_meta_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _book = Book(
  driveFileId: 'b1',
  fileName: 'dune_v2.epub',
  format: BookFormat.epub,
  folderPath: '',
);

void main() {
  late Directory dir;
  late BookMetaStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meta');
    store = BookMetaStore(File('${dir.path}/library.json'), null);
  });
  tearDown(() => dir.delete(recursive: true));

  test('falls back to the file name until a title is set', () async {
    expect(store.titleOf(_book), 'dune_v2');
    await store.set('b1', title: 'Dune', author: 'Frank Herbert');
    expect(store.titleOf(_book), 'Dune');
    expect(store.authorOf(_book), 'Frank Herbert');
  });

  test("the book's own metadata never overwrites the user's", () async {
    await store.fillIn('b1', title: 'DUNE (Ace ed.)', author: 'Herbert');
    expect(store.titleOf(_book), 'DUNE (Ace ed.)');
    await store.set('b1', title: 'Dune');
    await store.fillIn('b1', title: 'Something else', author: 'Other');
    expect(store.titleOf(_book), 'Dune');
    expect(store.authorOf(_book), 'Herbert');
  });

  test('collections can be listed, renamed and deleted', () async {
    await store.set('b1', collections: ['sci-fi', 'Favourites']);
    await store.set('b2', collections: ['sci-fi']);
    expect(store.collections, ['Favourites', 'sci-fi']);
    await store.renameCollection('sci-fi', 'Science fiction');
    expect(store.collectionsOf(_book), ['Science fiction', 'Favourites']);
    await store.deleteCollection('Science fiction');
    expect(store.collections, ['Favourites']);
    expect(store['b2']!.collections, isEmpty);
  });

  test('survives a restart and merges with the newest entry winning', () async {
    await store.set('b1', title: 'Dune', collections: ['A']);
    final reloaded = BookMetaStore(File('${dir.path}/library.json'), null);
    await reloaded.load();
    expect(reloaded.titleOf(_book), 'Dune');

    final older = {
      'b1': BookMeta(title: 'Old', updatedAt: DateTime.utc(2000)),
      'b2': BookMeta(title: 'Only remote', updatedAt: DateTime.utc(2000)),
    };
    final merged = mergeMeta(
      decodeMeta(encodeMeta({'b1': reloaded['b1']!})),
      older,
    );
    expect(merged['b1']!.title, 'Dune');
    expect(merged['b1']!.collections, ['A']);
    expect(merged['b2']!.title, 'Only remote');
  });
}
