import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, dark }

/// A page colour with the text colour that goes on it.
@immutable
class Paper {
  const Paper(this.name, this.page, this.text);

  final String name;
  final Color page;
  final Color text;

  /// The built-in papers, as the reader's themes draw them.
  static const builtIn = {
    ReaderTheme.light: Paper('Light', Color(0xFFFBF9F4), Color(0xFF23262D)),
    ReaderTheme.sepia: Paper('Sepia', Color(0xFFF4ECD8), Color(0xFF433422)),
    ReaderTheme.dark: Paper('Dark', Color(0xFF1B1A18), Color(0xFFE6E1D8)),
  };

  /// Starting points for a paper of one's own.
  static const starters = [
    Paper('Sage', Color(0xFFE3EBDD), Color(0xFF26331F)),
    Paper('Mist', Color(0xFFE4EAF0), Color(0xFF1F2A36)),
    Paper('Rose', Color(0xFFF6E6E4), Color(0xFF3D2522)),
    Paper('Stone', Color(0xFFE6E2DA), Color(0xFF2E2B26)),
    Paper('Slate', Color(0xFF2B3138), Color(0xFFDCE1E6)),
    Paper('Ink', Color(0xFF101418), Color(0xFFB9C2CC)),
  ];

  bool get dark => page.computeLuminance() < 0.3;

  /// How far the text stands out from the page, from 1 to 21; text below
  /// 4.5 is hard to read.
  double get contrast => contrastRatio(page, text);

  Paper copyWith({String? name, Color? page, Color? text}) =>
      Paper(name ?? this.name, page ?? this.page, text ?? this.text);

  Map<String, Object> toJson() => {
    'name': name,
    'page': page.toARGB32(),
    'text': text.toARGB32(),
  };

  static Paper? fromJson(Object? json) => switch (json) {
    {
      'name': final String name,
      'page': final int page,
      'text': final int text,
    } =>
      Paper(name, Color(page), Color(text)),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Paper &&
      other.name == name &&
      other.page == page &&
      other.text == text;

  @override
  int get hashCode => Object.hash(name, page, text);
}

/// The WCAG contrast ratio between two colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// `#rrggbb` for CSS.
String cssColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Where a tap turns the page in a reflowable book; the middle third
/// always shows the controls.
enum TapZones {
  /// Left third back, right third forward.
  sides('Sides'),

  /// Top third back, bottom third forward, handy lying down.
  topBottom('Top & bottom');

  const TapZones(this.label);

  final String label;
}

/// The typeface for reflowable books; [original] keeps the book's own.
enum ReaderFont {
  original('Original', null),
  serif('Serif', 'Georgia, "Noto Serif", serif'),
  sans('Sans', '"Roboto", "Segoe UI", system-ui, sans-serif'),
  mono('Mono', '"Roboto Mono", "Cascadia Mono", monospace');

  const ReaderFont(this.label, this.css);

  final String label;

  /// The CSS font-family list, or null to keep the book's fonts.
  final String? css;
}

/// Space around the text.
enum ReaderMargins {
  narrow('Narrow', '3%'),
  normal('Normal', '6%'),
  wide('Wide', '12%');

  const ReaderMargins(this.label, this.gap);

  final String label;

  /// foliate-js's gap between the page edge and the text, and between
  /// columns.
  final String gap;
}

/// Reading appearance, shared by every book and kept between launches.
class ReaderSettings extends ChangeNotifier {
  static const _themeKey = 'reader.theme';
  static const _fontKey = 'reader.fontSize';
  static const _familyKey = 'reader.font';
  static const _lineHeightKey = 'reader.lineHeight';
  static const _marginsKey = 'reader.margins';
  static const _justifyKey = 'reader.justify';
  static const _scrolledKey = 'reader.scrolled';
  static const _spreadKey = 'reader.spread';
  static const _brightnessKey = 'reader.brightness';
  static const _awakeKey = 'reader.keepAwake';
  static const _papersKey = 'reader.papers';
  static const _paperKey = 'reader.paper';
  static const _tapZonesKey = 'reader.tapZones';
  static const minFont = 70, maxFont = 200;
  static const minLineHeight = 1.2, maxLineHeight = 2.2;

  SharedPreferences? _prefs;
  ReaderTheme _theme = ReaderTheme.light;
  int _fontSize = 100;
  ReaderFont _font = ReaderFont.original;
  double _lineHeight = 1.5;
  ReaderMargins _margins = ReaderMargins.normal;
  bool _justify = true;
  bool _scrolled = false;
  bool _spread = true;
  double? _brightness;
  bool _keepAwake = true;
  List<Paper> _papers = const [];
  int? _paper;
  TapZones _tapZones = TapZones.sides;

  ReaderTheme get theme => _theme;

  /// Papers the reader made, after the built-in ones.
  List<Paper> get papers => _papers;

  /// Which of [papers] is in use; null for the built-in [theme].
  int? get customPaper => _paper;

  /// The page and text colours in use.
  Paper get paper => _paper == null ? Paper.builtIn[_theme]! : _papers[_paper!];

  TapZones get tapZones => _tapZones;

  /// Text size as a percentage of the book's own size.
  int get fontSize => _fontSize;
  ReaderFont get font => _font;
  double get lineHeight => _lineHeight;
  ReaderMargins get margins => _margins;

  /// Justified text, else ragged right.
  bool get justify => _justify;

  /// One long scroll instead of pages.
  bool get scrolled => _scrolled;

  /// Two pages side by side on a wide screen.
  bool get spread => _spread;

  /// Screen brightness while reading, 0 to 1; null follows the system.
  double? get brightness => _brightness;

