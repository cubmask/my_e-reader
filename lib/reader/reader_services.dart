import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/book_meta_store.dart';
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
    required this.server,
    required this.settings,
  });

  final BookCache cache;
  final ProgressStore progress;
  final AnnotationStore annotations;
  final BookMetaStore meta;
  final InkStore ink;
  final ReaderServer server;
  final ReaderSettings settings;

  static Future<ReaderServices> create(http.Client client) async {
    final api = drive.DriveApi(client);
    final dir = await getApplicationSupportDirectory();
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
      meta: BookMetaStore(
        File(p.join(dir.path, 'library.json')),
        DriveAppDataRemote(api, 'library.json'),
      ),
      ink: InkStore(
        File(p.join(dir.path, 'ink.json')),
        DriveAppDataRemote(api, 'ink.json'),
      ),
      server: ReaderServer(),
      settings: ReaderSettings(),
    );
    await Future.wait([
      services.progress.load(),
      services.annotations.load(),
      services.meta.load(),
      services.ink.load(),
      services.settings.load(),
    ]);
    return services;
  }
}
