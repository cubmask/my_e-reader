/// The Web application OAuth client id of this app's Google Cloud project.
/// A client id is not a secret (every installed app carries it), so it lives
/// here and a plain `flutter run` can sign in. Building with
/// `--dart-define=GOOGLE_WEB_CLIENT_ID=...` points the app at another project.
const googleWebClientId = _override == '' ? _webClientId : _override;

const _webClientId =
    '52226296797-vs9gloom36eg8j1rak0nuk7s3culnuh3.apps.googleusercontent.com';

// An empty value, as CI passes when its variable is unset, keeps the default.
const _override = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
