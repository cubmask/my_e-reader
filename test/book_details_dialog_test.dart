import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_meta_store.dart';
import 'package:ebook_reader/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('edits series, tags and rating', (tester) async {
    final dir = Directory.systemTemp.createTempSync('dialog');
    addTearDown(() => dir.deleteSync(recursive: true));
    final meta = BookMetaStore(File('${dir.path}/library.json'), null);
    const book = Book(
      driveFileId: 'b',
      fileName: 'Dune.epub',
      format: BookFormat.epub,
      folderPath: '',
    );
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailsDialog(book: book, meta: meta),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Series'),
      'Dune Chronicles',
    );
    await tester.enterText(find.widgetWithText(TextField, 'No.'), '1');
    await tester.enterText(find.widgetWithText(TextField, 'New tag'), 'sci-fi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final star = find.byIcon(Icons.star_border_rounded).at(3);
    await tester.ensureVisible(star);
    await tester.pumpAndSettle();
    await tester.tap(star);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final m = meta['b']!;
    expect(m.series, 'Dune Chronicles');
    expect(m.seriesIndex, 1);
    expect(m.tags, ['sci-fi']);
    expect(m.myRating, 4);
  });
}
