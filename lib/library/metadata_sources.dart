import 'dart:convert';

import 'package:http/http.dart' as http;

/// What to look a book up by: its title and author as far as we know them,
/// or an ISBN.
class MetadataQuery {
  const MetadataQuery({required this.title, this.author = '', this.isbn = ''});

  /// Guesses a title and author from a file name, the way Calibre reads
  /// "Title - Author" names: brackets, underscores and edition noise go, and
  /// the part after " - " or " by " is taken as the author.
  factory MetadataQuery.fromFileName(String name) {
    var s = name
        .replaceAll(RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]'), ' ')
        .replaceAll(RegExp(r'[_.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final isbn = RegExp(r'\b(97[89]\d{10}|\d{9}[\dXx])\b').firstMatch(s);
    if (isbn != null) s = s.replaceFirst(isbn[0]!, '').trim();
    final parts = s.split(RegExp(r'\s+-\s+|\s+by\s+', caseSensitive: false));
    return MetadataQuery(
      title: parts.first.trim(),
      author: parts.length > 1 ? parts.sublist(1).join(' ').trim() : '',
      isbn: isbn?[0] ?? '',
    );
  }

  final String title;
  final String author;
  final String isbn;

  String get text => [title, author].where((s) => s.isNotEmpty).join(' ');
}

/// One candidate match from an online source.
class MetadataResult {
  const MetadataResult({
    required this.source,
    required this.title,
    this.authors = const [],
    this.description = '',
    this.publisher = '',
    this.published = '',
    this.isbn = '',
    this.subjects = const [],
    this.pageCount,
    this.rating,
    this.coverUrl,
    this.detailsUrl,
  });

  final String source;
  final String title;
  final List<String> authors;
  final String description;
  final String publisher;
  final String published;
  final String isbn;
  final List<String> subjects;
  final int? pageCount;
  final double? rating;
  final Uri? coverUrl;

  /// Where to fetch more details (Open Library keeps descriptions apart).
  final Uri? detailsUrl;

  String get author => authors.join(', ');

  MetadataResult withDescription(String text) => MetadataResult(
    source: source,
    title: title,
    authors: authors,
    description: text,
    publisher: publisher,
    published: published,
    isbn: isbn,
    subjects: subjects,
    pageCount: pageCount,
    rating: rating,
    coverUrl: coverUrl,
    detailsUrl: detailsUrl,
  );

  /// Fills this result's empty fields from [other], as Calibre merges the
  /// answers of several sources for the same book.
  MetadataResult mergedWith(MetadataResult other) => MetadataResult(
    source: '$source + ${other.source}',
    title: title,
    authors: authors.isNotEmpty ? authors : other.authors,
    description: description.isNotEmpty ? description : other.description,
    publisher: publisher.isNotEmpty ? publisher : other.publisher,
    published: published.isNotEmpty ? published : other.published,
    isbn: isbn.isNotEmpty ? isbn : other.isbn,
    subjects: subjects.isNotEmpty ? subjects : other.subjects,
    pageCount: pageCount ?? other.pageCount,
    rating: rating ?? other.rating,
    // Open Library's large covers are sharper than Google's thumbnails.
    coverUrl: other.source == 'Open Library'
        ? other.coverUrl ?? coverUrl
        : coverUrl ?? other.coverUrl,
    detailsUrl: detailsUrl ?? other.detailsUrl,
  );
}

abstract interface class MetadataSource {
  String get name;
  Future<List<MetadataResult>> search(MetadataQuery query);
}

/// Google Books. Works without a key at a low daily rate; a key from the
/// user's Google Cloud project (GOOGLE_BOOKS_API_KEY) lifts that.
class GoogleBooksSource implements MetadataSource {
  GoogleBooksSource(this._http, {this.apiKey = ''});

  final http.Client _http;
  final String apiKey;

  @override
  String get name => 'Google Books';

  @override
  Future<List<MetadataResult>> search(MetadataQuery query) async {
    final q = query.isbn.isNotEmpty
        ? 'isbn:${query.isbn}'
        : [
            'intitle:${query.title}',
            if (query.author.isNotEmpty) 'inauthor:${query.author}',
          ].join(' ');
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': q,
      'maxResults': '8',
      'printType': 'books',
      'key': ?(apiKey.isEmpty ? null : apiKey),
    });
    final response = await _http.get(uri);
    if (response.statusCode != 200) return const [];
    final items = (jsonDecode(response.body) as Map)['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['volumeInfo'] is Map)
          _parse(item['volumeInfo'] as Map),
    ];
  }

