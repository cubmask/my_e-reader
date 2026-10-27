import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../reader/progress_store.dart' show ProgressRemote;

/// `2026-10-27` for the local day of [time].
String dayKey(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Time spent reading, per day and book, plus the daily goal, finished
/// books and how fast the user reads.
///
/// Each device records its own seconds, so merging copies from two devices
/// takes the larger count per device and adds the devices up, without
/// counting a session twice. Synced to a hidden `stats.json` in Drive.
class ReadingStats extends ChangeNotifier {
  ReadingStats(this._localFile, this._remote, {required this.device});

  /// Null keeps the stats in memory only.
  final File? _localFile;
  final ProgressRemote? _remote;

  /// This device's id within the stats.
  final String device;

  /// Day → device → book id → seconds.
  final Map<String, Map<String, Map<String, int>>> _days = {};

  /// Book id → when it was finished.
  final Map<String, DateTime> _finished = {};
  int _goalMinutes = 30;
  DateTime _goalUpdatedAt = DateTime.utc(2000);

  /// Minutes of reading per foliate time unit (1600 bytes of the book), as
  /// measured; 1 until enough reading has been timed.
  double _minutesPerUnit = 1;

  /// Seconds per PDF page, as measured.
  double _secondsPerPage = 90;
  Timer? _pushTimer;
  Timer? _saveTimer;

  int get goalMinutes => _goalMinutes;
  double get minutesPerUnit => _minutesPerUnit;
  double get secondsPerPage => _secondsPerPage;
  Map<String, DateTime> get finished => Map.unmodifiable(_finished);

  /// Seconds read on [day] (see [dayKey]), on every device.
  int secondsOn(String day) {
    var total = 0;
    for (final books in (_days[day] ?? const {}).values) {
      for (final s in books.values) {
        total += s;
      }
    }
    return total;
  }

  /// Seconds read in each of the [days] days up to [today], oldest first.
  List<int> lastDays(int days, {DateTime? today}) {
    final now = today ?? DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        secondsOn(dayKey(DateTime(now.year, now.month, now.day - i))),
    ];
  }

  /// Seconds read per book over all time, on every device.
  Map<String, int> get secondsByBook {
    final out = <String, int>{};
    for (final devices in _days.values) {
      for (final books in devices.values) {
        books.forEach((id, s) => out[id] = (out[id] ?? 0) + s);
      }
    }
    return out;
  }

  /// Days in a row, up to today, with any reading; today counts once read,
  /// and an unread today doesn't break yesterday's streak.
  int streak({DateTime? today}) {
    final now = today ?? DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (secondsOn(dayKey(day)) == 0) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var n = 0;
    while (secondsOn(dayKey(day)) > 0) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  /// Seconds read between [from] and [to], inclusive, by day.
  int secondsBetween(DateTime from, DateTime to) {
    final a = dayKey(from), b = dayKey(to);
    var total = 0;
    for (final day in _days.keys) {
      if (day.compareTo(a) >= 0 && day.compareTo(b) <= 0) {
        total += secondsOn(day);
      }
    }
    return total;
  }

  /// Adds [seconds] of reading [bookId] at [at] (now by default).
  void addReading(String bookId, int seconds, {DateTime? at}) {
    if (seconds <= 0) return;
    final books = (_days[dayKey(at ?? DateTime.now())] ??= {})[device] ??= {};
    books[bookId] = (books[bookId] ?? 0) + seconds;
    _changed();
  }

  /// Folds a timed stretch of reading into the pace estimates.
  void learnPace({double? minutes, double? units, int? pages}) {
    if (minutes == null || minutes < 2) return;
    if (units != null && units >= 3) {
      final pace = (minutes / units).clamp(0.2, 5.0);
      _minutesPerUnit = _minutesPerUnit * 0.7 + pace * 0.3;
    }
    if (pages != null && pages >= 3) {
      final pace = (minutes * 60 / pages).clamp(10.0, 600.0);
      _secondsPerPage = _secondsPerPage * 0.7 + pace * 0.3;
    }
    _changed();
  }

  void markFinished(String bookId, {DateTime? at}) {
    if (_finished.containsKey(bookId)) return;
    _finished[bookId] = at ?? DateTime.now();
    _changed();
  }

  void setGoal(int minutes) {
    _goalMinutes = minutes.clamp(5, 600);
    _goalUpdatedAt = DateTime.now();
    _changed();
  }

  void _changed() {
    notifyListeners();
    _saveTimer ??= Timer(const Duration(seconds: 5), () {
      _saveTimer = null;
      _saveLocal();
    });
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(minutes: 1), sync);
  }

  Future<void> load() async {
    final file = _localFile;
    if (file != null && await file.exists()) {
      try {
        _merge(jsonDecode(await file.readAsString()));
      } on FormatException {
        // A damaged file starts afresh.
      }
    }
    notifyListeners();
    unawaited(sync());
  }

  Future<void> sync() async {
    final remote = _remote;
    if (remote == null) return;
    try {
      final text = await remote.read();
      if (text != null) {
        _merge(jsonDecode(text));
        notifyListeners();
      }
      await _saveLocal();
      await remote.write(encode());
    } catch (_) {
      // Offline: kept locally and pushed on the next sync.
    }
  }

  Future<void> flush() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      await _saveLocal();
    }
    if (_pushTimer?.isActive ?? false) {
      _pushTimer!.cancel();
      await sync();
    }
  }

  String encode() => jsonEncode({
    'version': 1,
    'days': _days,
    'finished': {
      for (final e in _finished.entries)
        e.key: e.value.toUtc().toIso8601String(),
    },
    'goalMinutes': _goalMinutes,
    'goalUpdatedAt': _goalUpdatedAt.toUtc().toIso8601String(),
    'minutesPerUnit': _minutesPerUnit,
    'secondsPerPage': _secondsPerPage,
  });

  /// Merges another copy into this one.
  void _merge(Object? json) {
    if (json is! Map) return;
    if (json['days'] case final Map days) {
      for (final MapEntry(key: day, value: devices) in days.entries) {
        if (devices is! Map) continue;
        final ourDay = _days[day as String] ??= {};
        for (final MapEntry(key: dev, value: books) in devices.entries) {
          if (books is! Map) continue;
          final ours = ourDay[dev as String] ??= {};
          for (final MapEntry(key: id, value: s) in books.entries) {
            if (s is int) ours[id as String] = math.max(ours[id] ?? 0, s);
          }
        }
      }
    }
    if (json['finished'] case final Map finished) {
      for (final MapEntry(:key, :value) in finished.entries) {
        final at = DateTime.tryParse('$value');
        if (at != null && !_finished.containsKey(key)) _finished['$key'] = at;
      }
    }
    final goalAt = DateTime.tryParse('${json['goalUpdatedAt']}');
    if (json['goalMinutes'] case final int goal
        when goalAt != null && goalAt.isAfter(_goalUpdatedAt)) {
      _goalMinutes = goal;
      _goalUpdatedAt = goalAt;
    }
    if (json['minutesPerUnit'] case final num v) _minutesPerUnit = v.toDouble();
    if (json['secondsPerPage'] case final num v) _secondsPerPage = v.toDouble();
  }

  Future<void> _saveLocal() async {
    final file = _localFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(encode());
    } catch (_) {
      // Next change tries again.
    }
  }
}

