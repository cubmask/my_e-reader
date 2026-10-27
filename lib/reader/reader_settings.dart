import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, dark }

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

  ReaderTheme get theme => _theme;

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
    notifyListeners();
  }

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> setTheme(ReaderTheme theme) async {
    _theme = theme;
    notifyListeners();
    await (await _store).setString(_themeKey, theme.name);
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
