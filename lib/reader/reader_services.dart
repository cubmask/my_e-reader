import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/book_meta_store.dart';
import '../library/cover_store.dart';
import '../library/metadata_sources.dart';
import '../library/metadata_updater.dart';
import '../library/new_books.dart';
import '../notes/annotation_store.dart';
import '../notes/ink_store.dart';
import 'book_cache.dart';
import 'progress_store.dart';
import 'reader_server.dart';
import 'reader_settings.dart';

/// Everything the reader needs once the user is signed in.
class ReaderServices {
  ReaderServices({
    required this.cache,
    required this.progress,
    required this.annotations,
    required this.meta,
    required this.ink,
    required this.covers,
    required this.metadata,
    required this.newBooks,
    required this.server,
    required this.settings,
  });

  final BookCache cache;
  final ProgressStore progress;
  final AnnotationStore annotations;
  final BookMetaStore meta;
  final InkStore ink;
  final CoverStore covers;
  final MetadataUpdater metadata;
  final NewBooks newBooks;
  final ReaderServer server;
  final ReaderSettings settings;

  static Future<ReaderServices> create(http.Client client) async {
    final api = drive.DriveApi(client);
    final dir = await getApplicationSupportDirectory();
    // Blocks of PDFs streamed in an earlier session; their URLs change with
    // every launch, so they are never reused.
    final pdfBlocks = Directory(
      p.join((await getTemporaryDirectory()).path, 'pdfrx.cache'),
    );
    if (await pdfBlocks.exists()) {
      await pdfBlocks.delete(recursive: true).catchError((_) => pdfBlocks);
    }
    final meta = BookMetaStore(
      File(p.join(dir.path, 'library.json')),
      DriveAppDataRemote(api, 'library.json'),
    );
    final covers = CoverStore(Directory(p.join(dir.path, 'covers')), client);
    final services = ReaderServices(
      cache: BookCache(api, Directory(p.join(dir.path, 'books'))),
      progress: ProgressStore(
        File(p.join(dir.path, 'progress.json')),
        DriveAppDataRemote(api, 'progress.json'),
      ),
      annotations: AnnotationStore(
        File(p.join(dir.path, 'annotations.json')),
        DriveAppDataRemote(api, 'annotations.json'),
      ),
      meta: meta,
      ink: InkStore(
        File(p.join(dir.path, 'ink.json')),
        DriveAppDataRemote(api, 'ink.json'),
      ),
      covers: covers,
      // A plain client: the Google sign-in token is only for Drive.
      metadata: MetadataUpdater(
        MetadataService(
          http.Client(),
          googleApiKey: const String.fromEnvironment('GOOGLE_BOOKS_API_KEY'),
        ),
        meta,
        covers,
      ),
      newBooks: NewBooks(),
      server: ReaderServer(drive: client),
      settings: ReaderSettings(),
    );
    await Future.wait([
      services.progress.load(),
      services.annotations.load(),
      services.meta.load(),
      services.ink.load(),
      services.cache.load(),
      services.covers.load(),
      services.metadata.load(),
      services.newBooks.load(),
      services.settings.load(),
    ]);
    return services;
  }
}
