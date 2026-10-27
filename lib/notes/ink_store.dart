import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../reader/progress_store.dart' show ProgressRemote;

/// One pen or highlighter stroke drawn on a PDF page.
///
/// Points and [width] are in page widths (x runs 0 to 1, y 0 to the page's
/// height over its width), so a stroke stays put whatever the zoom or screen. Deleted strokes stay as tombstones so the
/// deletion syncs to other devices.
@immutable
class InkStroke {
  const InkStroke({
    required this.id,
    required this.bookId,
    required this.page,
    required this.color,
    required this.width,
    required this.points,
    required this.updatedAt,
    this.highlighter = false,
    this.deleted = false,
  });

  final String id;
  final String bookId;
  final int page;

  /// ARGB colour.
  final int color;

  /// Line width as a fraction of the page width.
  final double width;
  final List<Offset> points;
  final bool highlighter;
  final DateTime updatedAt;
  final bool deleted;

  InkStroke delete() => InkStroke(
    id: id,
    bookId: bookId,
    page: page,
    color: color,
    width: width,
    points: points,
    highlighter: highlighter,
    updatedAt: DateTime.now(),
    deleted: true,
  );

  /// Whether [p] (in page widths) is within [radius] of the line.
  bool hits(Offset p, double radius) {
    final r = radius + width / 2;
    if (points.length == 1) return (points.first - p).distance <= r;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(p, points[i - 1], points[i]) <= r) return true;
    }
    return false;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final ap = p - a;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  Map<String, Object> toJson() => {
    'id': id,
    'bookId': bookId,
    'page': page,
    'color': color,
    'width': width,
    if (highlighter) 'highlighter': true,
    // Four decimals is a tenth of a millimetre on an A4 page.
    'points': [
      for (final p in points) ...[_round(p.dx), _round(p.dy)],
    ],
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (deleted) 'deleted': true,
  };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  static InkStroke? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], bookId = json['bookId'], page = json['page'];
    final color = json['color'], width = json['width'];
    final coords = json['points'];
    final updatedAt = DateTime.tryParse('${json['updatedAt']}');
    if (id is! String ||
        bookId is! String ||
        page is! int ||
        color is! int ||
        width is! num ||
        coords is! List ||
        updatedAt == null) {
      return null;
    }
    final points = <Offset>[];
    for (var i = 0; i + 1 < coords.length; i += 2) {
      final x = coords[i], y = coords[i + 1];
      if (x is num && y is num) points.add(Offset(x.toDouble(), y.toDouble()));
    }
    return InkStroke(
      id: id,
      bookId: bookId,
      page: page,
      color: color,
      width: width.toDouble(),
      points: points,
      highlighter: json['highlighter'] == true,
      updatedAt: updatedAt,
      deleted: json['deleted'] == true,
    );
  }
}

/// Merges two stroke sets by id; the most recently updated copy wins.
Map<String, InkStroke> mergeInk(
  Map<String, InkStroke> a,
  Map<String, InkStroke> b,
) {
  final merged = {...a};
  b.forEach((id, theirs) {
    final ours = merged[id];
    if (ours == null || theirs.updatedAt.isAfter(ours.updatedAt)) {
      merged[id] = theirs;
    }
  });
  return merged;
}

Map<String, InkStroke> decodeInk(String text) {
  final json = jsonDecode(text);
  final list = json is Map ? json['strokes'] : null;
  if (list is! List) return {};
  final out = <String, InkStroke>{};
  for (final item in list) {
    final s = InkStroke.fromJson(item);
    if (s != null) out[s.id] = s;
  }
  return out;
}

String encodeInk(Iterable<InkStroke> strokes) => jsonEncode({
  'version': 1,
  'strokes': [for (final s in strokes) s.toJson()],
});

/// Handwritten PDF notes, kept locally and synced to a hidden `ink.json` in
/// Drive like highlights.
class InkStore extends ChangeNotifier {
  /// A null [_localFile] keeps strokes in memory only, for tests.
  InkStore(this._localFile, this._remote);

  final File? _localFile;
  final ProgressRemote? _remote;
  Map<String, InkStroke> _all = {};
  Timer? _pushTimer;
  int _counter = 0;

  /// Local writes run one after another, since strokes arrive quickly.
  Future<void> _saving = Future.value();

  /// Live strokes on one page, oldest first so later ones draw on top.
  ///
  /// The same list is returned until the ink changes, so painters can tell
  /// cheaply whether there is anything new to draw.
  List<InkStroke> forPage(String bookId, int page) =>
      _pages.putIfAbsent((bookId, page), () {
        return List.unmodifiable(
          _all.values
              .where((s) => !s.deleted && s.bookId == bookId && s.page == page)
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id)),
        );
      });

  /// Pages of a book that have ink on them.
  Set<int> pagesWithInk(String bookId) => {
    for (final s in _all.values)
      if (!s.deleted && s.bookId == bookId) s.page,
  };

  final _pages = <(String, int), List<InkStroke>>{};

  @override
  void notifyListeners() {
    _pages.clear();
    super.notifyListeners();
  }

  Future<void> load() async {
    final file = _localFile;
    if (file != null && await file.exists()) {
      try {
        _all = decodeInk(await file.readAsString());
      } on FormatException {
        _all = {};
      }
    }
    notifyListeners();
    await sync();
  }

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    try {
      final text = await remote.read();
      if (text != null) {
        _all = mergeInk(_all, decodeInk(text));
        notifyListeners();
      }
      await _saveLocal();
      await remote.write(encodeInk(_all.values));
    } catch (_) {
      // Offline: kept locally and pushed on the next sync.
    }
  }

  /// Adds a stroke at once; saving and syncing happen in the background.
  InkStroke add({
    required String bookId,
    required int page,
    required int color,
    required double width,
    required List<Offset> points,
    bool highlighter = false,
  }) {
    final now = DateTime.now();
    // Ids sort by creation time, which is the drawing order.
    final stamp = now.microsecondsSinceEpoch.toRadixString(36).padLeft(12, '0');
    final stroke = InkStroke(
      id: '$stamp-${_counter++}',
      bookId: bookId,
      page: page,
      color: color,
      width: width,
      points: points,
      highlighter: highlighter,
      updatedAt: now,
    );
    unawaited(_put([stroke]));
    return stroke;
  }

  Future<void> remove(Iterable<InkStroke> strokes) =>
      _put([for (final s in strokes) s.delete()]);

  /// Puts deleted strokes back, for undo.
  Future<void> restore(Iterable<InkStroke> strokes) => _put([
    for (final s in strokes)
      InkStroke(
        id: s.id,
        bookId: s.bookId,
        page: s.page,
        color: s.color,
        width: s.width,
        points: s.points,
        highlighter: s.highlighter,
        updatedAt: DateTime.now(),
      ),
  ]);

  Future<void> _put(List<InkStroke> strokes) async {
    for (final s in strokes) {
      _all[s.id] = s;
    }
    notifyListeners();
    await (_saving = _saving.then((_) => _saveLocal()));
    if (_remote == null) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 5), sync);
  }

  Future<void> flush() async {
    await _saving;
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await sync();
    }
  }

  Future<void> _saveLocal() async {
    final file = _localFile;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(encodeInk(_all.values));
  }
}
