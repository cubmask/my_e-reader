import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/book_format.dart';
import '../library/book.dart';
import '../ui/breakpoints.dart';
import 'pdf_book_view.dart';
import 'progress_store.dart';
import 'reader_services.dart';
import 'reader_settings.dart';
import 'web_book_view.dart';

/// Formats the web reader (foliate-js) opens in this phase.
const _webFormats = {
  BookFormat.epub,
  BookFormat.mobi,
  BookFormat.azw3,
  BookFormat.fb2,
  BookFormat.txt,
  BookFormat.cbz,
};

bool isReadable(BookFormat format) =>
    format == BookFormat.pdf || _webFormats.contains(format);

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, required this.services});

  final Book book;
  final ReaderServices services;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _web = WebBookController();
  File? _file;
  double? _download;
  String? _error;
  bool _controls = true;
  late String _title = widget.book.displayTitle;
  List<TocItem> _toc = const [];
  double _fraction = 0;
  String _chapter = '';

  Book get book => widget.book;
  ReaderServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _fraction = services.progress[book.driveFileId]?.fraction ?? 0;
    if (!isReadable(book.format)) return;
    services.cache
        .open(book, onProgress: (v) => setState(() => _download = v))
        .then(
          (file) => setState(() => _file = file),
          onError: (Object e) => setState(() => _error = '$e'),
        );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    services.progress.flush();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    SystemChrome.setEnabledSystemUIMode(
      _controls ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _save(String location, double fraction) {
    setState(() => _fraction = fraction);
    services.progress.save(
      book.driveFileId,
      ReadingProgress(
        location: location,
        fraction: fraction,
        updatedAt: DateTime.now(),
      ),
    );
  }

  int get _initialPdfPage {
    final location = services.progress[book.driveFileId]?.location ?? '';
    return int.tryParse(location.replaceFirst('page:', '')) ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background(context),
      endDrawer: _toc.isEmpty ? null : _buildToc(),
      body: LayoutBuilder(
        builder: (context, box) {
          final spread =
              box.maxWidth > box.maxHeight &&
              box.maxWidth >= Breakpoints.expanded;
          return Stack(
            children: [
              Positioned.fill(child: _buildBody(spread)),
              if (_controls) ...[
                Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
                if (_file != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Color _background(BuildContext context) => switch (services.settings.theme) {
    ReaderTheme.light => Colors.white,
    ReaderTheme.sepia => const Color(0xFFF4ECD8),
    ReaderTheme.dark => const Color(0xFF121212),
  };

  Widget _buildBody(bool spread) {
    if (!isReadable(book.format)) {
      return _Notice(
        '${book.format.label} support arrives in a later phase. '
        'This phase reads EPUB, MOBI, AZW3, FB2, TXT, CBZ and PDF.',
      );
    }
    if (_error != null) return _Notice('Could not open this book.\n$_error');
    final file = _file;
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
            const Text('Downloading from Google Drive'),
          ],
        ),
      );
    }
    if (book.format == BookFormat.pdf) {
      return SafeArea(
        child: PdfBookView(
          file: file,
          initialPage: _initialPdfPage,
          spread: spread,
          onToggleControls: _toggleControls,
          onPageChanged: (page, count) =>
              _save('page:$page', count <= 1 ? 1 : (page - 1) / (count - 1)),
        ),
      );
    }
    return SafeArea(
      child: WebBookView(
        file: file,
        fileName: book.fileName,
        format: book.format,
        server: services.server,
        controller: _web,
        settings: services.settings,
        columns: spread ? 2 : 1,
        initialLocation: services.progress[book.driveFileId]?.location,
        onRelocate: (cfi, fraction, chapter) {
          _chapter = chapter;
          _save(cfi, fraction);
        },
        onOpened: (title, toc) => setState(() {
          _title = title;
          _toc = toc;
          _controls = false;
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }),
        onError: (message) => setState(() => _error = message),
        onToggleControls: _toggleControls,
      ),
    );
  }

  Widget _buildTopBar() {
    return Material(
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const BackButton(),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Appearance',
                icon: const Icon(Icons.text_format),
                onPressed: _showAppearance,
              ),
              if (_toc.isNotEmpty)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isWeb = book.format != BookFormat.pdf;
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              if (isWeb)
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _web.prev,
                ),
              Expanded(
                child: isWeb
                    ? Slider(
                        value: _fraction.clamp(0, 1),
                        onChanged: (v) => setState(() => _fraction = v),
                        onChangeEnd: _web.goToFraction,
                      )
                    : LinearProgressIndicator(value: _fraction),
              ),
              if (isWeb)
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _web.next,
                ),
              const SizedBox(width: 8),
              Text(
                [
                  if (_chapter.isNotEmpty) _chapter,
                  '${(_fraction * 100).round()}%',
                ].join(' · '),
              ),
            ],
          ),
        ),
      ),
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
                  _web.goTo(item.href);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAppearance() {
    final settings = services.settings;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<ReaderTheme>(
                segments: const [
                  ButtonSegment(value: ReaderTheme.light, label: Text('Light')),
                  ButtonSegment(value: ReaderTheme.sepia, label: Text('Sepia')),
                  ButtonSegment(value: ReaderTheme.dark, label: Text('Dark')),
                ],
                selected: {settings.theme},
                onSelectionChanged: (s) {
                  settings.setTheme(s.first);
                  setState(() {});
                },
              ),
              if (book.format != BookFormat.pdf) ...[
                const SizedBox(height: 16),
                Text('Text size ${settings.fontSize}%'),
                Slider(
                  min: ReaderSettings.minFont.toDouble(),
                  max: ReaderSettings.maxFont.toDouble(),
                  divisions: 13,
                  value: settings.fontSize.toDouble(),
                  onChanged: (v) => settings.setFontSize(v.round()),
                ),
              ],
            ],
          ),
        ),
      ),
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
