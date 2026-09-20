import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 key derivation.
///
/// Spec §6.1: open the database with a 32-byte key derived from the PIN using
/// PBKDF2-HMAC-SHA256, 100 000 iterations, with a per-device salt held in
/// secure storage. Session 1 ships the database UNENCRYPTED (plain
/// sqlite3_flutter_libs) — the spec explicitly allows this fallback — but the
/// derivation lives here so switching to sqlcipher_flutter_libs later is a
/// one-line change at the database open site.
///
/// The same derivation also produces the locally stored PIN verifier used by
/// S04 for offline unlock.
class KeyDerivation {
  const KeyDerivation._();

  static const int iterations = 100000;
  static const int keyLengthBytes = 32;
  static const int saltLengthBytes = 16;

  /// Derives the 32-byte database key from [pin] and [salt].
  static Uint8List deriveDbKey(String pin, Uint8List salt) =>
      pbkdf2(utf8.encode(pin), salt, iterations, keyLengthBytes);

  /// Hex form, which is what SQLCipher's `PRAGMA key = "x'...'"` expects.
  static String deriveDbKeyHex(String pin, Uint8List salt) =>
      _toHex(deriveDbKey(pin, salt));

  /// Verifier stored in secure storage so S04 can check a PIN with no network.
  /// A different iteration count from the DB key keeps the two values unequal
  /// even though they share a salt.
  static String derivePinVerifier(String pin, Uint8List salt) =>
      _toHex(pbkdf2(utf8.encode('pin:$pin'), salt, iterations, keyLengthBytes));

  /// Constant-time comparison so a wrong PIN cannot be found by timing.
  static bool verifyPin(String pin, Uint8List salt, String expectedVerifier) {
    final actual = derivePinVerifier(pin, salt);
    if (actual.length != expectedVerifier.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedVerifier.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Uint8List newSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(saltLengthBytes, (_) => rng.nextInt(256)),
    );
  }

  static String saltToBase64(Uint8List salt) => base64Encode(salt);

  static Uint8List saltFromBase64(String encoded) =>
      Uint8List.fromList(base64Decode(encoded));

  /// RFC 8018 PBKDF2 with HMAC-SHA256.
  static Uint8List pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, password);
    const hashLength = 32;
    final blockCount = (keyLength + hashLength - 1) ~/ hashLength;
    final output = Uint8List(blockCount * hashLength);

    for (var block = 1; block <= blockCount; block++) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      final blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      var u = Uint8List.fromList(hmac.convert([...salt, ...blockIndex]).bytes);
      final accumulator = Uint8List.fromList(u);

      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < hashLength; j++) {
          accumulator[j] ^= u[j];
        }
      }
      output.setRange((block - 1) * hashLength, block * hashLength, accumulator);
    }
    return Uint8List.sublistView(output, 0, keyLength);
  }

  static String _toHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
