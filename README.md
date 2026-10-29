# My E-Reader

A personal ebook reader and library manager built with Flutter. The primary
device is a Samsung Galaxy Tab S9 Ultra (Android); iPad, iPhone, Windows and
macOS run the same app. Books live in a Google Drive folder.

The full architecture and roadmap are in the
[plan document](https://claude.ai/artifact/3BywiMWRA5WHqkZhGdTkm3).

## Status

The interface follows Apple Books:

- **Home** opens on a large *Continue reading* card for the book you read last. Below it are shelves of recent books, books on this device and books not started yet.
- **New in your Drive:** books added to the Drive folder in the last 14 days appear in a hero above *Continue reading*, with cover, author and description. A book leaves the hero once it is opened or dismissed, and the hero is hidden when there is nothing new.
- **Library** is a grid of covers with progress (or a NEW badge), a search bar, one row of filter chips (downloaded, collections, formats) and a sort menu (recently read, title, author, recently added).
- **Covers:**
  - In order of preference, a cover is one you picked online, the book's own (read the first time it opens), one found by the automatic lookup, or Drive's preview image (PDFs).
  - Other books get a typeset cover in a muted colour.
- **Book sheet:** tapping a cover opens the book. Long-pressing it, or tapping its *More* button, opens a sheet with the cover, details, progress, *Read/Continue*, *Download* and editing.
- **Reader and theme:**
  - The reader's bars are frosted and tinted to the page, in light or dark to match the reading theme.
  - The theme uses plain white or black backgrounds with an orange accent.

The latest round filled the biggest gaps:

- **Search inside a book**, for EPUBs and PDFs alike, with every match listed in context and highlighted on the page.
- **PDFs** gained a contents list from the PDF's outline, text highlights with notes (stored as character ranges, synced with the rest) and the position slider.
- **Reading settings:** font, line spacing, margins, justification, scrolled or paged layout, single or two-page spreads, a brightness slider and keep-screen-on.
- **Look up** selected text: a dictionary definition (English, from dictionaryapi.dev), a Wikipedia summary, Google Translate, or a web search. Selected text can also be shared as a quote.
- **Add books from the tablet** with the + button in the Library, or by opening or sharing a file into the app. They upload to the Drive folder, and copies already there are skipped.
- **Sleep timer** for read aloud: after 5 to 60 minutes, or at the end of the chapter.
- **Series, tags and your own star rating** in a book's details, with a Series sort, tag filters and search over both.
- **Reading stats:** time read per day and per book, a daily goal, books finished this year and a streak, plus "12 min left in chapter" in the reader. Stats sync through a hidden `stats.json`.
- **Export notes** as Markdown (copy, share or save), and for PDFs with handwriting, a copy of the PDF with the ink drawn on, shared or saved to Drive next to the book. Pages with ink become pictures in that copy; the rest keep their text.
- **Convert books** between EPUB, PDF, DOCX, ODT and plain text from the book's sheet, through Google Docs. Text and structure come across; pictures and the book's own styling don't, and Drive's 10 MB export limit applies.

A few ideas came from the [Athene](https://theadipost.com/athene/docs/) reader:

- **Your place on another device:** each device keeps its own place in every book. When another device read further more recently, a note at the top names it, with the chapter and a *Go* button, instead of jumping there. It goes away once you turn a page.
- **Cleaner PDF read aloud:** running heads, page numbers and small-type footnotes are skipped, reference marks like [12] and web addresses are dropped, words split across lines are joined, and a sentence that crosses a page break is read in one piece.
- **Papers of your own** in Appearance: page and text colours by hue, intensity and lightness or hex, starting from Sage, Mist, Rose, Stone, Slate or Ink. The contrast ratio is shown and flagged below 4.5 to 1. Long-press a paper to edit or delete it.
- **Tap zones:** pages turn by tapping the sides, or the top and bottom thirds for reading lying down. The zones are shaded for a moment when a book opens.
- **Ask about the page:** Settings > Ask about the page takes a Claude, OpenAI or OpenRouter key (kept in secure storage) or an Ollama server address. A question button then appears in the reader and over selected text. Only the pages around your position are sent (about a page and a half, or up to five pages of the chapter), so answers can't give away the ending, and the first question to each address asks before anything leaves the device. Claude defaults to Claude Opus 5.5.

Duplicate books are found in two ways: files with identical contents (by Drive's checksum) and files with the same title by the same author, usually one book in two formats. A *Duplicates* chip in the Library (and an entry in Settings) lists them. Identical extra copies start ticked for deletion, keeping the copy you're reading or else the oldest; other-format copies start unticked. One copy of each book is always kept. Duplicates are checked automatically every time the library refreshes. When new ones turn up, Home shows a *Duplicates found* card. Its *Delete n extra copies* button removes every extra identical copy in one go, after one confirmation, and *Review* opens the Duplicates screen, where *Tick all extra copies* also selects the other-format copies. Dismissing the card hides it until a new duplicate appears. Any book can also be deleted from its sheet with *Delete from Google Drive*. Deleting always asks first, then removes the file from Drive for good, without going to the Drive trash. Files someone else shared with you can't be deleted. Deleting needs full Drive access instead of read-only, so Google asks for consent once more after updating and warns that the app is unverified, which is expected for a personal app.

*Books that won't open* in Settings checks the whole library for files that fail to open and lists them grouped by why: no longer in Drive, refused by Drive, empty, not really a book (such as a web page saved as `.epub`), or damaged and cut short by an upload that never finished. The check reads only the first and last 64 KB of each file, so a large library costs little data, and later checks only look at new or changed books (the menu has *Check every book again*). A book that fails in the reader is added to the list too, with the reader's error, and drops off once it opens. *Copy the list* puts the titles, paths and reasons on the clipboard. Results stay on the device.

Book details and covers are looked up online, the way Calibre's *Download metadata* does. Each new book is searched once in [Google Books](https://developers.google.com/books) and [Open Library](https://openlibrary.org/developers/api) by its title and author (or by the file name, read as "Title - Author"). Only a confident match is used, and it fills in what is missing (description, publisher, date, ISBN, subjects, pages, rating, cover) without replacing what you typed. The book sheet shows these details and has *Find details and cover online* to search by hand and pick a match, which replaces everything. The automatic lookup can be turned off in Settings. Amazon and Goodreads aren't used because neither has a public API any more (Goodreads closed its API in 2020, and Amazon's needs an affiliate account). Google Books allows a modest number of keyless requests; for a big library, pass an API key with `--dart-define=GOOGLE_BOOKS_API_KEY=...`. Your Google sign-in is never sent to these services.

Books now stream from Google Drive instead of being stored automatically. PDFs page in straight from Drive through HTTP range requests, relayed by the loopback server, so a large PDF opens without downloading all of it. Other formats need the whole file, so they go to a temporary streaming cache that is trimmed past 300 MB. To keep a book for offline reading, tap the download button in the reader or use *Download* in the book's details (long-press its card). Downloaded books show a tick on their card and are never evicted. A *Downloaded* filter lists them, and Settings shows the space used, with options to remove all downloads or clear the streaming cache. A downloaded book that changes in Drive is fetched again when the library refreshes.

Phase 4 starts with office documents. DOC, DOCX, RTF and ODT files are converted by Google Drive on first open: the app makes a temporary Google Docs copy, exports it as EPUB, deletes the copy and caches the EPUB. Everything else (highlights, read aloud, spreads) then works as for any EPUB. This needs the extra `drive.file` permission, so Google asks for consent once more after updating. Very large documents (over Drive's 10 MB export limit) can't be converted.

The library now shows real titles and authors. Opening a book fills them in from its own metadata, and a long press (or right click) on a card edits the title, author and collections. Collections appear as chips above the format filters; long-press one to rename or delete it. These details sync through a hidden `library.json` in Drive's app data folder.

PDFs take handwritten notes. Tap the pen button in a PDF's top bar, then write with the S Pen (or Apple Pencil, or the mouse on desktop) while fingers still scroll and zoom. The toolbar has a pen in four colours, a highlighter, an eraser and undo; the S Pen's side button and a Surface pen's eraser end also erase. Strokes are stored per page in page coordinates, so they stay in place at any zoom and in two-page spreads, and sync through a hidden `ink.json`. They are not written into the PDF file in Drive.

Phase 3 added notes and read-aloud:

- Select text to highlight it in yellow, green, blue or pink, with an optional note. Tap a highlight to recolour, edit or delete it.
- Bookmark any page, including PDF pages. The notes button lists the book's highlights and bookmarks.
- The Notes tab lists every highlight across the library, with search and a copy-as-Markdown export. Tap one to jump back into the book.
- Highlights and notes sync through a hidden `annotations.json` in Drive's app data folder, like reading progress.
- Read aloud uses the system voices (Samsung or Google on Android). It highlights each sentence as it's spoken, turns pages and chapters by itself, and runs at 0.75x to 2x speed. PDFs are read page by page.
- Offline neural voice: Settings > Read aloud downloads [Supertonic 3](https://huggingface.co/Supertone/supertonic-3) (128 MB, run with [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)), ten natural voices for 31 languages that work without a connection. The reading language follows the book's metadata and the script of its text, or can be fixed in settings. Languages it doesn't speak (such as Chinese), or everything when it isn't downloaded, fall back to the system voices. Reading carries on with the screen locked, with pause and stop on the lock screen. To keep the APK small, build release copies with `flutter build apk --split-per-abi` and install the `arm64-v8a` one.
- Online voices: Settings > Read aloud > Online voice switches reading to [ElevenLabs](https://elevenlabs.io) (Eleven v4, Multilingual v2 or Flash v2.5) or [Fish Audio](https://fish.audio) (Drama 3 or S2.1 Pro) with your own API key, kept in the platform's secure storage. Pick any voice from your account or the provider's library, or paste a voice ID. The text being read is sent to the provider and billed to your account. When the connection drops or the service refuses a request, reading carries on from the same sentence with the offline voice.

Phase 2 added DjVu (rendered with DjVu.js), CBR and RAR (UnRAR compiled to WebAssembly, run in a worker), and ZIP. An archive that holds one book opens as that book; one full of page images opens as a comic.

Phase 1 (MVP reader) added:

- EPUB, MOBI, AZW3, FB2, TXT and CBZ open in a foliate-js reader inside a WebView, with tap zones, keyboard paging, contents, light/sepia/dark themes and text size.
- PDF opens in a native PDFium viewer.
- On a landscape tablet or desktop, books and PDFs show as two-page spreads.
- Reading position saves on every page turn and syncs to a hidden `progress.json` in Drive's app data folder, so every device resumes at the same place.

Phase 0 laid the groundwork: the adaptive shell, Google sign-in, the Drive library with search and format filters, and format detection for every planned type.

The reader page (`assets/reader/`) bundles [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT, see `assets/reader/foliate/VERSION`) plus the DjVu and RAR libraries listed in `assets/reader/vendor/README.md` and is served from a loopback-only server with a random path token. A Content Security Policy blocks scripts inside books.

## Google Cloud setup (one time)

1. Create a project at <https://console.cloud.google.com> and enable the **Google Drive API**.
2. Under **OAuth consent screen**, choose *External*, add yourself as a test user, then press **Publish app** so it is *In production*. The app stays unverified, which is fine for personal use, and sign-ins no longer expire every 7 days as they do in *Testing*.
3. Under **Credentials**, create OAuth client ids:
   - **Web application**: needed by Android. Pass it as `GOOGLE_WEB_CLIENT_ID`.
   - **Android**: package `com.cubmask.ebook_reader` and the SHA-1 from `cd android && ./gradlew signingReport`.
   - **Desktop app**: for Windows. Pass it as `GOOGLE_DESKTOP_CLIENT_ID` and `GOOGLE_DESKTOP_CLIENT_SECRET`.
   - **iOS** (only for iPad/iPhone/macOS): bundle id `com.cubmask.ebookReader`; add `GIDClientID` and the reversed client id URL scheme to `ios/Runner/Info.plist` and `macos/Runner/Info.plist`.

## Run on the Galaxy Tab S9 Ultra

Enable Developer options and USB debugging on the tablet, connect it, then:

```sh
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>.apps.googleusercontent.com
```

Every CI run also uploads a debug APK you can install directly on the tablet.

On first launch, sign in and paste the link to your books folder
(`https://drive.google.com/drive/folders/...`).

## Develop

```sh
flutter pub get
flutter analyze
flutter test
```
