/// Static build configuration for Errorcloud.
class AppConfig {
  AppConfig._();

  static const String appName = 'Errorcloud';
  static const String version = '1.0.0';
  static const String build = '1';

  /// The app's internal signature. Kept in one place so the splash and the
  /// About screen can never drift apart.
  static const String signature = 'Developed by Error';

  /// Blind-storage backend. Override at build time with
  /// `--dart-define=WORKER_BASE_URL=https://...`
  static const String workerBaseUrl = String.fromEnvironment(
    'WORKER_BASE_URL',
    defaultValue: 'https://errorcloud-api.mfm965204.workers.dev',
  );

  /// Scheme used for shareable links, e.g. `vault://ID?key=BASE64URL_KEY`.
  static const String linkScheme = 'vault';

  /// Schemes accepted when pasting a link (the app also answers to its own name).
  static const List<String> acceptedSchemes = <String>['vault', 'errorcloud'];

  static Uri get healthUri => Uri.parse('$workerBaseUrl/health');
  static Uri get uploadUri => Uri.parse('$workerBaseUrl/upload');
  static Uri downloadUri(String id) => Uri.parse('$workerBaseUrl/download/$id');
}
