import 'package:ebook_reader/reader/appearance_sheet.dart';
import 'package:ebook_reader/reader/reader_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('settings are kept between launches', () async {
    final settings = ReaderSettings();
    await settings.load();
    expect(settings.webStyle['flow'], 'paginated');
    expect(settings.webStyle['fontFamily'], isNull);

    await settings.setFont(ReaderFont.serif);
    await settings.setLineHeight(1.83);
    await settings.setMargins(ReaderMargins.wide);
    await settings.setJustify(false);
    await settings.setScrolled(true);
    await settings.setSpread(false);
    await settings.saveBrightness(0.3);
    await settings.setKeepAwake(false);

    final again = ReaderSettings();
    await again.load();
    expect(again.font, ReaderFont.serif);
    expect(again.lineHeight, 1.8);
    expect(again.margins, ReaderMargins.wide);
    expect(again.justify, isFalse);
    expect(again.spread, isFalse);
    expect(again.brightness, 0.3);
    expect(again.keepAwake, isFalse);
    expect(again.webStyle, containsPair('flow', 'scrolled'));
    expect(again.webStyle, containsPair('gap', '12%'));

    await again.saveBrightness(null);
    final third = ReaderSettings();
    await third.load();
    expect(third.brightness, isNull);
  });

  testWidgets('the sheet hides type settings for page images', (tester) async {
    final settings = ReaderSettings();
    await settings.load();
    Future<void> show(bool reflowable) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppearanceSheet(settings: settings, reflowable: reflowable),
        ),
      ),
    );
    await show(true);
    expect(find.text('Line spacing 1.5'), findsOneWidget);
    await tester.tap(find.text('Wide'));
    await tester.pump();
    expect(settings.margins, ReaderMargins.wide);

    await show(false);
    expect(find.text('Line spacing 1.5'), findsNothing);
    expect(find.text('Two pages side by side'), findsOneWidget);
  });
}
