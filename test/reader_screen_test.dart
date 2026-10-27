import 'dart:io';

import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_meta_store.dart';
import 'package:ebook_reader/library/cover_store.dart';
import 'package:ebook_reader/library/metadata_sources.dart';
import 'package:ebook_reader/library/metadata_updater.dart';
import 'package:ebook_reader/library/new_books.dart';
import 'package:ebook_reader/notes/annotation_store.dart';
import 'package:ebook_reader/notes/ink_store.dart';
import 'package:ebook_reader/reader/book_cache.dart';
import 'package:ebook_reader/reader/pdf_book_view.dart';
import 'package:ebook_reader/reader/progress_store.dart';
import 'package:ebook_reader/reader/reader_screen.dart';
import 'package:ebook_reader/reader/reader_server.dart';
import 'package:ebook_reader/reader/reader_services.dart';
import 'package:ebook_reader/reader/reader_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a PDF builds its viewer before the document has opened', (
    tester,
  ) async {
    late ReaderServices services;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('reader');
      addTearDown(() => dir.delete(recursive: true));
      final api = drive.DriveApi(
        MockClient((_) async => http.Response('', 404)),
      );
      final meta = BookMetaStore(File('${dir.path}/m.json'), null);
      final covers = CoverStore(Directory('${dir.path}/covers'), null);
      services = ReaderServices(
        cache: BookCache(api, Directory('${dir.path}/books')),
        progress: ProgressStore(File('${dir.path}/p.json'), null),
        annotations: AnnotationStore(File('${dir.path}/a.json'), null),
        meta: meta,
        ink: InkStore(null, null),
        covers: covers,
        metadata: MetadataUpdater(
          MetadataService(MockClient((_) async => http.Response('', 404))),
          meta,
          covers,
        ),
        newBooks: NewBooks(),
        server: ReaderServer(),
        settings: ReaderSettings(),
      );
      // Start the loopback server outside the test's fake clock.
      await services.server.driveUrl('p1');
    });
    addTearDown(() => tester.runAsync(services.server.close));
    final book = Book(
      driveFileId: 'p1',
      fileName: 'Manual.pdf',
      format: BookFormat.pdf,
      folderPath: '',
      sizeBytes: 4096,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(book: book, services: services),
      ),
    );
    // The stream URL arrives from the loopback server.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PdfBookView), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.pumpWidget(const SizedBox());
    // Let the debounced saves of progress and reading time run.
    await tester.pump(const Duration(minutes: 2));
  });
}
