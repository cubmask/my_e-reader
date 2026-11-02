import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/book_format.dart';
import '../../library/book.dart';
import '../../library/library_controller.dart';
import '../../notes/annotation_store.dart' show PdfTextLocation;
import '../pdf_book_view.dart';
import '../progress_store.dart';
import '../read_aloud.dart';
import '../reader_services.dart';
import '../tts/background_audio.dart';
import '../web_book_view.dart';
import 'car_library.dart';

/// Something to tell the driver, such as a book that needs a signal.
class CarError implements Exception {
  const CarError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What Android Auto browses and plays from, beyond the book open on screen.
abstract interface class CarSource {
  /// The library, signing in quietly if the app was started by the car;
  /// null when the user has to sign in on the phone.
  Future<CarLibrary?> library();

  /// Starts reading the book aloud with no screen. Throws [CarError].
  Future<void> play(String driveFileId);
}

/// Reads books aloud that were started from Android Auto, in a hidden
/// reader, saving the reading position as it goes so the book opens at the
/// same sentence on the phone.
class CarPlayer implements CarSource {
  CarPlayer(this._controller);

  final LibraryController _controller;
  _CarSession? _session;

  @override
  Future<CarLibrary?> library() async {
    final c = _controller;
    if (c.status == LibraryStatus.signedOut) await c.signIn(quietly: true);
    if (c.status == LibraryStatus.loading) {
      final done = Completer<void>();
      void check() {
        if (c.status != LibraryStatus.loading && !done.isCompleted) {
          done.complete();
        }
      }

      c.addListener(check);
      try {
        await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      } finally {
        c.removeListener(check);
      }
    }
    final services = c.services;
    if (services == null || c.status != LibraryStatus.ready) return null;
    return libraryOf(c.books, services);
  }

  /// The car's view of [books].
  static CarLibrary libraryOf(List<Book> books, ReaderServices services) =>
      CarLibrary(
        books: books,
        titleOf: services.meta.titleOf,
        authorOf: services.meta.authorOf,
        coverOf: services.covers.coverOf,
        collectionsOf: services.meta.collectionsOf,
        openedAt: (b) => services.progress[b.driveFileId]?.updatedAt,
        fractionOf: (b) => services.progress[b.driveFileId]?.fraction,
        isOffline: (b) =>
            services.cache.isDownloaded(b) ||
            services.cache.isAvailableOffline(b),
      );

  @override
  Future<void> play(String driveFileId) async {
    final library = await this.library();
    final services = _controller.services;
    if (library == null || services == null) {
      throw const CarError("Sign in on your phone when it's safe");
    }
    final entry = library.byId(driveFileId);
    if (entry == null) {
      throw const CarError('That book is no longer in your library');
    }
    final book = entry.book;
    if (!canReadInCar(book.format)) {
      throw CarError('${book.format.label} books can’t be read aloud');
    }
    final current = _session;
    if (current != null && current.book.driveFileId == driveFileId) {
      return current.resume();
    }
    _session = null;
    await current?.dispose();

    final offline = library.isOffline(book);
    final file = await services.cache
        .open(book)
        .timeout(const Duration(seconds: 45))
        .catchError(
          (Object e) => throw CarError(
            offline
                ? 'This book couldn’t be opened'
                : 'This book isn’t downloaded and there’s no signal',
          ),
        );
    final session = _session = _CarSession(
      book: book,
      services: services,
      title: entry.title,
      author: entry.author,
      onReleased: (s) {
        if (_session == s) _session = null;
        s.dispose();
      },
    );
    try {
      await session.open(file);
    } catch (e) {
      if (_session == session) _session = null;
      await session.dispose();
      if (e is CarError) rethrow;
      debugPrint('Car reader failed: $e');
      throw const CarError('This book couldn’t be opened');
    }
    await session.start();
  }
}

/// Whether read aloud can follow the book with no screen: reflowable books
/// (office documents become EPUBs) and PDFs; not comics or DjVu.
bool canReadInCar(BookFormat format) =>
    format == BookFormat.pdf || format.engine == ReaderEngine.reflowable;

/// One book being read aloud in the car.
class _CarSession {
  _CarSession({
    required this.book,
    required this.services,
    required this.title,
    required this.author,
    required this.onReleased,
  }) : reader = ReadAloud(voices: services.voices);

  final Book book;
  final ReaderServices services;
  final String title;
  final String author;
  final ReadAloud reader;
  final void Function(_CarSession) onReleased;

  HeadlessWebBook? _web;
  PdfDocument? _pdf;
  int _page = 1;
  List<TocItem> _toc = const [];
  String _chapter = '';
  bool _disposed = false;