  MetadataResult _parse(Map v) {
    String text(String key) => v[key] is String ? v[key] as String : '';
    List<String> list(String key) => [
      if (v[key] case final List items)
        for (final i in items)
          if (i is String) i,
    ];
    final ids = [
      if (v['industryIdentifiers'] case final List items)
        for (final i in items)
          if (i is Map) i,
    ];
    String isbn(String type) =>
        '${ids.where((i) => i['type'] == type).firstOrNull?['identifier'] ?? ''}';
    final thumb = (v['imageLinks'] as Map?)?['thumbnail'];
    final subtitle = text('subtitle');
    return MetadataResult(
      source: name,
      title: subtitle.isEmpty ? text('title') : '${text('title')}: $subtitle',
      authors: list('authors'),
      description: stripHtml(text('description')),
      publisher: text('publisher'),
      published: text('publishedDate'),
      isbn: isbn('ISBN_13').isNotEmpty ? isbn('ISBN_13') : isbn('ISBN_10'),
      subjects: list('categories'),
      pageCount: v['pageCount'] is int ? v['pageCount'] as int : null,
      rating: v['averageRating'] is num
          ? (v['averageRating'] as num).toDouble()
          : null,
      coverUrl: thumb is String
          ? Uri.parse(
              // Google serves a bigger image when asked for a width.
              '${thumb.replaceFirst('http:', 'https:').replaceAll('&edge=curl', '')}&fife=w800',
            )
          : null,
    );
  }
}

/// Open Library, the Internet Archive's free book catalogue.
class OpenLibrarySource implements MetadataSource {
  OpenLibrarySource(this._http);

  final http.Client _http;

  @override
  String get name => 'Open Library';

  static const _fields =
      'key,title,subtitle,author_name,cover_i,isbn,first_publish_year,'
      'publisher,subject,number_of_pages_median,ratings_average';

  @override
  Future<List<MetadataResult>> search(MetadataQuery query) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      if (query.isbn.isNotEmpty)
        'isbn': query.isbn
      else ...{
        'title': query.title,
        if (query.author.isNotEmpty) 'author': query.author,
      },
      'limit': '8',
      'fields': _fields,
    });
    final response = await _http.get(uri);
    if (response.statusCode != 200) return const [];
    final docs = (jsonDecode(response.body) as Map)['docs'];
    if (docs is! List) return const [];
    return [
      for (final d in docs)
        if (d is Map && d['title'] is String) _parse(d),
    ];
  }

  MetadataResult _parse(Map d) {
    List<String> list(String key) => [
      if (d[key] case final List items)
        for (final i in items)
          if (i is String) i,
    ];
    final isbns = list('isbn');
    final cover = d['cover_i'];
    final key = d['key'];
    final subtitle = d['subtitle'] is String ? d['subtitle'] as String : '';
    return MetadataResult(
      source: name,
      title: subtitle.isEmpty
          ? d['title'] as String
          : '${d['title']}: $subtitle',
      authors: list('author_name'),
      publisher: list('publisher').firstOrNull ?? '',
      published: d['first_publish_year'] is int
          ? '${d['first_publish_year']}'
          : '',
      isbn:
          isbns.where((i) => i.length == 13).firstOrNull ??
          isbns.firstOrNull ??
          '',
      subjects: list('subject').take(8).toList(),
      pageCount: d['number_of_pages_median'] is int
          ? d['number_of_pages_median'] as int
          : null,
      rating: d['ratings_average'] is num
          ? (d['ratings_average'] as num).toDouble()
          : null,
      coverUrl: cover is int
          ? Uri.parse('https://covers.openlibrary.org/b/id/$cover-L.jpg')
          : null,
      detailsUrl: key is String
          ? Uri.https('openlibrary.org', '$key.json')
          : null,
    );
  }

  /// Open Library keeps the description on the work record.
  Future<String> description(MetadataResult result) async {
    final url = result.detailsUrl;
    if (url == null) return '';
    final response = await _http.get(url);
    if (response.statusCode != 200) return '';
    final d = (jsonDecode(response.body) as Map)['description'];
    if (d is String) return d;
    if (d is Map && d['value'] is String) return d['value'] as String;
    return '';
  }
}

