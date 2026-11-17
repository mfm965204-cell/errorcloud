import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:errorcloud/core/config.dart';
import 'package:errorcloud/core/ssl_pinning.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class VaultApiException implements Exception {
  VaultApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to the Cloudflare Worker. Every request goes through the pinned
/// [HttpClient], and the certificate is verified before the first byte is sent.
class VaultApi {
  factory VaultApi({HttpClient? client}) {
    final HttpClient shared = client ?? SslPinning.newClient();
    return VaultApi._(shared, IOClient(shared));
  }

  VaultApi._(this._client, this._http);

  final HttpClient _client;
  final IOClient _http;
  bool _verified = false;

  Future<void> _ensurePinned() async {
    if (_verified) return;
    await SslPinning.assertEndpointPinned(_client, AppConfig.healthUri);
    _verified = true;
  }

  /// Uploads an already-encrypted blob and returns the 6-character file ID.
  Future<String> upload(Uint8List blob) async {
    await _ensurePinned();
    final http.Response response = await _http
        .post(
          AppConfig.uploadUri,
          headers: const <String, String>{'Content-Type': 'application/octet-stream'},
          body: blob,
        )
        .timeout(const Duration(minutes: 10));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw VaultApiException(
        'Upload failed (HTTP ${response.statusCode}): ${_message(response.body)}',
      );
    }
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['id'] is! String) {
      throw VaultApiException('The server did not return a file ID.');
    }
    return decoded['id'] as String;
  }

  /// Fetches the encrypted blob for [fileId].
  Future<Uint8List> download(String fileId) async {
    await _ensurePinned();
    final http.Response response = await _http
        .get(AppConfig.downloadUri(fileId))
        .timeout(const Duration(minutes: 10));

    if (response.statusCode == 404) {
      throw VaultApiException('Nothing is stored under ID $fileId.');
    }
    if (response.statusCode != 200) {
      throw VaultApiException('Download failed (HTTP ${response.statusCode}).');
    }
    if (response.bodyBytes.isEmpty) {
      throw VaultApiException('The server returned an empty file.');
    }
    return response.bodyBytes;
  }

  String _message(String body) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) return decoded['error'].toString();
    } catch (_) {
      // fall through
    }
    return body.isEmpty ? 'no details' : body;
  }

  void close() => _http.close();
}
