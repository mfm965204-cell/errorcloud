import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Thrown when the TLS certificate presented by the backend is not one of the
/// certificates this build was pinned to.
class PinningException implements Exception {
  PinningException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Certificate (public-key) pinning for the Errorcloud backend.
///
/// Pins are `base64(SHA-256(DER leaf certificate))`, the same value produced by
///
///     openssl s_client -connect <host>:443 -servername <host> </dev/null \
///       | openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
///
/// Two layers of defence are applied:
///
///  1. `badCertificateCallback` — a chain that does not validate (self-signed,
///     unknown CA, hostname mismatch) is only accepted when the leaf
///     certificate matches a pin.
///  2. [assertEndpointPinned] — a real handshake against `/health` whose leaf
///     certificate fingerprint must match a pin *before* any file bytes are
///     sent. This closes the gap where a MITM presents a perfectly valid
///     certificate from a public CA: dart:io never calls the callback in that
///     case, so the fingerprint is checked explicitly.
class SslPinning {
  SslPinning._();

  /// Pins committed to the repository. Regenerate with the
  /// `Fetch SSL pin` workflow (.github/workflows/fetch-ssl-pin.yml).
  static const List<String> committedPins = <String>[
    'sQd0bm2o0a0ivRNjJWxv84EZHwT26VjYJs5+L56hSNU=',
  ];

  /// Extra pin injected at build time: `--dart-define=SSL_PIN=<base64>`.
  /// The CI build resolves the live certificate and passes it here, so a
  /// certificate rotation cannot brick a fresh build.
  static const String _buildPin = String.fromEnvironment('SSL_PIN');

  static List<String> get pins => <String>[
        ...committedPins.where((String p) => p.trim().isNotEmpty),
        if (_buildPin.trim().isNotEmpty) _buildPin.trim(),
      ];

  static bool get isConfigured => pins.isNotEmpty;

  /// `base64(SHA-256(DER))` for a certificate.
  static String fingerprintOf(X509Certificate cert) =>
      base64.encode(sha256.convert(cert.der).bytes);

  /// True when [cert] matches one of the configured pins.
  static bool matches(X509Certificate? cert) {
    if (cert == null) return false;
    final String fingerprint = fingerprintOf(cert);
    for (final String pin in pins) {
      if (_constantTimeEquals(pin, fingerprint)) return true;
    }
    return false;
  }

  /// An [HttpClient] that refuses to talk to anything but the pinned backend.
  static HttpClient newClient() {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => matches(cert);
    return client;
  }

  /// Performs a handshake against [uri] and verifies the leaf certificate
  /// against the pin set. Throws [PinningException] on any mismatch.
  static Future<void> assertEndpointPinned(HttpClient client, Uri uri) async {
    if (!isConfigured) {
      throw PinningException(
        'No SSL pins are configured in this build, so the connection was '
        'refused. Add the backend certificate fingerprint to '
        'lib/core/ssl_pinning.dart or build with --dart-define=SSL_PIN=...',
      );
    }
    final HttpClientRequest request = await client.getUrl(uri);
    request.followRedirects = false;
    final HttpClientResponse response = await request.close();
    final X509Certificate? cert = response.certificate;
    await response.drain();
    if (cert == null) {
      throw PinningException('The server presented no certificate for ${uri.host}.');
    }
    if (!matches(cert)) {
      throw PinningException(
        'Certificate pin mismatch for ${uri.host}. '
        'Observed fingerprint: ${fingerprintOf(cert)}. '
        'The connection was aborted and nothing was sent.',
      );
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
