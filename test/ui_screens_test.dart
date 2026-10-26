import 'dart:io';

import 'package:ebook_reader/app.dart';
import 'package:ebook_reader/core/book_format.dart';
import 'package:ebook_reader/drive/drive_auth.dart';
import 'package:ebook_reader/library/book.dart';
import 'package:ebook_reader/library/book_meta_store.dart';
import 'package:ebook_reader/library/cover_store.dart';
import 'package:ebook_reader/library/library_controller.dart';
import 'package:ebook_reader/library/library_source.dart';
import 'package:ebook_reader/library/metadata_sources.dart';
import 'package:ebook_reader/library/metadata_updater.dart';
import 'package:ebook_reader/library/new_books.dart';
import 'package:ebook_reader/notes/annotation_store.dart';
import 'package:ebook_reader/notes/ink_store.dart';
import 'package:ebook_reader/reader/book_cache.dart';
import 'package:ebook_reader/reader/progress_store.dart';
import 'package:ebook_reader/reader/reader_server.dart';
import 'package:ebook_reader/reader/reader_services.dart';
import 'package:ebook_reader/reader/reader_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuth implements DriveAuth {
  @override
  Future<http.Client> signIn() async => http.Client();
  @override
  Future<void> signOut() async {}
}

class _FakeSource implements LibrarySource {
  _FakeSource(this.books);
  final List<Book> books;
  @override
  Future<List<Book>> listBooks() async => books;
}

Book _book(String id, String name, BookFormat format, int day) => Book(
  driveFileId: id,
  fileName: name,
  format: format,
  folderPath: 'Fiction',
  sizeBytes: 1200000,
  modifiedTime: DateTime.utc(2026, 1, day),
);

final books = [
  _book('a1', 'The Left Hand of Darkness.epub', BookFormat.epub, 1),
  _book('b2', 'Piranesi.epub', BookFormat.epub, 2),
  _book('c3', 'A Brief History of Time.pdf', BookFormat.pdf, 3),
  _book('d4', 'Dune.azw3', BookFormat.azw3, 4),
  _book('e5', 'Saga Vol 1.cbz', BookFormat.cbz, 5),
  _book('f6', 'Meeting notes.docx', BookFormat.docx, 6),
  _book('g7', 'Project Hail Mary.epub', BookFormat.epub, 7),
];

/// Signs in with fake services and a fake Drive folder, with some reading
/// progress so Home has something to show.
Future<LibraryController> signedIn(
  WidgetTester tester, {
  List<Book>? library,
}) async {
  late LibraryController controller;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({'library.folderId': 'root'});
    final dir = await Directory.systemTemp.createTemp('ui');
    addTearDown(() => dir.delete(recursive: true));
    final api = drive.DriveApi(MockClient((_) async => http.Response('', 404)));
    final meta = BookMetaStore(File('${dir.path}/m.json'), null);
    final covers = CoverStore(Directory('${dir.path}/covers'), null);
    final metadata = MetadataUpdater(
      MetadataService(MockClient((_) async => http.Response('', 404))),
      meta,
      covers,
    );
    await metadata.setAuto(false);
    final services = ReaderServices(
      cache: BookCache(api, Directory('${dir.path}/books')),
      progress: ProgressStore(File('${dir.path}/p.json'), null),
      annotations: AnnotationStore(File('${dir.path}/a.json'), null),
      meta: meta,
      ink: InkStore(null, null),
      covers: covers,
      metadata: metadata,
      newBooks: NewBooks(),
      server: ReaderServer(),
      settings: ReaderSettings(),
    );
    await services.meta.set('a1', author: 'Ursula K. Le Guin');
    await services.meta.set('b2', author: 'Susanna Clarke');
    await services.meta.set('d4', author: 'Frank Herbert');
    await services.meta.set('g7', author: 'Andy Weir');
    final now = DateTime.now();
    for (final (id, fraction, minutes) in [
      ('b2', 0.34, 1),
      ('d4', 0.71, 60),
      ('c3', 0.12, 600),
    ]) {
      await services.progress.save(
        id,
        ReadingProgress(
          location: 'x',
          fraction: fraction,
          updatedAt: now.subtract(Duration(minutes: minutes)),
        ),
      );
    }
    controller = LibraryController(
      auth: _FakeAuth(),
      sourceFactory: (_, _) => _FakeSource(library ?? books),
      servicesFactory: (_) async => services,
    );
    await controller.signIn();
  });
  return controller;
}

