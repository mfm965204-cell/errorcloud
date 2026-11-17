/// Central configuration for Errorcloud.
class AppConfig {
  AppConfig._();

  static const String appName = 'Errorcloud';
  static const String appVersion = '1.0.0';
  static const String developerLine = 'Developed by Error';

  /// Locked-down API base URL.
  ///
  /// Every request is validated against this host and the `https` scheme
  /// before any bytes leave the device (see `ApiClient._guard`). Certificate
  /// pinning was intentionally left out: Cloudflare rotates the managed
  /// certificate for `*.workers.dev`, so a pinned fingerprint would hard-fail
  /// the app on the first rotation. Transport security relies on TLS plus the
  /// host lock below, and payloads are encrypted before they are uploaded.
  static const String apiBaseUrl = 'https://errorcloud-api.mfm965204.workers.dev';

  /// Upper bound for a single transfer. Workers KV caps a value at 25 MiB, so
  /// the Worker accepts 24 MiB and the app checks the same number first.
  static const int maxTransferBytes = 24 * 1024 * 1024;

  static const Duration requestTimeout = Duration(minutes: 5);
}
