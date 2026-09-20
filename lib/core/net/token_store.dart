import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/key_derivation.dart';

/// Everything that must survive a restart but must never reach the database
/// (spec §3: "Secure storage — tokens, PIN hash, DB key").
///
/// The tokens live here rather than in `sync_meta` for a plain reason: the
/// database is the thing the PIN is supposed to protect, so the credential that
/// unlocks a session cannot sit inside it.
abstract interface class TokenStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> clear();

  /// Per-device salt for [KeyDerivation], created on first use.
  Future<Uint8List> salt();

  /// Lets S04 check a PIN with no network (spec §6.1).
  Future<void> savePinVerifier(String pin);
  Future<bool> verifyPin(String pin);
  Future<bool> hasPin();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _saltKey = 'device_salt';
  static const String _pinVerifierKey = 'pin_verifier';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> accessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> refreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  /// Signing out drops the tokens but keeps the salt, so a PIN the user sets
  /// again derives the same database key.
  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _pinVerifierKey);
  }

  @override
  Future<Uint8List> salt() async {
    final existing = await _storage.read(key: _saltKey);
    if (existing != null) return base64Decode(existing);

    final generated = KeyDerivation.newSalt();
    await _storage.write(key: _saltKey, value: base64Encode(generated));
    return generated;
  }

  @override
  Future<void> savePinVerifier(String pin) async {
    await _storage.write(
      key: _pinVerifierKey,
      value: KeyDerivation.derivePinVerifier(pin, await salt()),
    );
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final expected = await _storage.read(key: _pinVerifierKey);
    if (expected == null) return false;
    return KeyDerivation.verifyPin(pin, await salt(), expected);
  }

  @override
  Future<bool> hasPin() async =>
      await _storage.read(key: _pinVerifierKey) != null;
}

/// In-memory stand-in for tests and for `MOCK_API=true`, where there is no
/// platform channel to talk to.
class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;
  String? _pinVerifier;
  Uint8List? _salt;

  @override
  Future<String?> accessToken() async => _access;

  @override
  Future<String?> refreshToken() async => _refresh;

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _pinVerifier = null;
  }

  @override
  Future<Uint8List> salt() async => _salt ??= KeyDerivation.newSalt();

  @override
  Future<void> savePinVerifier(String pin) async {
    _pinVerifier = KeyDerivation.derivePinVerifier(pin, await salt());
  }

  @override
  Future<bool> verifyPin(String pin) async {
    final expected = _pinVerifier;
    if (expected == null) return false;
    return KeyDerivation.verifyPin(pin, await salt(), expected);
  }

  @override
  Future<bool> hasPin() async => _pinVerifier != null;
}
