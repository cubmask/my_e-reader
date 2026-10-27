import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/book_format.dart';
import '../core/platform_bridge.dart';
import '../core/file_type.dart';
import '../library/book.dart';
import '../library/cover_store.dart' show CoverKind;
import '../notes/annotation_store.dart';
import '../ui/breakpoints.dart';
import '../ui/theme.dart';
import '../ui/voice_settings.dart';
import 'appearance_sheet.dart';
import 'book_cache.dart';
import 'book_search.dart';
import 'ink_layer.dart';
import 'lookup.dart';
import 'pdf_book_view.dart';
import 'pdf_highlights.dart';
import 'progress_store.dart';
import 'reader_chrome.dart';
import 'read_aloud.dart';
import 'tts/background_audio.dart';
import 'tts/voice_pack.dart';
import 'reader_services.dart';
import 'reader_settings.dart';
import 'web_book_view.dart';

export 'reader_chrome.dart' show highlightSwatches;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.services,
    this.openAt,
  });

  final Book book;
  final ReaderServices services;

  /// A location to open at instead of the saved reading position, such as a
  /// note picked from the Notes screen.
  final String? openAt;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _web = WebBookController();
  final _pdf = PdfViewerController();
  late final _readAloud = ReadAloud(voices: services.voices);
  final _ink = InkController();
  late final _pdfSearch = PdfBookSearch(_pdf);
  bool _pdfSearchUsed = false;
  late final _pdfHighlighter = PdfHighlighter(
    _pdf,
    () => [
      for (final a in annotations.forBook(book.driveFileId))
        if (PdfTextLocation.parse(a.location) case final location?)
          (location: location, color: highlightSwatches[a.color]!),
    ],
  );
  File? _file;

  /// Set instead of [_file] when a PDF is paged in straight from Drive.
  Uri? _streamUrl;
  bool get _ready => _file != null || _streamUrl != null;
  double? _download;
  String? _error;
  bool _controls = true;
  late String _title = services.meta.titleOf(widget.book);
  List<TocItem> _toc = const [];
  double _fraction = 0;
  String _chapter = '';
  String _location = '';

  /// Selected text: a CFI in a web book, a [PdfTextLocation] in a PDF.
  ({String cfi, String text})? _selection;

  Book get book => widget.book;
  ReaderServices get services => widget.services;
  AnnotationStore get annotations => services.annotations;

  /// The format the book opens as: what its contents turned out to be, which
  /// can differ from what its name says (see [_fetch]).
  late BookFormat _format = book.format;
  bool get _isPdf => _format == BookFormat.pdf;

  BookSearch get _search {
    if (!_isPdf) return _web.search;
    _pdfSearchUsed = true;
    return _pdfSearch;
  }

  @override
  void initState() {
    super.initState();
    services.settings.addListener(_applyScreen);
    _applyScreen();
    final saved = services.progress[book.driveFileId];
    _fraction = saved?.fraction ?? 0;
    _location = widget.openAt ?? saved?.location ?? '';
    if (services.cache.canStreamDirectly(book)) {
      services.server
          .driveUrl(book.driveFileId)
          .then((url) => setState(() => _streamUrl = url));
      return;
    }
    _fetch();
  }

  /// Opens a local copy, fetching the whole book from Drive if needed.
  Future<void> _fetch() async {
    void progress(double v) {
      if (mounted) setState(() => _download = v);
    }

    try {
      var file = await services.cache.open(book, onProgress: progress);
      var format = book.format;
      // Converted office documents are always EPUBs; anything else may be
      // misnamed, so its contents decide how it opens.
      if (!book.format.needsConversion) {
        final actual = await sniffFile(file);
        final open = formatToOpen(book.format, actual);
        if (open == null) {
          if (mounted) {
            setState(() {
              _error =
                  'This file is really $actual, not ${_article(book.format)}, '
                  'so it cannot be opened as a book.';
            });
          }
          return;
        }
        if (open.needsConversion) {
          if (mounted) setState(() => _download = null);
          file = await services.cache.convertMisnamed(
            book,
            file,
            open,
            onProgress: progress,
          );
          format = BookFormat.epub;
        } else {
          format = open;
        }
      }
      if (!mounted) return;
      setState(() {
        _file = file;
        _format = format;
        // A saved page number means nothing to the reflowable engine.
        if (format != BookFormat.pdf && _location.startsWith('page:')) {
          _location = '';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static String _article(BookFormat format) {
    const an = {'EPUB', 'AZW3', 'FB2', 'RTF', 'ODT'};
    return '${an.contains(format.label) ? 'an' : 'a'} ${format.label}';
  }

  @override
  void dispose() {
    BackgroundAudio.instance.detach(_readAloud);
    _readAloud.dispose();
    services.settings.removeListener(_applyScreen);
    PlatformBridge.instance.setBrightness(null);
    PlatformBridge.instance.keepScreenOn(false);
    _ink.dispose();
    _web.search.dispose();
    if (_pdfSearchUsed) _pdfSearch.dispose();
    services.ink.flush();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    services.progress.flush();
    annotations.flush();
    super.dispose();
  }

  double? _brightness;
  bool? _awake;
  late ReaderTheme _theme = services.settings.theme;
  late bool _spread = services.settings.spread;

  /// Brightness and keep-awake from the reading settings, sent only when
  /// they change.
  void _applyScreen() {
    final settings = services.settings;
    if (settings.brightness != _brightness) {
      _brightness = settings.brightness;
      PlatformBridge.instance.setBrightness(_brightness);
    }
    if (settings.keepAwake != _awake) {
      _awake = settings.keepAwake;
      PlatformBridge.instance.keepScreenOn(_awake!);
    }
    // The page colour and the two-page layout are drawn here.
    if (settings.theme != _theme || settings.spread != _spread) {
      _theme = settings.theme;
      _spread = settings.spread;
      if (mounted) setState(() {});
    }
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    SystemChrome.setEnabledSystemUIMode(
      _controls ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _save(String location, double fraction) {
    setState(() {
      _fraction = fraction;
      _location = location;
    });
    services.progress.save(
      book.driveFileId,
      ReadingProgress(
        location: location,
        fraction: fraction,
        updatedAt: DateTime.now(),
      ),
    );
  }

  int get _initialPdfPage =>
      int.tryParse(_location.replaceFirst('page:', '')) ??
      PdfTextLocation.parse(_location)?.ranges.first.page ??
      1;

  Future<void> _goTo(Annotation a) async {
    if (a.page case final page? when _isPdf) {
      await _pdf.goToPage(pageNumber: page);
    } else {
      await _web.goTo(a.location);
    }
  }

  // Highlights and notes

  Future<void> _highlight(HighlightColor color, {String note = ''}) async {
    final selection = _selection;
    if (selection == null) return;
    setState(() => _selection = null);
    await annotations.add(
      bookId: book.driveFileId,
      bookTitle: _title,
      location: selection.cfi,
      text: selection.text,
      note: note,
      color: color,
    );
    await _drawHighlight(selection.cfi, color);
  }

  Future<void> _drawHighlight(String location, HighlightColor color) async {
    if (_isPdf) {
      await _clearSelection();
      if (_pdf.isReady) _pdf.invalidate();
    } else {
      await _web.addHighlight(location, color.name);
    }
  }

  Future<void> _clearSelection() async {
    if (!_isPdf) return _web.clearSelection();
    if (_pdf.isReady) await _pdf.textSelectionDelegate.clearTextSelection();
  }

  Future<void> _highlightWithNote() async {
    final note = await _editNote(context, '');
    if (note != null) await _highlight(HighlightColor.yellow, note: note);
  }

  Annotation? get _bookmarkHere =>
      annotations.forBook(book.driveFileId).where((a) {
        if (!a.isBookmark) return false;
        return a.location == _location;
      }).firstOrNull;

  Future<void> _toggleBookmark() async {
    final existing = _bookmarkHere;
    if (existing != null) {
      await annotations.remove(existing);
    } else if (_location.isNotEmpty) {
      await annotations.add(
        bookId: book.driveFileId,
        bookTitle: _title,
        location: _location,
        note: _chapter,
      );
    }
    setState(() {});
  }

  Future<void> _openAnnotation(Annotation a) async {
    final result = await showModalBottomSheet<_AnnotationAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _AnnotationSheet(annotation: a),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _Recolor(:final color):
        await annotations.update(a.copyWith(color: color));
        await _drawHighlight(a.location, color);
      case _EditNote():
        final note = await _editNote(context, a.note);
        if (note != null) await annotations.update(a.copyWith(note: note));
      case _Delete():
        await annotations.remove(a);
        if (_isPdf) {
          if (_pdf.isReady) _pdf.invalidate();
        } else if (!a.isBookmark) {
          await _web.removeHighlight(a.location);
        }
    }
    setState(() {});
  }

  void _showNotes() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: annotations,
        builder: (context, _) {
          final items = annotations.forBook(book.driveFileId);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            builder: (context, scroll) => items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Select text to highlight it, or use the bookmark '
                        'button to mark a page.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    controller: scroll,
                    children: [
                      for (final a in items)
                        AnnotationTile(
                          annotation: a,
                          onTap: () {
                            Navigator.of(context).pop();
                            _goTo(a);
                          },
                          onLongPress: () => _openAnnotation(a),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _showSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) =>
              SearchPanel(search: _search, scroll: scroll),
        ),
      ),
    );
  }

  /// A PDF's outline becomes its contents.
  Future<void> _loadOutline(PdfDocument document) async {
    final outline = await document.loadOutline().catchError(
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
    if (mounted && toc.isNotEmpty) setState(() => _toc = toc);
  }

  // Read aloud

  Future<void> _toggleReadAloud() async {
    if (_readAloud.active) return _readAloud.stop();
    setState(() => _controls = true);
    await BackgroundAudio.instance.attach(_readAloud, title: _title);
    await _readAloud.play(
      _isPdf ? PdfSpeechSource(_pdf) : WebSpeechSource(_web),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background(),
      endDrawer: _toc.isEmpty ? null : _buildToc(),
      body: LayoutBuilder(
        builder: (context, box) {
          final spread =
              services.settings.spread &&
              box.maxWidth > box.maxHeight &&
              box.maxWidth >= Breakpoints.expanded;
          return ListenableBuilder(
            listenable: Listenable.merge([_readAloud, _ink, ?services.voices]),
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(child: _buildBody(spread)),
                if (_controls || _readAloud.active)
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                if (_ink.enabled)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: InkToolbar(
                            controller: _ink,
                            store: services.ink,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (_selection != null)
                  Positioned(
                    bottom: 32,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _buildSelectionBar(),
                        ),
                      ),
                    ),
                  )
                else if (_ready && (_controls || _readAloud.active))
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _background() => switch (services.settings.theme) {
    ReaderTheme.light => const Color(0xFFFBF9F4),
    ReaderTheme.sepia => const Color(0xFFF4ECD8),
    ReaderTheme.dark => const Color(0xFF1B1A18),
  };

  Widget _buildBody(bool spread) {
    if (_error != null) return _Notice('Could not open this book.\n$_error');
    final file = _file;
    if (_isPdf && _ready) {
      return SafeArea(
        child: PdfBookView(
          file: file,
          streamUrl: _streamUrl,
          controller: _pdf,
          initialPage: _initialPdfPage,
          spread: spread,
          onToggleControls: _toggleControls,
          onStreamFailed: () {
            setState(() => _streamUrl = null);
            _fetch();
          },
          bookId: book.driveFileId,
          paintSearch: (_search as PdfBookSearch).paint,
          highlighter: _pdfHighlighter,
          onSelection: (selection) => setState(
            () => _selection = selection == null
                ? null
                : (cfi: selection.location, text: selection.text),
          ),
          onHighlightTapped: (location) {
            final a = annotations.byLocation(book.driveFileId, location);
            if (a != null) _openAnnotation(a);
          },
          onReady: _loadOutline,
          ink: services.ink,
          inkController: _ink,
          onPageChanged: (page, count) =>
              _save('page:$page', count <= 1 ? 1 : (page - 1) / (count - 1)),
        ),
      );
    }
    if (file == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              child: LinearProgressIndicator(value: _download),
            ),
            const SizedBox(height: 12),
            Text(
              book.format.needsConversion
                  ? 'Converting with Google Drive'
                  : 'Opening from Google Drive',
            ),
          ],
        ),
      );
    }
    return SafeArea(
      child: WebBookView(
        file: file,
        // Converted office documents are EPUBs.
        fileName: book.format.needsConversion
            ? '${book.displayTitle}.epub'
            : _format == book.format
            ? book.fileName
            : '${book.displayTitle}${_format.extensions.first}',
        format: _format,
        server: services.server,
        controller: _web,
        settings: services.settings,
        columns: spread ? 2 : 1,
        initialLocation: _location.isEmpty ? null : _location,
        highlights: [
          for (final a in annotations.forBook(book.driveFileId))
            if (!a.isBookmark) (cfi: a.location, color: a.color.name),
        ],
        onRelocate: (cfi, fraction, chapter) {
          _chapter = chapter;
          _save(cfi, fraction);
        },
        onSelection: (selection) => setState(() => _selection = selection),
        onHighlightTapped: (cfi) {
          final a = annotations.byLocation(book.driveFileId, cfi);
          if (a != null) _openAnnotation(a);
        },
        onOpened: (title, author, toc) => setState(() {
          // A converted document's title is its temporary copy's name.
          if (!book.format.needsConversion) {
            services.meta.fillIn(
              book.driveFileId,
              // Comics and DjVu have no metadata and report the file name.
              title: title == book.fileName || title == book.displayTitle
                  ? null
                  : title,
              author: author,
            );
          }
          _title = services.meta.titleOf(book);
          _toc = toc;
          _controls = false;
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }),
        onError: (message) => setState(() => _error = message),
        onToggleControls: _toggleControls,
        onCover: (jpeg) =>
            services.covers.save(book.driveFileId, CoverKind.book, jpeg),
      ),
    );
  }

  /// Floating controls tinted like the page, in light or dark to match the
  /// reading theme.
  Widget _chrome(Widget child) {
    final dark = services.settings.theme == ReaderTheme.dark;
    final base = Theme.of(context);
    if (dark == (base.brightness == Brightness.dark)) return child;
    return Theme(
      data: buildAppTheme(dark ? Brightness.dark : Brightness.light),
      child: child,
    );
  }

  Widget _buildTopBar() {
    final paper = _background();
    return _chrome(
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FloatingPill(
                paper: paper,
                padding: const EdgeInsets.all(4),
                child: const BackButton(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: FloatingPill(
                    paper: paper,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontFamily: AppFonts.serif),
                        ),
                        if (_chapter.isNotEmpty)
                          Text(
                            _chapter,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingPill(
                paper: paper,
                padding: const EdgeInsets.all(4),
                child: _ready
                    ? _DownloadButton(book: book, cache: services.cache)
                    : const SizedBox.square(dimension: 48),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final selection = _selection!;
    return _chrome(
      SelectionPopover(
        paper: _background(),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: selection.text));
          _clearSelection();
          setState(() => _selection = null);
        },
        onReadAloud: () async {
          _clearSelection();
          setState(() {
            _selection = null;
            _controls = true;
          });
          await BackgroundAudio.instance.attach(_readAloud, title: _title);
          await _readAloud.play(
            PassageSpeechSource(selection.text, language: _web.language),
          );
        },
        onHighlight: _highlight,
        onNote: _highlightWithNote,
        onLookUp: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          builder: (context) => LookupSheet(
            service: services.lookup,
            text: selection.text,
            language: _isPdf ? null : _web.language,
          ),
        ),
        onShare: PlatformBridge.instance.available
            ? () {
                final author = services.meta.authorOf(book);
                PlatformBridge.instance.shareText(
                  '“${selection.text}”\n— $_title${author.isEmpty ? '' : ', $author'}',
                );
                _clearSelection();
                setState(() => _selection = null);
              }
            : null,
      ),
    );
  }

  Widget _buildBottomBar() {
    final isWeb = !_isPdf;
    final paper = _background();
    final bookmarked = _bookmarkHere != null;
    final percent = Text('${(_fraction * 100).round()}%');
    final toolbar = Builder(
      builder: (context) => ReaderToolbar(
        paper: paper,
        items: [
          if (_toc.isNotEmpty)
            ToolbarItem(
              icon: Icons.format_list_bulleted,
              tooltip: 'Contents',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ToolbarItem(
            icon: Icons.search,
            tooltip: 'Search this book',
            onPressed: _showSearch,
          ),
          ToolbarItem(
            icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
            tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark this page',
            onPressed: _toggleBookmark,
          ),
          ToolbarItem(
            icon: _readAloud.active
                ? Icons.stop_rounded
                : Icons.headphones_outlined,
            tooltip: _readAloud.active ? 'Stop reading aloud' : 'Read aloud',
            selected: _readAloud.active,
            onPressed: _toggleReadAloud,
          ),
          ToolbarItem(
            icon: Icons.sticky_note_2_outlined,
            tooltip: 'Notes and highlights',
            onPressed: _showNotes,
          ),
          if (_isPdf)
            ToolbarItem(
              icon: _ink.enabled ? Icons.draw : Icons.draw_outlined,
              tooltip: _ink.enabled ? 'Stop writing' : 'Write with pen',
              selected: _ink.enabled,
              onPressed: () => _ink.enabled = !_ink.enabled,
            ),
          ToolbarItem(
            icon: Icons.light_mode_outlined,
            tooltip: 'Appearance',
            onPressed: _showAppearance,
          ),
        ],
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              child: Slider(
                value: _fraction.clamp(0, 1),
                onChanged: (v) => setState(() => _fraction = v),
                onChangeEnd: isWeb ? _web.goToFraction : _goToPdfFraction,
              ),
            ),
            SizedBox(width: 44, child: percent),
          ],
        ),
      ),
    );
    Widget turn(IconData icon, String tooltip, VoidCallback onPressed) =>
        FloatingPill(
          paper: paper,
          padding: const EdgeInsets.all(4),
          child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
        );
    return _chrome(
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_readAloud.active) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: FloatingPill(
                    paper: paper,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: _buildSpeedRow(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  if (isWeb) turn(Icons.arrow_back, 'Previous page', _web.prev),
                  Expanded(
                    child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: toolbar),
                    ),
                  ),
                  if (isWeb) turn(Icons.arrow_forward, 'Next page', _web.next),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goToPdfFraction(double fraction) {
    if (!_pdf.isReady) return;
    final count = _pdf.pageCount;
    _pdf.goToPage(pageNumber: (fraction * (count - 1)).round() + 1);
  }

  /// Which voice is reading, such as "German · Supertonic 3".
  String _voiceLabel() {
    final language = _readAloud.language;
    if (language == null) return 'Reading aloud';
    final voice = services.voices?.describe(language) ?? 'System voice';
    return '${languageName(language)} · $voice';
  }

  void _showVoiceSettings() {
    final voices = services.voices;
    if (voices == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: VoiceSettings(voices: voices, preview: !_readAloud.active),
        ),
      ),
    );
  }

  Widget _buildSpeedRow() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    return Row(
      children: [
        IconButton(
          tooltip: _readAloud.paused ? 'Resume' : 'Pause',
          icon: Icon(_readAloud.paused ? Icons.play_arrow : Icons.pause),
          onPressed: _readAloud.paused ? _readAloud.resume : _readAloud.pause,
        ),
        Flexible(
          child: TextButton.icon(
            icon: const Icon(Icons.record_voice_over, size: 20),
            label: Text(
              _voiceLabel(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: services.voices == null ? null : _showVoiceSettings,
          ),
        ),
        const Spacer(),
        SegmentedButton<double>(
          showSelectedIcon: false,
          segments: [
            for (final s in speeds)
              ButtonSegment(value: s, label: Text('${s}x')),
          ],
          selected: {_readAloud.speed},
          onSelectionChanged: (v) => _readAloud.setSpeed(v.first),
        ),
      ],
    );
  }

  Widget _buildToc() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: Text(
                'Contents',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final item in _toc)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16.0 + item.depth * 16,
                  right: 16,
                ),
                title: Text(item.label),
                onTap: () {
                  Navigator.of(context).pop();
                  final page = item.href.startsWith('page:')
                      ? int.tryParse(item.href.substring(5))
                      : null;
                  if (page != null) {
                    _pdf.goToPage(pageNumber: page);
                  } else {
                    _web.goTo(item.href);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAppearance() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => AppearanceSheet(
          settings: services.settings,
          reflowable: _format.engine == ReaderEngine.reflowable,
          scroll: scroll,
        ),
      ),
    );
  }
}

