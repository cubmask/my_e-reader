import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/book_format.dart';
import '../library/book.dart';
import '../notes/annotation_store.dart';
import '../ui/breakpoints.dart';
import 'ink_layer.dart';
import 'pdf_book_view.dart';
import 'progress_store.dart';
import 'read_aloud.dart';
import 'reader_services.dart';
import 'reader_settings.dart';
import 'web_book_view.dart';

const highlightSwatches = {
  HighlightColor.yellow: Color(0xFFF9D71C),
  HighlightColor.green: Color(0xFF5FD068),
  HighlightColor.blue: Color(0xFF4AA8FF),
  HighlightColor.pink: Color(0xFFFF6FAE),
};

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
  final _readAloud = ReadAloud();
  final _ink = InkController();
  File? _file;
  double? _download;
  String? _error;
  bool _controls = true;
  late String _title = services.meta.titleOf(widget.book);
  List<TocItem> _toc = const [];
  double _fraction = 0;
  String _chapter = '';
  String _location = '';
  ({String cfi, String text})? _selection;

  Book get book => widget.book;
  ReaderServices get services => widget.services;
  AnnotationStore get annotations => services.annotations;
  bool get _isPdf => book.format == BookFormat.pdf;

  @override
  void initState() {
    super.initState();
    final saved = services.progress[book.driveFileId];
    _fraction = saved?.fraction ?? 0;
    _location = widget.openAt ?? saved?.location ?? '';
    services.cache
        .open(book, onProgress: (v) => setState(() => _download = v))
        .then(
          (file) => setState(() => _file = file),
          onError: (Object e) => setState(() => _error = '$e'),
        );
  }

  @override
  void dispose() {
    _readAloud.dispose();
    _ink.dispose();
    services.ink.flush();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    services.progress.flush();
    annotations.flush();
    super.dispose();
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
      int.tryParse(_location.replaceFirst('page:', '')) ?? 1;

  Future<void> _goTo(Annotation a) async {
    if (a.page case final page?) {
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
    await _web.addHighlight(selection.cfi, color.name);
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
        await _web.addHighlight(a.location, color.name);
      case _EditNote():
        final note = await _editNote(context, a.note);
        if (note != null) await annotations.update(a.copyWith(note: note));
      case _Delete():
        await annotations.remove(a);
        if (!a.isBookmark) await _web.removeHighlight(a.location);
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

  // Read aloud

  Future<void> _toggleReadAloud() async {
    if (_readAloud.active) return _readAloud.stop();
    setState(() => _controls = true);
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
              box.maxWidth > box.maxHeight &&
              box.maxWidth >= Breakpoints.expanded;
          return ListenableBuilder(
            listenable: Listenable.merge([_readAloud, _ink]),
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
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildSelectionBar()),
                  )
                else if (_file != null && (_controls || _readAloud.active))
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
    ReaderTheme.light => Colors.white,
    ReaderTheme.sepia => const Color(0xFFF4ECD8),
    ReaderTheme.dark => const Color(0xFF121212),
  };

  Widget _buildBody(bool spread) {
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
            Text(
              book.format.needsConversion
                  ? 'Converting with Google Drive'
                  : 'Downloading from Google Drive',
            ),
          ],
        ),
      );
    }
    if (_isPdf) {
      return SafeArea(
        child: PdfBookView(
          file: file,
          controller: _pdf,
          initialPage: _initialPdfPage,
          spread: spread,
          onToggleControls: _toggleControls,
          bookId: book.driveFileId,
          ink: services.ink,
          inkController: _ink,
          onPageChanged: (page, count) =>
              _save('page:$page', count <= 1 ? 1 : (page - 1) / (count - 1)),
        ),
      );
    }
    return SafeArea(
      child: WebBookView(
        file: file,
        // Converted office documents are EPUBs.
        fileName: book.format.needsConversion
            ? '${book.displayTitle}.epub'
            : book.fileName,
        format: book.format,
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
              title: title,
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
      ),
    );
  }

  Widget _buildTopBar() {
    final bookmarked = _bookmarkHere != null;
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
              if (_file != null) ...[
                IconButton(
                  tooltip: _readAloud.active
                      ? 'Stop reading aloud'
                      : 'Read aloud',
                  icon: Icon(
                    _readAloud.active ? Icons.stop_circle : Icons.headphones,
                  ),
                  onPressed: _toggleReadAloud,
                ),
                IconButton(
                  tooltip: bookmarked
                      ? 'Remove bookmark'
                      : 'Bookmark this page',
                  icon: Icon(
                    bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  onPressed: _toggleBookmark,
                ),
                if (_isPdf)
                  IconButton(
                    tooltip: _ink.enabled ? 'Stop writing' : 'Write with pen',
                    isSelected: _ink.enabled,
                    icon: const Icon(Icons.draw_outlined),
                    selectedIcon: const Icon(Icons.draw),
                    onPressed: () => _ink.enabled = !_ink.enabled,
                  ),
                IconButton(
                  tooltip: 'Notes and highlights',
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  onPressed: _showNotes,
                ),
              ],
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

  Widget _buildSelectionBar() {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(key: color, value: swatch)
                in highlightSwatches.entries)
              IconButton(
                tooltip: 'Highlight ${color.name}',
                icon: Icon(Icons.circle, color: swatch),
                onPressed: () => _highlight(color),
              ),
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('Note'),
              onPressed: _highlightWithNote,
            ),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _selection!.text));
                _web.clearSelection();
                setState(() => _selection = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isWeb = !_isPdf;
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_readAloud.active) _buildSpeedRow(),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedRow() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    return Row(
      children: [
        const Icon(Icons.record_voice_over, size: 20),
        const SizedBox(width: 12),
        const Text('Reading aloud'),
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
              if (!_isPdf) ...[
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
