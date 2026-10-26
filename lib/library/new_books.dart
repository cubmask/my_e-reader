import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book.dart';

/// Books recently added to the Drive folder, for the hero on Home.
///
/// A book counts as new for [window] after it arrives in Drive, until it is
/// opened or dismissed.
class NewBooks extends ChangeNotifier {
  NewBooks({this.window = const Duration(days: 14)});

  final Duration window;
  static const _key = 'library.dismissedNew';
  final _dismissed = <String>{};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _dismissed.addAll(prefs.getStringList(_key) ?? const []);
    notifyListeners();
  }

  /// New books, newest first. [opened] says whether a book has been read.
  List<Book> of(
    List<Book> books, {
    required bool Function(Book) opened,
    DateTime? now,
  }) {
    final since = (now ?? DateTime.now()).subtract(window);
    return [
      for (final b in books)
        if (b.createdTime case final created?)
          if (created.isAfter(since) &&
              !opened(b) &&
              !_dismissed.contains(b.driveFileId))
            b,
    ]..sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
  }

  Future<void> dismiss(Iterable<Book> books) async {
    _dismissed.addAll(books.map((b) => b.driveFileId));
    notifyListeners();
    await (await SharedPreferences.getInstance()).setStringList(
      _key,
      _dismissed.toList(),
    );
  }
}
