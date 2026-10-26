# My E-Reader

A personal ebook reader and library manager built with Flutter. The primary
device is a Samsung Galaxy Tab S9 Ultra (Android); iPad, iPhone, Windows and
macOS run the same app. Books live in a Google Drive folder.

The full architecture and roadmap are in the
[plan document](https://claude.ai/artifact/3BywiMWRA5WHqkZhGdTkm3).

## Status

Phase 4 starts with office documents. DOC, DOCX, RTF and ODT files are converted by Google Drive on first open: the app makes a temporary Google Docs copy, exports it as EPUB, deletes the copy and caches the EPUB. Everything else (highlights, read aloud, spreads) then works as for any EPUB. This needs the extra `drive.file` permission, so Google asks for consent once more after updating. Very large documents (over Drive's 10 MB export limit) can't be converted.

Phase 3 added notes and read-aloud:

- Select text to highlight it in yellow, green, blue or pink, with an optional note. Tap a highlight to recolour, edit or delete it.
- Bookmark any page, including PDF pages. The notes button lists the book's highlights and bookmarks.
- The Notes tab lists every highlight across the library, with search and a copy-as-Markdown export. Tap one to jump back into the book.
- Highlights and notes sync through a hidden `annotations.json` in Drive's app data folder, like reading progress.
- Read aloud uses the system voices (Samsung or Google on Android). It highlights each sentence as it's spoken, turns pages and chapters by itself, and runs at 0.75x to 2x speed. PDFs are read page by page.

Phase 2 added DjVu (rendered with DjVu.js), CBR and RAR (UnRAR compiled to WebAssembly, run in a worker), and ZIP. An archive that holds one book opens as that book; one full of page images opens as a comic.

Phase 1 (MVP reader) added:

- Books download from Drive on first open and stay cached for offline reading (2 GB, least recently opened evicted first).
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
