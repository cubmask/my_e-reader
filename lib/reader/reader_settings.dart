import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderTheme { light, sepia, dark }

/// Reading appearance, shared by every book and kept between launches.
class ReaderSettings extends ChangeNotifier {
  static const _themeKey = 'reader.theme';
  static const _fontKey = 'reader.fontSize';
  static const minFont = 70, maxFont = 200;

  ReaderTheme _theme = ReaderTheme.light;
  int _fontSize = 100;

  ReaderTheme get theme => _theme;

  /// Text size as a percentage of the book's own size.
  int get fontSize => _fontSize;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _theme =
        ReaderTheme.values.asNameMap()[prefs.getString(_themeKey)] ??
        ReaderTheme.light;
    _fontSize = (prefs.getInt(_fontKey) ?? 100).clamp(minFont, maxFont);
    notifyListeners();
  }

  Future<void> setTheme(ReaderTheme theme) async {
    _theme = theme;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _themeKey,
      theme.name,
    );
  }

  Future<void> setFontSize(int size) async {
    _fontSize = size.clamp(minFont, maxFont);
    notifyListeners();
    await (await SharedPreferences.getInstance()).setInt(_fontKey, _fontSize);
  }
}
