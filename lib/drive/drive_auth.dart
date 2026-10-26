import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Read the books folder, read/write sync data in the hidden app folder, and
/// create (then delete) the temporary Google Docs copies used to convert
/// office documents.
const driveScopes = [
  drive.DriveApi.driveReadonlyScope,
  drive.DriveApi.driveAppdataScope,
  drive.DriveApi.driveFileScope,
];

/// Signs the user in to Google and returns an authorised HTTP client.
abstract interface class DriveAuth {
  Future<http.Client> signIn();
  Future<void> signOut();

  /// google_sign_in on Android, iOS and macOS; browser loopback on Windows,
  /// which google_sign_in does not support.
  factory DriveAuth.forPlatform() =>
      Platform.isWindows ? DesktopDriveAuth() : MobileDriveAuth();
}

class MobileDriveAuth implements DriveAuth {
  /// The "Web application" OAuth client id; Android requires it as the server
  /// client id when no google-services.json is used.
  static const _serverClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  bool _initialized = false;

  @override
  Future<http.Client> signIn() async {
    final signIn = GoogleSignIn.instance;
    if (!_initialized) {
      await signIn.initialize(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _initialized = true;
    }
    final account =
        await signIn.attemptLightweightAuthentication() ??
        await signIn.authenticate(scopeHint: driveScopes);
    final headers = await account.authorizationClient.authorizationHeaders(
      driveScopes,
      promptIfNecessary: true,
    );
    return _HeaderClient(headers!);
  }

  @override
  Future<void> signOut() => GoogleSignIn.instance.signOut();
}

class DesktopDriveAuth implements DriveAuth {
  /// A "Desktop app" OAuth client from Google Cloud, passed at build time.
  static const _clientId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const _clientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
  );

  auth.AutoRefreshingAuthClient? _client;

  @override
  Future<http.Client> signIn() async {
    if (_clientId.isEmpty) {
      throw StateError(
        'Build with --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... (see README).',
      );
    }
    return _client ??= await auth.clientViaUserConsent(
      auth.ClientId(_clientId, _clientSecret),
      driveScopes,
      (url) => launchUrl(Uri.parse(url)),
    );
  }

  @override
  Future<void> signOut() async {
    _client?.close();
    _client = null;
  }
}

class _HeaderClient extends http.BaseClient {
  _HeaderClient(this._headers);

  final Map<String, String> _headers;
  final _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
