import 'dart:io';

import 'package:ebook_reader/notes/annotation_store.dart';
import 'package:ebook_reader/reader/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRemote implements ProgressRemote {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String c) async => contents = c;
}

Annotation _a(
  String id,
  int minute, {
  bool deleted = false,
  String note = '',
}) => Annotation(
  id: id,
  bookId: 'book',
  bookTitle: 'Book',
  location: 'epubcfi(/6/2!/4/2,/1:0,/1:5)',
  text: 'Hello',
  note: note,
  color: HighlightColor.yellow,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, 1, 12, minute),
  deleted: deleted,
);

void main() {
  test('merge keeps the newest copy, including deletions', () {
    final merged = mergeAnnotations(
      {'x': _a('x', 10, note: 'mine'), 'y': _a('y', 30)},
      {'x': _a('x', 20, note: 'theirs'), 'y': _a('y', 5, deleted: true)},
    );
    expect(merged['x']!.note, 'theirs');
    expect(merged['y']!.deleted, isFalse);
  });

  test('round-trips through JSON', () {
    final decoded = decodeAnnotations(encodeAnnotations([_a('x', 1)]));
    expect(decoded['x']!.text, 'Hello');
    expect(decoded['x']!.color, HighlightColor.yellow);
    expect(decodeAnnotations('{"annotations":[{"id":1}]}'), isEmpty);
  });

  test('add, remove and sync across two devices', () async {
    final dir = await Directory.systemTemp.createTemp('notes');
    addTearDown(() => dir.delete(recursive: true));
    final remote = _MemoryRemote();
    final tablet = AnnotationStore(File('${dir.path}/a.json'), remote);
    final laptop = AnnotationStore(File('${dir.path}/b.json'), remote);
    await tablet.load();
    await laptop.load();

    final a = await tablet.add(
      bookId: 'book',
      bookTitle: 'Book',
      location: 'cfi',
      text: 'quote',
    );
    await tablet.flush();
    await laptop.sync();
    expect(laptop.forBook('book').single.text, 'quote');

    await laptop.remove(laptop.forBook('book').single);
    await laptop.flush();
    await tablet.sync();
    expect(tablet.all, isEmpty);
    expect(decodeAnnotations(remote.contents!)[a.id]!.deleted, isTrue);
  });

  test('exports Markdown grouped by book', () {
    final page = Annotation(
      id: 'p',
      bookId: 'pdf',
      bookTitle: 'Manual',
      location: 'page:12',
      text: '',
      note: 'check this',
      color: HighlightColor.blue,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final md = annotationsToMarkdown([_a('x', 1, note: 'nice'), page]);
    expect(md, contains('## Book\n\n> Hello\n\nnice'));
    expect(md, contains('## Manual\n\nBookmark, page 12\n\ncheck this'));
  });
}
