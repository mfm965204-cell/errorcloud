import 'package:errorcloud/core/config.dart';
import 'package:errorcloud/core/crypto_service.dart';

/// A shareable vault link: `vault://<ID>?key=<BASE64URL_KEY>&n=<filename>`
class VaultLink {
  const VaultLink({required this.fileId, required this.key, this.fileName});

  final String fileId;
  final VaultKey key;
  final String? fileName;

  String encode() {
    final Map<String, String> params = <String, String>{'key': key.encoded};
    if (fileName != null && fileName!.isNotEmpty) {
      params['n'] = fileName!;
    }
    return Uri(
      scheme: AppConfig.linkScheme,
      host: fileId,
      queryParameters: params,
    ).toString();
  }

  static final RegExp _idPattern = RegExp(r'^[A-Z2-9]{6}$');

  static VaultLink parse(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('Paste a vault link first.');
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      throw const FormatException('That is not a valid link.');
    }
    if (!AppConfig.acceptedSchemes.contains(uri.scheme.toLowerCase())) {
      throw const FormatException(
        'A vault link starts with ${AppConfig.linkScheme}://',
      );
    }

    String id = uri.host;
    if (id.isEmpty && uri.pathSegments.isNotEmpty) id = uri.pathSegments.first;
    id = id.toUpperCase();
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('The link does not contain a valid 6-character file ID.');
    }

    final String? key = uri.queryParameters['key'];
    if (key == null || key.isEmpty) {
      throw const FormatException('The link is missing its decryption key.');
    }

    return VaultLink(
      fileId: id,
      key: VaultKey.fromEncoded(key),
      fileName: uri.queryParameters['n'],
    );
  }
}
