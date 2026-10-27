import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// One match of a search inside a book.
@immutable
class SearchHit {
  const SearchHit({
    required this.location,
    required this.label,
    required this.pre,
    required this.match,
    required this.post,
  });

  /// Where the match is: a CFI, or `page:N` in a PDF.
  final String location;

  /// The chapter, or "Page N" in a PDF.
  final String label;
  final String pre, match, post;
}

/// Finds text in the open book, page by page or chapter by chapter, so the
/// first matches show while the rest of the book is still being searched.
abstract class BookSearch extends ChangeNotifier {
  String _query = '';
  List<SearchHit> _hits = const [];
  bool _searching = false;
  double? _progress;

  String get query => _query;
  List<SearchHit> get hits => _hits;
  bool get searching => _searching;

  /// How much of the book has been searched, 0 to 1.
  double? get progress => _progress;

  /// Starts a new search; an empty [query] clears it.
  void search(String query) {
    final q = query.trim();
    if (q == _query) return;
    _query = q;
    _hits = const [];
    _progress = null;
    _searching = q.isNotEmpty;
    notifyListeners();
    if (q.isEmpty) {
      cancel();
    } else {
      start(q);
    }
  }

  void clear() => search('');

  @protected
  void start(String query);

  @protected
  void cancel();

  /// Shows [hit] in the reader.
  Future<void> goTo(SearchHit hit);

  @protected
  void addHits(Iterable<SearchHit> hits) {
    _hits = [..._hits, ...hits];
    notifyListeners();
  }

  @protected
  void setHits(List<SearchHit> hits) {
    _hits = hits;
    notifyListeners();
  }

  @protected
  void setProgress(double? progress, {bool done = false}) {
    _progress = progress;
    if (done) _searching = false;
    notifyListeners();
  }
}

/// Searches a PDF with PDFium's text layer, drawing matches on the pages.
class PdfBookSearch extends BookSearch {
  PdfBookSearch(PdfViewerController controller)
    : _searcher = PdfTextSearcher(controller) {
    _searcher.addListener(_update);
  }

  final PdfTextSearcher _searcher;
  int _seen = 0;

  /// Draws the matches; pass to [PdfViewerParams.pagePaintCallbacks].
  void paint(Canvas canvas, Rect pageRect, PdfPage page) =>
      _searcher.pageTextMatchPaintCallback(canvas, pageRect, page);

  @override
  void start(String query) {
    _seen = 0;
    _searcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  @override
  void cancel() {
    _seen = 0;
    _searcher.resetTextSearch();
  }

  void _update() {
    final matches = _searcher.matches;
    if (matches.length < _seen) _seen = 0;
    if (matches.length > _seen) {
      addHits([for (final m in matches.skip(_seen)) _hit(m)]);
      _seen = matches.length;
    }
    setProgress(
      _searcher.searchProgress,
      done: !_searcher.isSearching && query.isNotEmpty,
    );
  }

  static SearchHit _hit(PdfPageTextRange m) {
    final text = m.pageText.fullText;
    String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
    final from = (m.start - 50).clamp(0, text.length);
    final to = (m.end + 50).clamp(0, text.length);
    return SearchHit(
      location: 'page:${m.pageNumber}',
      label: 'Page ${m.pageNumber}',
      pre: '${from > 0 ? '…' : ''}${clean(text.substring(from, m.start))}',
      match: clean(text.substring(m.start, m.end)),
      post: '${clean(text.substring(m.end, to))}${to < text.length ? '…' : ''}',
    );
  }

  @override
  Future<void> goTo(SearchHit hit) async {
    final index = hits.indexOf(hit);
    if (index >= 0 && index < _searcher.matches.length) {
      await _searcher.goToMatchOfIndex(index);
    }
  }

  @override
  void dispose() {
    _searcher.removeListener(_update);
    _searcher.dispose();
    super.dispose();
  }
}

/// The search panel: a field, progress, and the matches grouped under their
/// chapter or page. Tapping a match closes the panel and shows it.
class SearchPanel extends StatefulWidget {
  const SearchPanel({super.key, required this.search, this.scroll});

  final BookSearch search;
  final ScrollController? scroll;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  late final _field = TextEditingController(text: widget.search.query);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = widget.search;
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) {
        final hits = search.hits;
        return CustomScrollView(
          controller: widget.scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  controller: _field,
                  autofocus: search.query.isEmpty,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search this book',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: search.query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _field.clear();
                              search.clear();
                            },
                          ),
                  ),
                  onSubmitted: search.search,
                ),
              ),
            ),
            if (search.searching)
              SliverToBoxAdapter(
                child: LinearProgressIndicator(value: search.progress),
              ),
            if (search.query.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    search.searching
                        ? '${hits.length} found so far'
                        : hits.isEmpty
                        ? 'No matches for "${search.query}"'
                        : '${hits.length} ${hits.length == 1 ? 'match' : 'matches'}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: hits.length,
              itemBuilder: (context, i) {
                final hit = hits[i];
                final newLabel = i == 0 || hits[i - 1].label != hit.label;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (newLabel && hit.label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Text(
                          hit.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ListTile(
                      title: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: hit.pre),
                            TextSpan(
                              text: hit.match,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: hit.post),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        search.goTo(hit);
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
