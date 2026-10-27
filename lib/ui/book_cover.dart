import 'dart:io';

import 'package:flutter/material.dart';

import '../library/book.dart';
import '../reader/reader_services.dart';
import 'theme.dart';

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
          // A long soft shadow falling down and right, plus a tight one
          // where the book meets the page, so covers sit like hardbacks.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 28,
                offset: Offset(10, 18),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 4,
                offset: Offset(1, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(2),
              right: Radius.circular(4),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (image != null)
                  LayoutBuilder(
                    // Decode the picture at the size it is shown, not at
                    // the size it was downloaded, to keep memory down.
                    builder: (context, box) => Image.file(
                      image,
                      fit: BoxFit.cover,
                      cacheWidth: box.maxWidth.isFinite
                          ? (box.maxWidth *
                                    MediaQuery.devicePixelRatioOf(context))
                                .ceil()
                          : null,
                      errorBuilder: (_, _, _) => GeneratedCover(
                        seed: book.driveFileId,
                        title: title,
                        author: author,
                      ),
                    ),
                  )
                else
                  GeneratedCover(
                    seed: book.driveFileId,
                    title: title,
                    author: author,
                  ),
                const _Spine(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The hinge of a hardback: a dark fold and a glint of light near the left
/// edge, and a faint sheen across the cover.
class _Spine extends StatelessWidget {
  const _Spine();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0x4D000000),
              Color(0x1FFFFFFF),
              Color(0x00FFFFFF),
              Color(0x26000000),
              Color(0x00000000),
              Color(0x0FFFFFFF),
              Color(0x00000000),
            ],
            stops: [0, 0.025, 0.045, 0.06, 0.09, 0.5, 1],
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
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFonts.serif,
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