Future<void> pumpApp(
  WidgetTester tester,
  LibraryController controller,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ReaderApp(controller: controller));
  await tester.pump();
}

void main() {
  for (final (name, size) in [
    ('tablet', const Size(1848, 1155)),
    ('phone', const Size(400, 860)),
  ]) {
    testWidgets('Home shows the book in progress on a $name', (tester) async {
      final controller = await signedIn(tester);
      await pumpApp(tester, controller, size);
      expect(find.text('CONTINUE READING'), findsOneWidget);
      // Piranesi was read most recently.
      expect(find.text('Piranesi'), findsWidgets);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('Not started yet'), findsOneWidget);
      // Nothing arrived in Drive lately, so there is no hero.
      expect(find.textContaining('NEW IN YOUR DRIVE'), findsNothing);
      expect(find.text('Duplicates found'), findsNothing);
    });

    testWidgets('Home highlights books new in Drive on a $name', (
      tester,
    ) async {
      final added = Book(
        driveFileId: 'n1',
        fileName: 'The Ministry of Time.epub',
        format: BookFormat.epub,
        folderPath: '',
        createdTime: DateTime.now().subtract(const Duration(days: 1)),
      );
      final controller = await signedIn(tester, library: [...books, added]);
      await pumpApp(tester, controller, size);
      expect(find.text('NEW IN YOUR DRIVE'), findsOneWidget);
      expect(find.text('The Ministry of Time'), findsWidgets);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('NEW IN YOUR DRIVE'), findsNothing);
    });

    testWidgets('Duplicates are deleted after confirming on a $name', (
      tester,
    ) async {
      Book copy(String id, int day) => Book(
        driveFileId: id,
        fileName: id == 'c1' ? 'Circe.epub' : 'Circe (1).epub',
        format: BookFormat.epub,
        folderPath: '',
        md5: 'same',
        createdTime: DateTime.utc(2026, 1, day),
      );
      final controller = await signedIn(
        tester,
        library: [...books, copy('c1', 1), copy('c2', 9)],
      );
      await pumpApp(tester, controller, size);
      await tester.tap(find.text('Library').first);
      await tester.pump();
      // On a phone the chip is further along the scrolling row.
      await tester.ensureVisible(find.text('Duplicates · 1'));
      await tester.pump();
      await tester.tap(find.text('Duplicates · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Identical files'), findsOneWidget);

      // The newer copy is ticked; the other can't be, so one stays.
      await tester.tap(find.text('Delete 1 file'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this file permanently?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(controller.books.map((b) => b.driveFileId), contains('c1'));
      expect(controller.books.map((b) => b.driveFileId), isNot(contains('c2')));
      expect(find.text('No duplicates in your library.'), findsOneWidget);
    });

    testWidgets('Home deletes extra copies in one go on a $name', (
      tester,
    ) async {
      Book copy(String id, int day) => Book(
        driveFileId: id,
        fileName: 'Circe ($id).epub',
        format: BookFormat.epub,
        folderPath: '',
        sizeBytes: 2 * 1024 * 1024,
        md5: 'same',
        createdTime: DateTime.utc(2026, 1, day),
      );
      final controller = await signedIn(
        tester,
        library: [...books, copy('z1', 1), copy('z2', 5), copy('z3', 9)],
      );
      await pumpApp(tester, controller, size);
      expect(find.text('Duplicates found'), findsOneWidget);
      expect(find.textContaining('2 identical extra copies'), findsOneWidget);

      await tester.tap(find.text('Delete 2 extra copies'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files permanently?'), findsOneWidget);
      await tester.tap(find.text('Delete 2'));
      // Each delete touches the disk, which needs real time between frames.
      for (var i = 0; i < 10 && controller.books.length > 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final left = controller.books.map((b) => b.driveFileId);
      expect(left, contains('z1'));
      expect(left, isNot(contains('z2')));
      expect(left, isNot(contains('z3')));
      expect(find.text('Duplicates found'), findsNothing);
    });

    testWidgets('Library lists every book on a $name', (tester) async {
      final controller = await signedIn(tester);
      await pumpApp(tester, controller, size);
      await tester.tap(find.text('Library').first);
      await tester.pump();
      expect(find.text('All · 7'), findsOneWidget);
      expect(find.text('34%'), findsOneWidget);
      expect(find.text('NEW'), findsWidgets);

      // The "more" button opens the book's details.
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });
  }
}
