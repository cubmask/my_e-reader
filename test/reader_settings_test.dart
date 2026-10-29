import 'package:ebook_reader/reader/appearance_sheet.dart';
import 'package:ebook_reader/reader/paper_editor.dart';
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

  test('papers of your own are kept, used and deleted', () async {
    final settings = ReaderSettings();
    await settings.load();
    expect(settings.paper, Paper.builtIn[ReaderTheme.light]);
    expect(settings.webStyle['paper'], isNull);

    await settings.savePaper(Paper.starters.first);
    await settings.savePaper(Paper.starters.last.copyWith(name: 'Night'));
    expect(settings.customPaper, 1);
    expect(settings.webStyle['paper'], {
      'bg': '#101418',
      'fg': '#b9c2cc',
      'dark': true,
    });
    await settings.setTapZones(TapZones.topBottom);

    final again = ReaderSettings();
    await again.load();
    expect(again.papers.map((p) => p.name), ['Sage', 'Night']);
    expect(again.paper.name, 'Night');
    expect(again.tapZones, TapZones.topBottom);

    await again.deletePaper(0);
    expect(again.paper.name, 'Night');
    await again.setTheme(ReaderTheme.sepia);
    expect(again.customPaper, isNull);
    expect(again.paper, Paper.builtIn[ReaderTheme.sepia]);
  });

  test('contrast follows the WCAG ratio', () {
    expect(
      contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.01),
    );
    expect(Paper.builtIn.values.every((p) => p.contrast >= 4.5), isTrue);
    expect(Paper.starters.every((p) => p.contrast >= 4.5), isTrue);
  });

  testWidgets('the paper editor warns when text is hard to read', (
    tester,
  ) async {
    Paper? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showDialog<Paper>(
              context: context,
              builder: (_) => const PaperEditor(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hard to read'), findsNothing);
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Hex'), 'D0D8CC');
    await tester.pump();
    expect(find.textContaining('Hard to read'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.name, 'Sage');
    expect(saved!.text, const Color(0xFFD0D8CC));
  });
}
