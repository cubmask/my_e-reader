import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/book.dart';
import '../library/book_health.dart';
import '../library/book_meta_store.dart';
import '../library/book_uploader.dart';
import '../library/converter.dart';
import '../library/cover_store.dart';
import '../library/duplicates.dart';
import '../library/metadata_sources.dart';
import '../library/metadata_updater.dart';
import '../library/new_books.dart';
import '../library/reading_stats.dart';
import '../notes/annotation_store.dart';
import '../notes/ink_store.dart';
import 'book_cache.dart';
import 'lookup.dart';
import 'progress_store.dart';
import 'reader_server.dart';
import 'reader_settings.dart';
import 'tts/voice_store.dart';

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
    DuplicateAlerts? duplicates,
    BookHealth? health,
    required this.server,
    required this.settings,
    this.voices,
    LookupService? lookup,
    ReadingStats? stats,
    this.uploader,
    this.converter,
  }) : duplicates = duplicates ?? DuplicateAlerts(),
       health = health ?? BookHealth(null, null),
       lookup = lookup ?? LookupService(http.Client()),
       stats = stats ?? ReadingStats(null, null, device: 'test');

  final BookCache cache;
  final ProgressStore progress;
  final AnnotationStore annotations;
  final BookMetaStore meta;
  final InkStore ink;
  final CoverStore covers;
  final MetadataUpdater metadata;
  final NewBooks newBooks;
  final DuplicateAlerts duplicates;

  /// Books that will not open, found by a check or in the reader.
  final BookHealth health;
  final ReaderServer server;
  final ReaderSettings settings;

  /// Dictionary and Wikipedia look-ups for selected text.
  final LookupService lookup;

  /// Time spent reading, the daily goal and finished books.
  final ReadingStats stats;

  /// Puts new files (annotated copies, conversions) into Drive.
  final BookUploader? uploader;

  /// Converts books to other formats with Google Docs.
  final BookConverter? converter;

  /// Books the reader added to Drive, for the library to list at once.
  final added = ValueNotifier<Book?>(null);

  /// Offline voices for reading aloud; the system voices when null.
  final VoiceStore? voices;

  /// A random id for this device, made once.
  static Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device.id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
      await prefs.setString('device.id', id);
    }
    return id;
  }

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
      health: BookHealth(api, File(p.join(dir.path, 'book_health.json'))),
      server: ReaderServer(drive: client),
      settings: ReaderSettings(),
      voices: VoiceStore(Directory(p.join(dir.path, 'voices'))),
      stats: ReadingStats(
        File(p.join(dir.path, 'stats.json')),
        DriveAppDataRemote(api, 'stats.json'),
        device: await _deviceId(),
      ),
      uploader: BookUploader(api),
      converter: BookConverter(api),
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
      services.duplicates.load(),
      services.health.load(),
      services.settings.load(),
      services.voices!.load(),
      services.stats.load(),
    ]);
    return services;
  }
}