  bool get _isPdf => _pdf != null;

  ReadingProgress? get _saved =>
      services.progress.ownOf(book.driveFileId) ??
      services.progress[book.driveFileId];

  Future<void> open(File file) async {
    final saved = _saved;
    if (book.format == BookFormat.pdf) {
      final pdf = _pdf = await PdfDocument.openFile(file.path);
      final location = saved?.location ?? '';
      _page =
          (int.tryParse(location.replaceFirst('page:', '')) ??
                  PdfTextLocation.parse(location)?.ranges.first.page ??
                  1)
              .clamp(1, pdf.pages.length);
      final outline = await pdf.loadOutline().catchError(
        (_) => <PdfOutlineNode>[],
      );
      final toc = <TocItem>[];
      void walk(List<PdfOutlineNode> nodes, int depth) {
        for (final n in nodes) {
          if (n.dest case final dest?) {
            toc.add(TocItem(n.title.trim(), 'page:${dest.pageNumber}', depth));
          }
          walk(n.children, depth + 1);
        }
      }

      walk(outline, 0);
      _toc = toc;
      _chapter = _pdfChapter(_page);
    } else {
      var location = saved?.location;
      if (location != null && location.startsWith('page:')) location = null;
      final web = _web = await HeadlessWebBook.open(
        file: file,
        fileName: book.format.needsConversion
            ? '${book.displayTitle}.epub'
            : book.fileName,
        server: services.server,
        settings: services.settings,
        location: location,
        onRelocate: _relocated,
      );
      _toc = web.toc;
    }
  }

  String _pdfChapter(int page) {
    String chapter = '';
    for (final item in _toc) {
      final start = int.tryParse(item.href.substring(5));
      if (start != null && start <= page) chapter = item.label;
    }
    return chapter;
  }

  void _chapterIs(String chapter) {
    if (chapter == _chapter) return;
    if (_chapter.isNotEmpty) reader.chapterEnded();
    _chapter = chapter;
    BackgroundAudio.instance.setChapter(reader, chapter);
  }

  void _relocated(String cfi, double fraction, String chapter) {
    if (_disposed) return;
    _chapterIs(chapter);
    _save(cfi, fraction);
  }

  Future<void> _turnTo(int page) async {
    _page = page;
    final count = _pdf?.pages.length ?? 1;
    _chapterIs(_pdfChapter(page));
    _save('page:$page', count <= 1 ? 1 : (page - 1) / (count - 1));
  }

  void _save(String location, double fraction) {
    if (fraction >= 0.995) services.stats.markFinished(book.driveFileId);
    services.progress.save(
      book.driveFileId,
      ReadingProgress(
        location: location,
        fraction: fraction,
        updatedAt: DateTime.now(),
        chapter: _chapter,
      ),
    );
  }

  SpeechSource _source() {
    if (_pdf case final pdf?) {
      return PdfSpeechSource.pages(
        pageCount: () => pdf.pages.length,
        page: (n) => pdf.pages[n - 1],
        startPage: () => _page,
        turnTo: _turnTo,
      );
    }
    return _web!.speech();
  }

  NowReading _nowReading() => NowReading(
    id: book.driveFileId,
    title: title,
    author: author,
    cover: services.covers.coverOf(book),
    chapter: _chapter,
    byChapter: !_isPdf,
    start: start,
    nextChapter: _toc.isEmpty ? null : () => _skipChapter(1),
    previousChapter: _toc.isEmpty ? null : () => _skipChapter(-1),
    released: () => onReleased(this),
  );

  Future<void> start() async {
    if (_disposed) return;
    await BackgroundAudio.instance.attach(reader, _nowReading());
    unawaited(reader.play(_source()));
  }

  Future<void> resume() async {
    if (reader.active) return reader.resume();
    await start();
  }

  Future<void> _skipChapter(int step) async {
    final current = _toc.indexWhere((item) => item.label == _chapter);
    final target = current < 0 ? (step > 0 ? 0 : -1) : current + step;
    if (target < 0 || target >= _toc.length) return;
    final item = _toc[target];
    await reader.stop();
    if (item.href.startsWith('page:')) {
      await _turnTo(int.tryParse(item.href.substring(5)) ?? _page);
    } else {
      await _web?.controller.goTo(item.href);
    }
    await start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await services.progress.flush();
    BackgroundAudio.instance.detach(reader);
    await reader.stop();
    reader.dispose();
    await _web?.dispose();
    await _pdf?.dispose();
  }
}
