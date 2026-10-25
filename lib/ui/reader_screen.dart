import 'package:flutter/material.dart';

import '../library/book.dart';

/// Placeholder until the reading engines land in phase 1.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.displayTitle)),
      body: Center(
        child: Text(
          '${book.format.label} uses the '
          '${book.format.engine.name} engine, which arrives in phase 1.',
        ),
      ),
    );
  }
}
