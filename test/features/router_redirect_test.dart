import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/auth/auth_controller.dart';
import 'package:mero_swasthya/router.dart';

/// Spec §10 — the role redirect.
///
/// The case that matters here is S18: a patient account taps "I am a health
/// worker" on S06 and has to reach `/provider/activate`. The redirect used to
/// bounce *every* `/provider*` location for a non-provider, so the one screen
/// that turns a patient into a provider was the one screen a patient could not
/// open — the tap pushed a second `/family` and nothing else happened. Found on
/// the phone during the QR round-trip.
void main() {
  User user(UserRole role) => User(
        id: 'u1',
        phone: '+9779801000001',
        role: role,
        name: 'Test',
        createdAt: '2026-09-18T00:00:00Z',
      );

  final signedOut = const AuthState();
  final locked = AuthState(user: user(UserRole.patient));
  final patient = AuthState(user: user(UserRole.patient), unlocked: true);
  final provider = AuthState(user: user(UserRole.provider), unlocked: true);
  final fchv = AuthState(user: user(UserRole.fchv), unlocked: true);

  group('S01', () {
    test('the splash is left alone to decide for itself', () {
      for (final auth in [signedOut, locked, patient, provider]) {
        expect(authRedirect(auth, '/'), isNull);
      }
    });
  });

  group('no session', () {
    test('every record screen sends you to S02', () {
      expect(authRedirect(signedOut, '/family'), '/auth/phone');
      expect(authRedirect(signedOut, '/patient/p1'), '/auth/phone');
      expect(authRedirect(signedOut, '/settings'), '/auth/phone');
      expect(authRedirect(signedOut, '/provider/activate'), '/auth/phone');
    });

    test('the auth screens are reachable', () {
      expect(authRedirect(signedOut, '/auth/phone'), isNull);
      expect(authRedirect(signedOut, '/auth/otp'), isNull);
      expect(authRedirect(signedOut, '/auth/set-pin'), isNull);
    });
  });

  group('a session that has not been unlocked this run', () {
    test('everything funnels to S04', () {
      expect(authRedirect(locked, '/family'), '/auth/pin');
      expect(authRedirect(locked, '/auth/phone'), '/auth/pin');
      expect(authRedirect(locked, '/provider/activate'), '/auth/pin');
    });

    test('except S04 itself', () {
      expect(authRedirect(locked, '/auth/pin'), isNull);
    });
  });

  group('signed in and unlocked', () {
    test('the auth screens hand you to your home by role', () {
      expect(authRedirect(patient, '/auth/pin'), '/family');
      expect(authRedirect(provider, '/auth/pin'), '/provider');
      expect(authRedirect(fchv, '/auth/otp'), '/provider');
    });

    test('a patient keeps their own screens', () {
      expect(authRedirect(patient, '/family'), isNull);
      expect(authRedirect(patient, '/patient/p1/timeline'), isNull);
      expect(authRedirect(patient, '/pregnancy/pr1'), isNull);
      expect(authRedirect(patient, '/settings'), isNull);
    });

    test('a patient is kept out of the provider screens', () {
      expect(authRedirect(patient, '/provider'), '/family');
      expect(authRedirect(patient, '/provider/scan'), '/family');
      expect(authRedirect(patient, '/provider/patient/p1'), '/family');
      expect(authRedirect(patient, '/provider/patient/p1/visit/new'), '/family');
    });

    test('but a patient may reach S18 to become one', () {
      expect(
        authRedirect(patient, '/provider/activate'),
        isNull,
        reason: 'S06 "I am a health worker" has to land somewhere',
      );
    });

    test('a health worker keeps both sides', () {
      for (final auth in [provider, fchv]) {
        expect(authRedirect(auth, '/provider'), isNull);
        expect(authRedirect(auth, '/provider/scan'), isNull);
        expect(authRedirect(auth, '/provider/activate'), isNull);
        expect(authRedirect(auth, '/family'), isNull);
        expect(authRedirect(auth, '/patient/p1'), isNull);
      }
    });
  });
}
