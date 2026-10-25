# My E-Reader

A personal ebook reader and library manager built with Flutter. The primary
device is a Samsung Galaxy Tab S9 Ultra (Android); iPad, iPhone, Windows and
macOS run the same app. Books live in a Google Drive folder.

The full architecture and roadmap are in the
[plan document](https://claude.ai/artifact/3BywiMWRA5WHqkZhGdTkm3).

## Status

Phase 0 (foundations):

- Adaptive shell: extended navigation rail on tablets and desktops, bottom bar on phones.
- Google sign-in (google_sign_in on Android, iOS, macOS; browser sign-in on Windows).
- Library screen listing every supported book in the chosen Drive folder and its subfolders, with search and format filters.
- Format detection for EPUB, MOBI, AZW3, FB2, TXT, DOC, DOCX, RTF, ODT, PDF, DjVu, CBZ, CBR, ZIP and RAR, each mapped to its reading engine.

Opening a book shows a placeholder until the reading engines land in phase 1.

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
