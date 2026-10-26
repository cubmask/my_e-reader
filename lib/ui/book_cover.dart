import 'dart:io';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../reader/reader_services.dart';

/// Covers are drawn at the usual 2:3 book shape.
const coverAspectRatio = 2 / 3;

/// A book's cover with a soft shadow, like a book on a shelf. Books without
/// a cover image get a typeset one in a colour picked from the book's id.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    required this.services,
    this.width,
  });

  final Book book;
  final ReaderServices? services;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final covers = services?.covers;
    final File? image = covers?.coverOf(book);
    final title = services?.meta.titleOf(book) ?? book.displayTitle;
    final author = services?.meta.authorOf(book) ?? '';
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: coverAspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: image != null
                ? Image.file(
                    image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => GeneratedCover(
                      seed: book.driveFileId,
                      title: title,
                      author: author,
                    ),
                  )
                : GeneratedCover(
                    seed: book.driveFileId,
                    title: title,
                    author: author,
                  ),
          ),
        ),
      ),
    );
  }
}

/// A plain typeset cover: a muted colour, the title in a serif face and the
/// author underneath.
class GeneratedCover extends StatelessWidget {
  const GeneratedCover({
    super.key,
    required this.seed,
    required this.title,
    required this.author,
  });

  final String seed;
  final String title;
  final String author;

  static const _palettes = [
    (Color(0xFF2F4858), Color(0xFF33658A)),
    (Color(0xFF5B3A29), Color(0xFF8C5A3C)),
    (Color(0xFF3D5A40), Color(0xFF5F8463)),
    (Color(0xFF4A3B5C), Color(0xFF6E5A8A)),
    (Color(0xFF7A2E2E), Color(0xFFA14A3E)),
    (Color(0xFF1F3A5F), Color(0xFF3E6A9E)),
    (Color(0xFF5C4B1E), Color(0xFF8D7533)),
    (Color(0xFF263238), Color(0xFF4F6470)),
  ];

  @override
  Widget build(BuildContext context) {
    final (top, bottom) =
        _palettes[seed.codeUnits.fold(0, (a, b) => a + b) % _palettes.length];
    return LayoutBuilder(
      builder: (context, box) {
        final scale = box.maxWidth / 160;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [top, bottom],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28 * scale,
                  height: 2 * scale,
                  color: Colors.white54,
                ),
                SizedBox(height: 10 * scale),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17 * scale,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'serif',
                      fontFamilyFallback: const ['Georgia', 'Times New Roman'],
                    ),
                  ),
                ),
                if (author.isNotEmpty)
                  Text(
                    author.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9 * scale,
                      letterSpacing: 1.2 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
