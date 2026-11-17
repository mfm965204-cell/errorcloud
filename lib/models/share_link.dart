import 'dart:convert';

/// A parsed `errorcloud://<ID>?key=<KEY>&name=<FILENAME>` link.
///
/// The key and the (optional) original file name live only inside the link, so
/// the server never learns either of them.
class ShareLink {
  const ShareLink({
    required this.fileId,
    required this.keyBase64,
    this.fileName,
  });

  final String fileId;
  final String keyBase64;
  final String? fileName;

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9]{6}$');

  /// Builds the shareable string.
  static String build({
    required String fileId,
    required String keyBase64,
    String? fileName,
  }) {
    final query = <String, String>{'key': keyBase64};
    final safeName = _sanitise(fileName);
    if (safeName.isNotEmpty) {
      query['name'] = base64Url.encode(utf8.encode(safeName)).replaceAll('=', '');
    }
    return Uri(scheme: 'errorcloud', host: fileId, queryParameters: query).toString();
  }

  /// Parses user input. Accepts the full link, `ID?key=...`, or `ID KEY`.
  /// Returns null when the text cannot be understood.
  static ShareLink? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    var candidate = text;
    if (!candidate.contains('://')) {
      final parts = candidate.split(RegExp(r'\s+'));
      candidate = parts.length == 2
          ? 'errorcloud://${parts[0]}?key=${parts[1]}'
          : 'errorcloud://$candidate';
    }

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (uri.scheme.toLowerCase() != 'errorcloud') return null;

    final fileId = uri.host.isNotEmpty
        ? uri.host
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
    final key = uri.queryParameters['key'] ?? '';

    if (!_idPattern.hasMatch(fileId)) return null;
    if (key.isEmpty) return null;

    return ShareLink(
      fileId: fileId.toUpperCase(),
      keyBase64: key,
      fileName: _decodeName(uri.queryParameters['name']),
    );
  }

  static String _decodeName(String? encoded) {
    if (encoded == null || encoded.isEmpty) return '';
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } catch (_) {
      return '';
    }
  }

  static String _sanitise(String? name) {
    if (name == null) return '';
    var out = name.trim().replaceAll(RegExp(r'[\\/]'), '_');
    out = out.replaceAll('..', '_');
    if (out.length > 120) {
      out = out.substring(out.length - 120);
    }
    return out;
  }
}
