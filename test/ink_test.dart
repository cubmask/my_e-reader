import 'dart:io';

import 'package:ebook_reader/notes/ink_store.dart';
import 'package:ebook_reader/reader/ink_layer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late InkStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ink');
    store = InkStore(File('${dir.path}/ink.json'), null);
  });
  tearDown(() async {
    await store.flush();
    await dir.delete(recursive: true);
  });

  test('strokes round-trip, merge by newest and hit-test', () async {
    final s = store.add(
      bookId: 'b',
      page: 2,
      color: 0xFF000000,
      width: 0.003,
      points: const [Offset(0.1, 0.1), Offset(0.5, 0.1)],
    );
    final decoded = decodeInk(encodeInk([s]))[s.id]!;
    expect(decoded.points, s.points);
    expect(decoded.page, 2);
    expect(decoded.hits(const Offset(0.3, 0.105), 0.01), isTrue);
    expect(decoded.hits(const Offset(0.3, 0.2), 0.01), isFalse);

    final merged = mergeInk({s.id: s}, {s.id: s.delete()});
    expect(merged[s.id]!.deleted, isTrue);
  });

  test('undo removes a stroke and restores an erased one', () async {
    final ink = InkController();
    final s = store.add(
      bookId: 'b',
      page: 1,
      color: 0xFF000000,
      width: 0.003,
      points: const [Offset(0.1, 0.1)],
    );
    await store.remove([s]);
    expect(store.forPage('b', 1), isEmpty);
    await store.restore([s]);
    expect(store.forPage('b', 1), hasLength(1));
    expect(ink.canUndo, isFalse);
  });

  testWidgets('a stylus writes, a finger falls through to the viewer', (
    tester,
  ) async {
    final store = InkStore(null, null);
    final ink = InkController()..enabled = true;
    var pans = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 560,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => pans++,
                  ),
                ),
                Positioned.fill(
                  child: InkPageLayer(
                    bookId: 'b',
                    page: 1,
                    store: store,
                    controller: ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final centre = tester.getCenter(find.byType(InkPageLayer));

    final pen = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.stylus,
    );
    await pen.moveBy(const Offset(40, 0));
    await pen.moveBy(const Offset(40, 0));
    await pen.up();
    // Let the store finish writing its file.
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(pans, 0);
    final strokes = store.forPage('b', 1);
    expect(strokes, hasLength(1));
    expect(strokes.single.points.first.dx, closeTo(0.5, 0.01));
    expect(ink.canUndo, isTrue);

    final finger = await tester.startGesture(centre);
    await finger.moveBy(const Offset(0, 80));
    await finger.up();
    await tester.pumpAndSettle();
    expect(pans, 1);
    expect(store.forPage('b', 1), hasLength(1));

    await ink.undo(store);
    expect(store.forPage('b', 1), isEmpty);

    // Out of pen mode the stylus scrolls like a finger.
    ink.enabled = false;
    await tester.pump();
    final pen2 = await tester.startGesture(
      centre,
      kind: PointerDeviceKind.stylus,
    );
    await pen2.moveBy(const Offset(0, 80));
    await pen2.up();
    await tester.pumpAndSettle();
    expect(pans, 2);
    expect(store.forPage('b', 1), isEmpty);
  });
}
