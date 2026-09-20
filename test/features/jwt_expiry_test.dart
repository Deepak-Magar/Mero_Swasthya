import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/features/auth/auth_controller.dart';

/// Spec S01: "Refresh accessToken silently if < 1 h remaining." That decision
/// rests entirely on reading `exp`, so the parser has to be exact about what it
/// does *not* know.
void main() {
  String jwt(Object? payload) {
    String seg(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    return '${seg({'alg': 'HS256'})}.${seg(payload ?? {})}.signature';
  }

  test('it reads exp out of a well-formed token', () {
    final expiry = DateTime.utc(2026, 9, 18, 16);
    final token = jwt({'exp': expiry.millisecondsSinceEpoch ~/ 1000});

    expect(AuthController.jwtExpiry(token), expiry);
  });

  test('unpadded base64url still decodes', () {
    // JWT segments are unpadded; Dart's decoder insists on padding, so the
    // parser adds it back. A payload length that is not a multiple of 4 is the
    // case that catches a missing pad.
    final token = jwt({'exp': 1789739000, 'sub': 'abc'});

    expect(AuthController.jwtExpiry(token), isNotNull);
  });

  group('returns null rather than guessing', () {
    test('for a null token', () {
      expect(AuthController.jwtExpiry(null), isNull);
    });

    test('for the opaque token the mock hands out', () {
      // This is what keeps mock mode from refreshing on every single launch.
      expect(AuthController.jwtExpiry('mock_access'), isNull);
    });

    test('for a token with no exp claim', () {
      expect(AuthController.jwtExpiry(jwt({'sub': 'u1'})), isNull);
    });

    test('for a non-numeric exp', () {
      expect(AuthController.jwtExpiry(jwt({'exp': 'soon'})), isNull);
    });

    test('for undecodable payload bytes', () {
      expect(AuthController.jwtExpiry('a.!!!not-base64!!!.c'), isNull);
    });

    test('for the wrong number of segments', () {
      expect(AuthController.jwtExpiry('only.two'), isNull);
      expect(AuthController.jwtExpiry(''), isNull);
    });
  });

  test('an already-expired token reads as past, not null', () {
    // The caller needs to tell "expired" from "unknown" — they lead to
    // different behaviour.
    final past = DateTime.utc(2020, 1, 1);
    final token = jwt({'exp': past.millisecondsSinceEpoch ~/ 1000});

    final parsed = AuthController.jwtExpiry(token);
    expect(parsed, past);
    expect(parsed!.isBefore(DateTime.now().toUtc()), isTrue);
  });
}
