import 'dart:io';

import 'package:ebook_reader/reader/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

ReadingProgress _p(String loc, int minute) => ReadingProgress(
  location: loc,
  fraction: minute / 100,
  updatedAt: DateTime.utc(2026, 10, 25, 12, minute),
);

class _MemoryRemote implements ProgressRemote {
  String? contents;
  int writes = 0;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String c) async {
    contents = c;
    writes++;
  }
}

void main() {
  test('merge keeps the newer entry for each book', () {
    final merged = mergeProgress(
      {'a': _p('local-a', 10), 'b': _p('local-b', 30)},
      {'a': _p('remote-a', 20), 'b': _p('remote-b', 5), 'c': _p('remote-c', 1)},
    );
    expect(merged['a']!.location, 'remote-a');
    expect(merged['b']!.location, 'local-b');
    expect(merged['c']!.location, 'remote-c');
  });

  test('encode and decode round-trip and skip bad entries', () {
    final text = encodeProgress({'a': _p('epubcfi(/6/4!/2)', 42)});
    final decoded = decodeProgress(text);
    expect(decoded['a']!.location, 'epubcfi(/6/4!/2)');
    expect(decoded['a']!.fraction, 0.42);
    expect(decoded['a']!.updatedAt, DateTime.utc(2026, 10, 25, 12, 42));
    expect(decodeProgress('{"books":{"x":{"location":1}}}'), isEmpty);
  });

  test('load merges the remote copy and pushes the result', () async {
    final dir = await Directory.systemTemp.createTemp('progress');
    addTearDown(() => dir.delete(recursive: true));
    final local = File('${dir.path}/progress.json');
    await local.writeAsString(encodeProgress({'a': _p('local', 50)}));
    final remote = _MemoryRemote()
      ..contents = encodeProgress({'a': _p('old', 1), 'b': _p('other', 2)});

    final store = ProgressStore(local, remote);
    await store.load();

    expect(store['a']!.location, 'local');
    expect(store['b']!.location, 'other');
    expect(decodeProgress(remote.contents!).keys, unorderedEquals(['a', 'b']));
    expect(decodeProgress(await local.readAsString()).keys, contains('b'));
  });

  test('save writes locally at once and flush pushes to the remote', () async {
    final dir = await Directory.systemTemp.createTemp('progress');
    addTearDown(() => dir.delete(recursive: true));
    final local = File('${dir.path}/progress.json');
    final remote = _MemoryRemote();
    final store = ProgressStore(local, remote);

    await store.save('a', _p('cfi', 3));
    expect(decodeProgress(await local.readAsString())['a']!.location, 'cfi');
    expect(remote.writes, 0);

    await store.flush();
    expect(decodeProgress(remote.contents!)['a']!.location, 'cfi');
  });

  test('a newer place read on another device is offered, not used', () async {
    final dir = await Directory.systemTemp.createTemp('progress');
    addTearDown(() => dir.delete(recursive: true));
    final remote = _MemoryRemote();
    final tablet = ProgressStore(
      File('${dir.path}/tablet.json'),
      remote,
      device: 'tab',
      deviceName: 'Galaxy Tab',
    );
    final phone = ProgressStore(
      File('${dir.path}/phone.json'),
      remote,
      device: 'ph',
      deviceName: 'Pixel',
    );
    await tablet.save('a', _p('cfi-10', 10));
    await tablet.flush();
    await phone.load();
    expect(phone.ownOf('a'), isNull);
    expect(phone.elsewhere('a'), isNull);
    expect(phone['a']!.deviceName, 'Galaxy Tab');

    await phone.save('a', _p('cfi-40', 40));
    await phone.flush();
    await tablet.sync();
    expect(tablet.ownOf('a')!.location, 'cfi-10');
    expect(tablet['a']!.location, 'cfi-40');
    expect(tablet.elsewhere('a')!.deviceName, 'Pixel');

    await tablet.save('a', _p('cfi-12', 50));
    expect(tablet.elsewhere('a'), isNull);

    // The own places survive a restart, and stay off the synced copy.
    final again = ProgressStore(
      File('${dir.path}/tablet.json'),
      null,
      device: 'tab',
    );
    await again.load();
    expect(again.ownOf('a')!.location, 'cfi-12');
    expect(remote.contents, isNot(contains('"own"')));
  });
}