String stripHtml(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

const _stopWords = {'the', 'a', 'an', 'of', 'and', 'in', 'on', 'to', 'for'};

Set<String> _words(String s) => {
  for (final w in s.toLowerCase().split(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  ))
    if (w.isNotEmpty && !_stopWords.contains(w)) w,
};

/// How well [result] matches [query], 0 to 1. Both the title words and,
/// when known, the author have to line up.
double matchScore(MetadataQuery query, MetadataResult result) {
  final asked = _words(query.title);
  // Drop a subtitle the file name doesn't have.
  final found = _words(result.title.split(':').first);
  if (asked.isEmpty || found.isEmpty) return 0;
  final everything = _words(query.text);
  final foundInAsked = found.intersection(everything).length / found.length;
  final askedInFound =
      asked.intersection(found.union(_words(result.author))).length /
      asked.length;
  var score = (foundInAsked + askedInFound) / 2;
  final author = _words(query.author);
  if (author.isNotEmpty) {
    final shared = author.intersection(_words(result.author)).isNotEmpty;
    score += shared ? 0.15 : -0.25;
  }
  return score.clamp(0, 1).toDouble();
}

/// Looks books up in several sources at once and ranks the answers, like
/// Calibre's "Download metadata".
class MetadataService {
  MetadataService(this._http, {String googleApiKey = ''})
    : _google = GoogleBooksSource(_http, apiKey: googleApiKey),
      _openLibrary = OpenLibrarySource(_http);

  final http.Client _http;
  final GoogleBooksSource _google;
  final OpenLibrarySource _openLibrary;

  /// A score at or above this is trusted for automatic updates.
  static const confident = 0.75;

  http.Client get httpClient => _http;

  /// Every candidate from every source, best match first.
  Future<List<(MetadataResult, double)>> search(MetadataQuery query) async {
    final answers = await Future.wait([
      for (final source in <MetadataSource>[_google, _openLibrary])
        source
            .search(query)
            .then<List<MetadataResult>?>((r) => r, onError: (_) => null),
    ]);
    // Every source failing means we're offline, which is not "no match".
    if (answers.every((a) => a == null)) {
      throw StateError('No metadata source could be reached.');
    }
    final scored = [
      for (final list in answers.nonNulls)
        for (final r in list)
          (r, query.isbn.isNotEmpty ? 1.0 : matchScore(query, r)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return scored;
  }

  /// The best match, filled out from the other source's matching answer and
  /// with Open Library's description fetched if needed. Null when nothing
  /// matches confidently.
  Future<MetadataResult?> best(MetadataQuery query) async {
    final all = await search(query);
    if (all.isEmpty || all.first.$2 < confident) return null;
    return complete(all.first.$1, [
      for (final (r, s) in all)
        if (s >= confident) r,
    ]);
  }

  /// Fills [chosen] from other confident matches of the same book and
  /// fetches its description if it has none.
  Future<MetadataResult> complete(
    MetadataResult chosen,
    List<MetadataResult> others,
  ) async {
    var result = chosen;
    for (final other in others) {
      if (other.source != chosen.source) {
        result = result.mergedWith(other);
        break;
      }
    }
    if (result.description.isEmpty && result.detailsUrl != null) {
      final description = await _openLibrary
          .description(result)
          .catchError((_) => '');
      if (description.isNotEmpty) {
        result = result.withDescription(stripHtml(description));
      }
    }
    return result;
  }
}