/// Times one reading session: counts the seconds the book is open while
/// the reader is active (turning pages, or listening), and learns the pace.
class ReadingSession {
  ReadingSession(
    this._stats,
    this.bookId, {
    this.idle = const Duration(minutes: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _lastActivity = (now ?? DateTime.now)();

  final ReadingStats _stats;
  final String bookId;

  /// How long without a page turn still counts as reading.
  final Duration idle;
  final DateTime Function() _now;

  DateTime? _lastTick;
  DateTime _lastActivity;
  bool _paused = false;
  int _seconds = 0;
  double? _startUnits;
  double? _lastUnits;
  int? _startPage;
  int? _lastPage;

  /// Called on every page turn with the time left in the book (in foliate
  /// time units) or the page number.
  void activity({double? unitsLeft, int? page}) {
    _lastActivity = _now();
    if (unitsLeft != null) {
      // A jump (contents, slider, search) restarts the pace measurement.
      if (_lastUnits != null && (unitsLeft - _lastUnits!).abs() > 20) {
        _startUnits = null;
      }
      _startUnits ??= unitsLeft;
      _lastUnits = unitsLeft;
    }
    if (page != null) {
      if (_lastPage != null && (page - _lastPage!).abs() > 3) _startPage = null;
      _startPage ??= page;
      _lastPage = page;
    }
  }

  /// Counts time since the last tick if the user was reading; call every
  /// few seconds. [listening] counts read-aloud as reading.
  void tick({bool listening = false}) {
    final now = _now();
    final last = _lastTick;
    _lastTick = now;
    if (last == null || _paused) return;
    final active = listening || now.difference(_lastActivity) < idle;
    if (!active) return;
    final seconds = now.difference(last).inSeconds.clamp(0, 60);
    _seconds += seconds;
    _stats.addReading(bookId, seconds);
  }

  /// The app went to the background (or came back).
  set paused(bool value) {
    _paused = value;
    _lastTick = value ? null : _now();
  }

  /// Folds this session's pace into the estimates.
  void end() {
    final minutes = _seconds / 60;
    _stats.learnPace(
      minutes: minutes,
      units: _startUnits != null && _lastUnits != null
          ? _startUnits! - _lastUnits!
          : null,
      pages: _startPage != null && _lastPage != null
          ? _lastPage! - _startPage!
          : null,
    );
  }
}

/// "12 min", "1 h 5 min" or "under a minute".
String formatMinutes(double minutes) {
  final m = minutes.round();
  if (m < 1) return 'under a minute';
  if (m < 60) return '$m min';
  final h = m ~/ 60, rest = m % 60;
  return rest == 0 ? '$h h' : '$h h $rest min';
}
