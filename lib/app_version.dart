/// Build identity shown on the home screen so Tom can see what is live.
///
/// [kAppVersion] must stay in sync with `pubspec.yaml` `version:`.
/// [kGitSha] is injected at web release build via
/// `--dart-define=GIT_SHA=$(git rev-parse --short HEAD)`.
const String kAppVersion = '1.1.0+2';
const String kGitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');

String get kBuildLabel => 'v$kAppVersion · $kGitSha';