  /// Whether the screen stays on while a book is open.
  bool get keepAwake => _keepAwake;

  /// The style the web reader applies, as `window.reader.setStyle` takes it.
  Map<String, Object?> get webStyle => {
    'theme': _theme.name,
    'paper': _paper == null
        ? null
        : {
            'bg': cssColor(paper.page),
            'fg': cssColor(paper.text),
            'dark': paper.dark,
          },
    'fontSize': _fontSize,
    'fontFamily': _font.css,
    'lineHeight': _lineHeight,
    'justify': _justify,
    'gap': _margins.gap,
    'flow': _scrolled ? 'scrolled' : 'paginated',
  };

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _theme =
        ReaderTheme.values.asNameMap()[prefs.getString(_themeKey)] ??
        ReaderTheme.light;
    _fontSize = (prefs.getInt(_fontKey) ?? 100).clamp(minFont, maxFont);
    _font =
        ReaderFont.values.asNameMap()[prefs.getString(_familyKey)] ??
        ReaderFont.original;
    _lineHeight = (prefs.getDouble(_lineHeightKey) ?? 1.5).clamp(
      minLineHeight,
      maxLineHeight,
    );
    _margins =
        ReaderMargins.values.asNameMap()[prefs.getString(_marginsKey)] ??
        ReaderMargins.normal;
    _justify = prefs.getBool(_justifyKey) ?? true;
    _scrolled = prefs.getBool(_scrolledKey) ?? false;
    _spread = prefs.getBool(_spreadKey) ?? true;
    _brightness = prefs.getDouble(_brightnessKey);
    _keepAwake = prefs.getBool(_awakeKey) ?? true;
    _papers = [
      for (final text in prefs.getStringList(_papersKey) ?? const <String>[])
        ?_decodePaper(text),
    ];
    final chosen = prefs.getInt(_paperKey);
    _paper = chosen != null && chosen >= 0 && chosen < _papers.length
        ? chosen
        : null;
    _tapZones =
        TapZones.values.asNameMap()[prefs.getString(_tapZonesKey)] ??
        TapZones.sides;
    notifyListeners();
  }

  static Paper? _decodePaper(String text) {
    try {
      return Paper.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> setTheme(ReaderTheme theme) async {
    _theme = theme;
    _paper = null;
    notifyListeners();
    final prefs = await _store;
    await prefs.setString(_themeKey, theme.name);
    await prefs.remove(_paperKey);
  }

  /// Reads on one of [papers].
  Future<void> usePaper(int index) async {
    _paper = index;
    notifyListeners();
    await (await _store).setInt(_paperKey, index);
  }

  /// Adds [paper], or replaces the one at [index], and reads on it.
  Future<void> savePaper(Paper paper, {int? index}) async {
    final papers = [..._papers];
    if (index == null) {
      papers.add(paper);
      index = papers.length - 1;
    } else {
      papers[index] = paper;
    }
    _papers = papers;
    await _savePapers();
    await usePaper(index);
  }

  Future<void> deletePaper(int index) async {
    final current = _paper;
    _papers = [..._papers]..removeAt(index);
    if (current == index) {
      _paper = null;
    } else if (current != null && current > index) {
      _paper = current - 1;
    }
    notifyListeners();
    await _savePapers();
    final prefs = await _store;
    if (_paper == null) {
      await prefs.remove(_paperKey);
    } else {
      await prefs.setInt(_paperKey, _paper!);
    }
  }

  Future<void> _savePapers() async => (await _store).setStringList(_papersKey, [
    for (final p in _papers) jsonEncode(p.toJson()),
  ]);

  Future<void> setTapZones(TapZones zones) async {
    _tapZones = zones;
    notifyListeners();
    await (await _store).setString(_tapZonesKey, zones.name);
  }

  Future<void> setFontSize(int size) async {
    _fontSize = size.clamp(minFont, maxFont);
    notifyListeners();
    await (await _store).setInt(_fontKey, _fontSize);
  }

  Future<void> setFont(ReaderFont font) async {
    _font = font;
    notifyListeners();
    await (await _store).setString(_familyKey, font.name);
  }

  Future<void> setLineHeight(double value) async {
    _lineHeight = (value * 10).roundToDouble() / 10;
    _lineHeight = _lineHeight.clamp(minLineHeight, maxLineHeight);
    notifyListeners();
    await (await _store).setDouble(_lineHeightKey, _lineHeight);
  }

  Future<void> setMargins(ReaderMargins margins) async {
    _margins = margins;
    notifyListeners();
    await (await _store).setString(_marginsKey, margins.name);
  }

  Future<void> setJustify(bool value) async {
    _justify = value;
    notifyListeners();
    await (await _store).setBool(_justifyKey, value);
  }

  Future<void> setScrolled(bool value) async {
    _scrolled = value;
    notifyListeners();
    await (await _store).setBool(_scrolledKey, value);
  }

  Future<void> setSpread(bool value) async {
    _spread = value;
    notifyListeners();
    await (await _store).setBool(_spreadKey, value);
  }

  /// Changes brightness as a slider moves; [saveBrightness] keeps it.
  void previewBrightness(double? value) {
    _brightness = value;
    notifyListeners();
  }

  Future<void> saveBrightness(double? value) async {
    previewBrightness(value);
    final prefs = await _store;
    if (value == null) {
      await prefs.remove(_brightnessKey);
    } else {
      await prefs.setDouble(_brightnessKey, value);
    }
  }

  Future<void> setKeepAwake(bool value) async {
    _keepAwake = value;
    notifyListeners();
    await (await _store).setBool(_awakeKey, value);
  }
}