/// Asks for note text; returns null when cancelled.
Future<String?> _editNote(BuildContext context, String initial) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Note'),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: field,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(field.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(field.dispose);
}

sealed class _AnnotationAction {}

class _Recolor extends _AnnotationAction {
  _Recolor(this.color);
  final HighlightColor color;
}

class _EditNote extends _AnnotationAction {}

class _Delete extends _AnnotationAction {}

class _AnnotationSheet extends StatelessWidget {
  const _AnnotationSheet({required this.annotation});

  final Annotation annotation;

  @override
  Widget build(BuildContext context) {
    final a = annotation;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.text.isNotEmpty)
              Text(
                a.text,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            if (a.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(a.note),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (!a.isBookmark)
                  for (final MapEntry(key: color, value: swatch)
                      in highlightSwatches.entries)
                    IconButton(
                      tooltip: color.name,
                      icon: Icon(
                        color == a.color ? Icons.check_circle : Icons.circle,
                        color: swatch,
                      ),
                      onPressed: () =>
                          Navigator.of(context).pop(_Recolor(color)),
                    ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.edit_note),
                  label: Text(a.note.isEmpty ? 'Add note' : 'Edit note'),
                  onPressed: () => Navigator.of(context).pop(_EditNote()),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => Navigator.of(context).pop(_Delete()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One highlight, note or bookmark in a list.
class AnnotationTile extends StatelessWidget {
  const AnnotationTile({
    super.key,
    required this.annotation,
    this.subtitle,
    this.onTap,
    this.onLongPress,
  });

  final Annotation annotation;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final a = annotation;
    final title = a.isBookmark
        ? (a.page != null ? 'Page ${a.page}' : 'Bookmark')
        : a.text;
    return ListTile(
      leading: a.isBookmark
          ? const Icon(Icons.bookmark)
          : Container(
              width: 6,
              height: 40,
              decoration: BoxDecoration(
                color: highlightSwatches[a.color],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
      title: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [?subtitle, if (a.note.isNotEmpty) a.note].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// Keeps the book on the device for offline reading, or frees the space.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.book, required this.cache});

  final Book book;
  final BookCache cache;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        if (cache.isDownloading(book)) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: cache.downloadProgress(book),
              ),
            ),
          );
        }
        final kept = cache.isDownloaded(book);
        return IconButton(
          tooltip: kept ? 'Remove download' : 'Download for offline reading',
          icon: Icon(
            kept ? Icons.download_done : Icons.download_for_offline_outlined,
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              if (kept) {
                await cache.removeDownload(book);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Download removed')),
                );
              } else {
                await cache.download(book);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Available offline')),
                );
              }
            } catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Download failed: $e')),
              );
            }
          },
        );
      },
    );
  }
}
