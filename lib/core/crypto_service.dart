import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

/// A 256-bit AES key, transported as unpadded base64url.
class VaultKey {
  VaultKey(this.bytes) {
    if (bytes.length != CryptoService.keyLength) {
      throw FormatException(
        'Vault key must be ${CryptoService.keyLength} bytes (got ${bytes.length}).',
      );
    }
  }

  final Uint8List bytes;

  /// base64url without padding, so it survives being pasted into a URL.
  String get encoded => base64Url.encode(bytes).replaceAll('=', '');

  static VaultKey fromEncoded(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) throw const FormatException('The link has no key.');
    late Uint8List decoded;
    try {
      decoded = base64Url.decode(base64Url.normalize(trimmed));
    } on FormatException {
      throw const FormatException('The key in this link is not valid base64url.');
    }
    return VaultKey(decoded);
  }
}

/// The result of sealing a file: the blob that goes to the server and the key
/// that stays with the user.
class SealedFile {
  SealedFile({required this.key, required this.blob});

  final VaultKey key;

  /// `IV || ciphertext || GCM tag`
  final Uint8List blob;
}

/// AES-256-GCM, entirely on the device.
class CryptoService {
  CryptoService._();

  static const int keyLength = 32; // 256-bit
  static const int ivLength = 12; // GCM standard nonce length

  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int length) {
    final Uint8List out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }

  /// Encrypts [plain] with a fresh key and IV and prepends the IV to the blob.
  static SealedFile seal(Uint8List plain) {
    final VaultKey key = VaultKey(randomBytes(keyLength));
    final Uint8List iv = randomBytes(ivLength);
    final enc.Encrypter encrypter = enc.Encrypter(
      enc.AES(enc.Key(key.bytes), mode: enc.AESMode.gcm),
    );
    final enc.Encrypted sealed = encrypter.encryptBytes(plain, iv: enc.IV(iv));

    final Uint8List blob = Uint8List(ivLength + sealed.bytes.length);
    blob.setRange(0, ivLength, iv);
    blob.setRange(ivLength, blob.length, sealed.bytes);
    return SealedFile(key: key, blob: blob);
  }

  /// Reverses [seal]: strips the leading 12-byte IV and authenticates/decrypts
  /// the remainder. Throws when the tag does not verify (wrong key or tampering).
  static Uint8List open(Uint8List blob, VaultKey key) {
    if (blob.length <= ivLength) {
      throw const FormatException('The downloaded blob is too short to be valid.');
    }
    final Uint8List iv = Uint8List.sublistView(blob, 0, ivLength);
    final Uint8List ciphertext = Uint8List.sublistView(blob, ivLength);
    final enc.Encrypter encrypter = enc.Encrypter(
      enc.AES(enc.Key(key.bytes), mode: enc.AESMode.gcm),
    );
    try {
      return Uint8List.fromList(
        encrypter.decryptBytes(enc.Encrypted(ciphertext), iv: enc.IV(iv)),
      );
    } catch (_) {
      throw const FormatException(
        'Decryption failed: the key is wrong or the file was tampered with.',
      );
    }
  }
}
