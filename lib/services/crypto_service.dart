import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Thrown when a payload cannot be sealed or opened.
class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Result of sealing a file: the bytes that go to the server, plus the key
/// that must never leave the device.
class SealedPayload {
  const SealedPayload({required this.bytes, required this.keyBase64});

  /// `nonce (12 bytes) || ciphertext || GCM tag (16 bytes)`.
  final Uint8List bytes;

  /// Base64Url (unpadded) 256-bit key.
  final String keyBase64;
}

/// AES-256-GCM file encryption.
///
/// The key is generated with `Random.secure()` on the device and is only ever
/// embedded in the share link the user copies. The Worker therefore stores a
/// blob it cannot read: this is the zero-knowledge property.
class CryptoService {
  CryptoService._();

  static const int keyLength = 32; // 256-bit
  static const int nonceLength = 12; // 96-bit GCM nonce
  static const int tagLength = 16; // 128-bit authentication tag

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = random.nextInt(256);
    }
    return out;
  }

  /// Encrypts [plaintext] and prepends the random nonce to the ciphertext.
  static SealedPayload seal(Uint8List plaintext) {
    final key = _randomBytes(keyLength);
    final nonce = _randomBytes(nonceLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final sealedBody = cipher.process(plaintext);
    final out = Uint8List(nonceLength + sealedBody.length)
      ..setRange(0, nonceLength, nonce)
      ..setRange(nonceLength, nonceLength + sealedBody.length, sealedBody);

    return SealedPayload(bytes: out, keyBase64: _encodeKey(key));
  }

  /// Decrypts a blob produced by [seal].
  ///
  /// Throws [VaultException] when the key is the wrong shape, when the tag does
  /// not verify (wrong key or tampered data), or when the blob is truncated.
  static Uint8List open(Uint8List payload, String keyBase64) {
    if (payload.length < nonceLength + tagLength) {
      throw const VaultException('This file is truncated or not an Errorcloud file.');
    }

    final Uint8List key;
    try {
      key = _decodeKey(keyBase64);
    } catch (_) {
      throw const VaultException('The key in this link is not valid base64.');
    }
    if (key.length != keyLength) {
      throw const VaultException('The key in this link is the wrong length.');
    }

    final nonce = payload.sublist(0, nonceLength);
    final sealedBody = payload.sublist(nonceLength);

    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
      return cipher.process(sealedBody);
    } catch (_) {
      throw const VaultException('Wrong key, or the file was modified in transit.');
    }
  }

  static String _encodeKey(Uint8List key) =>
      base64Url.encode(key).replaceAll('=', '');

  static Uint8List _decodeKey(String encoded) =>
      base64Url.decode(base64Url.normalize(encoded.trim()));
}
