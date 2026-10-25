import 'package:ebook_reader/app.dart';
import 'package:ebook_reader/drive/drive_auth.dart';
import 'package:ebook_reader/library/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeAuth implements DriveAuth {
  @override
  Future<http.Client> signIn() async => http.Client();
  @override
  Future<void> signOut() async {}
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ReaderApp(controller: LibraryController(auth: _FakeAuth())),
  );
}

void main() {
  testWidgets('tablet landscape uses an extended navigation rail', (
    tester,
  ) async {
    // Galaxy Tab S9 Ultra landscape, in logical pixels.
    await _pumpAt(tester, const Size(1848, 1155));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('phone width uses a bottom navigation bar', (tester) async {
    await _pumpAt(tester, const Size(400, 860));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });
}
