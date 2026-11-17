import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Raised for any transport or protocol failure.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin client for the Errorcloud Worker.
///
/// Transport hardening (replaces certificate pinning, which is unsafe against
/// Cloudflare's rotating managed certificates):
///  * the scheme must be https,
///  * the host must match [AppConfig.apiBaseUrl] exactly,
///  * cleartext traffic is disabled in the Android manifest,
///  * payloads are already sealed before they reach this layer.
class ApiClient {
  ApiClient._();

  static final Uri _base = Uri.parse(AppConfig.apiBaseUrl);

  static Uri _guard(String path) {
    final uri = _base.resolve(path);
    if (uri.scheme != 'https') {
      throw const ApiException('Refusing to send data over an insecure connection.');
    }
    if (uri.host != _base.host) {
      throw const ApiException('Unexpected server host. Request blocked.');
    }
    return uri;
  }

  /// Uploads a sealed blob and returns the 6-character file id.
  static Future<String> upload(Uint8List sealedBytes) async {
    if (sealedBytes.isEmpty) {
      throw const ApiException('Nothing to upload.');
    }
    if (sealedBytes.length > AppConfig.maxTransferBytes) {
      throw const ApiException('That file is larger than the 24 MB limit.');
    }

    final uri = _guard('/upload');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/octet-stream'},
            body: sealedBytes,
          )
          .timeout(AppConfig.requestTimeout);
    } catch (_) {
      throw const ApiException('Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 413) {
      throw const ApiException('That file is larger than the 24 MB limit.');
    }
    if (response.statusCode != 200) {
      throw ApiException('Upload failed (HTTP ${response.statusCode}).');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ApiException('The server returned an unexpected response.');
    }

    final id = body['id'];
    if (id is! String || id.isEmpty) {
      throw const ApiException('The server did not return a file id.');
    }
    return id;
  }

  /// Downloads a sealed blob by id.
  static Future<Uint8List> download(String fileId) async {
    final uri = _guard('/download/$fileId');
    http.Response response;
    try {
      response = await http.get(uri).timeout(AppConfig.requestTimeout);
    } catch (_) {
      throw const ApiException('Could not reach the server. Check your connection.');
    }

    if (response.statusCode == 404) {
      throw const ApiException('No file with that id. It may have been deleted.');
    }
    if (response.statusCode != 200) {
      throw ApiException('Download failed (HTTP ${response.statusCode}).');
    }
    if (response.bodyBytes.isEmpty) {
      throw const ApiException('The server returned an empty file.');
    }
    return response.bodyBytes;
  }
}
