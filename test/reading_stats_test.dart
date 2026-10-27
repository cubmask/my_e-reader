import 'dart:io';

import 'package:ebook_reader/library/reading_stats.dart';
import 'package:ebook_reader/reader/progress_store.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _Remote implements ProgressRemote {
  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String contents) async => text = contents;
}

void main() {
  test('adds up days, books and devices without double counting', () async {
    final remote = _Remote();
    final tablet = ReadingStats(null, remote, device: 'tab');
    final phone = ReadingStats(null, remote, device: 'phone');
    final day = DateTime(2026, 10, 27, 20);
    tablet.addReading('dune', 600, at: day);
    tablet.addReading('dune', 300, at: day);
    phone.addReading('emma', 120, at: day);
    await tablet.sync();
    await phone.sync();
    await tablet.sync();
    // Syncing twice must not count anything again.
    await phone.sync();
    expect(phone.secondsOn(dayKey(day)), 1020);
    expect(tablet.secondsOn(dayKey(day)), 1020);
    expect(tablet.secondsByBook, {'dune': 900, 'emma': 120});
  });

  test('streaks run up to yesterday until today is read', () {
    final stats = ReadingStats(null, null, device: 'd');
    final today = DateTime(2026, 10, 27, 12);
    for (final d in [24, 25, 26]) {
      stats.addReading('b', 60, at: DateTime(2026, 10, d, 9));
    }
    expect(stats.streak(today: today), 3);
    stats.addReading('b', 60, at: today);
    expect(stats.streak(today: today), 4);
    expect(stats.lastDays(3, today: today), [60, 60, 60]);
    expect(stats.streak(today: DateTime(2026, 10, 30)), 0);
  });

  test('the goal and finished books survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('stats');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/stats.json');
    final stats = ReadingStats(file, null, device: 'd')
      ..setGoal(45)
      ..markFinished('dune', at: DateTime(2026, 3, 1));
    await stats.flush();
    final again = ReadingStats(file, null, device: 'd');
    await again.load();
    expect(again.goalMinutes, 45);
    expect(again.finished.keys, ['dune']);
  });

  test('a session counts active time and learns the pace', () {
    fakeAsync((async) {
      final stats = ReadingStats(null, null, device: 'd');
      final clock = async.getClock(DateTime(2026, 10, 27, 20));
      final session = ReadingSession(stats, 'dune', now: clock.now);
      session.tick();
      for (var i = 0; i < 20; i++) {
        session.activity(unitsLeft: 100.0 - i, page: null);
        async.elapse(const Duration(seconds: 15));
        session.tick();
      }
      // Idle for ten minutes: only the first three count.
      for (var i = 0; i < 40; i++) {
        async.elapse(const Duration(seconds: 15));
        session.tick();
      }
      final seconds = stats.secondsByBook['dune']!;
      expect(seconds, 450);
      session.end();
      // 19 units in about 8 minutes is faster than the default 1 min each.
      expect(stats.minutesPerUnit, lessThan(1));
    });
  });

  test('minutes read nicely', () {
    expect(formatMinutes(0.4), 'under a minute');
    expect(formatMinutes(12), '12 min');
    expect(formatMinutes(65), '1 h 5 min');
    expect(formatMinutes(120), '2 h');
  });
}
