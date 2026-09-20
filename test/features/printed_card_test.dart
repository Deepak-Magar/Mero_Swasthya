import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/patient_home/printed_card_screen.dart';
import 'package:mero_swasthya/features/provider/provider_patient_screen.dart';

import 'harness.dart';

/// Spec A.7 — the printed fallback card.
///
/// The card is only safe because the PIN gate holds and because whoever redeems
/// it cannot write. Both halves are tested here; the mock's rule is tested
/// first, because everything above it trusts the refusal to arrive.
void main() {
  late DateTime now;
  late MockApi mock;
  late Api api;

  setUp(() {
    now = DateTime.utc(2026, 9, 18, 5);
    mock = MockApi(clock: () => now);
    api = Api(mock);
  });

  group('the mock rule', () {
    test('a year-long grant is marked long-lived; a ten-minute one is not',
        () async {
      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );
      expect(card.grant.longLived, isTrue);
      expect(card.grant.scope, GrantScope.read);
      expect(card.qrPayload, startsWith(MockApi.qrPrefix));

      final live = await api.grants.create(patientId: MockApi.sitaId);
      expect(live.grant.longLived, isFalse);
    });

    test('a long-lived grant refuses a redeem that carries no PIN', () async {
      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );

      await expectLater(
        api.grants.redeem(card.qrPayload),
        throwsA(
          isA<AppError>()
              .having((e) => e.httpStatus, 'status', 403)
              .having((e) => e.code, 'code', AppError.forbidden)
              .having((e) => e.details?['pin'], 'details.pin', 'required'),
        ),
      );
    });

    test('a wrong PIN is a 403 the app can tell apart from a challenge',
        () async {
      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );

      await expectLater(
        api.grants.redeem(card.qrPayload, pin: '9999'),
        throwsA(
          isA<AppError>()
              .having((e) => e.httpStatus, 'status', 403)
              .having((e) => e.details?['pin'], 'details.pin', 'invalid'),
        ),
      );
    });

    test('the right PIN redeems and returns the whole bundle', () async {
      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );

      final result = await api.grants.redeem(
        card.qrPayload,
        pin: MockApi.demoPatientPin,
      );

      expect(result.patient.id, MockApi.sitaId);
      expect(result.patient.allergies, contains('sulpha'));
      expect(result.grant.scope, GrantScope.read);
      expect(result.grant.longLived, isTrue);
      expect(result.pregnancy, isNotNull);
    });

    test('the PIN checked is the one this account actually set', () async {
      await api.auth.setPin(
        tempToken: 'mock_temp',
        pin: '4321',
        name: 'Sita Chaudhary',
      );

      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );

      await expectLater(
        api.grants.redeem(card.qrPayload, pin: MockApi.demoPatientPin),
        throwsA(isA<AppError>()),
      );
      final result = await api.grants.redeem(card.qrPayload, pin: '4321');
      expect(result.patient.id, MockApi.sitaId);
    });

    test('the ordinary ten-minute grant still redeems with no PIN at all',
        () async {
      final live = await api.grants.create(patientId: MockApi.sitaId);
      final result = await api.grants.redeem(live.qrPayload);
      expect(result.patient.id, MockApi.sitaId);
      expect(result.grant.longLived, isFalse);
    });

    test('a long-lived grant that has been revoked is refused before the PIN is',
        () async {
      final card = await api.grants.create(
        patientId: MockApi.sitaId,
        scope: GrantScope.read,
        ttlMinutes: GrantsApi.printedCardTtlMinutes,
      );
      await api.grants.revoke(card.grant.id);

      await expectLater(
        api.grants.redeem(card.qrPayload, pin: MockApi.demoPatientPin),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppError.grantExpired),
        ),
      );
    });
  });

  group('the client-side classification', () {
    test('tells a challenge from a rejection from an unrelated 403', () {
      const challenge = AppError(
        code: AppError.forbidden,
        message: 'needs a PIN',
        details: {'pin': 'required'},
        httpStatus: 403,
      );
      const rejected = AppError(
        code: AppError.forbidden,
        message: 'wrong',
        details: {'pin': 'invalid'},
        httpStatus: 403,
      );
      const plain = AppError(
        code: AppError.forbidden,
        message: 'not your patient',
        httpStatus: 403,
      );

      expect(GrantsApi.isPinChallenge(challenge), isTrue);
      expect(GrantsApi.isPinRejected(challenge), isFalse);

      expect(GrantsApi.isPinRejected(rejected), isTrue);
      expect(GrantsApi.isPinChallenge(rejected), isFalse);

      expect(GrantsApi.isPinChallenge(plain), isFalse);
      expect(GrantsApi.isPinRejected(plain), isFalse);
      expect(GrantsApi.isPinChallenge(AppError.networkError()), isFalse);
    });
  });

  group('the card itself', () {
    testWidgets('carries the name, blood group, QR and the PIN sentence in '
        'both languages', (tester) async {
      const patient = Patient(
        id: MockApi.sitaId,
        ownerUserId: 'u_0001',
        name: 'Sita Chaudhary',
        sex: Sex.female,
        dob: '2002-04-11',
        bloodGroup: 'B+',
      );

      await tester.pumpWidget(
        wrapForTest(
          const Center(
            child: PrintedCard(
              patient: patient,
              qrPayload: 'SWC1:mock_grant_test',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sita Chaudhary'), findsOneWidget);
      expect(find.textContaining('B+'), findsOneWidget);

      // The sentence that makes the card safe is on every copy, in both
      // languages, whichever one the app happens to be in.
      expect(find.text(askForPinNp), findsOneWidget);
      expect(find.text(askForPinEn), findsOneWidget);
    });
  });

  group('S21 under a read-only grant', () {
    const patient = Patient(
      id: 'p_readonly',
      ownerUserId: 'u_other',
      name: 'Sita Chaudhary',
      sex: Sex.female,
      dob: '2002-04-11',
      bloodGroup: 'B+',
      allergies: ['sulpha'],
    );

    testWidgets('hides Add visit and Register pregnancy and says why',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.patientsDao.upsert(patient);
      await db.syncMetaDao.setReadOnlyAccess(patient.id, value: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            // The screen reaches the API through the repository; the mock keeps
            // it away from shared_preferences and secure storage, neither of
            // which has a platform channel in a widget test.
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const ProviderPatientScreen(patientId: 'p_readonly'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Read-only access'), findsOneWidget);
      expect(find.text('Add visit'), findsNothing);
      expect(find.text('Register pregnancy'), findsNothing);
      // The record itself is still fully readable — that is the point of it.
      expect(find.text('Sita Chaudhary'), findsWidgets);
      expect(find.textContaining('sulpha'), findsOneWidget);

      // Unmount inside the test: disposing drift's stream store schedules a
      // zero-duration timer, and a test that ends before it fires is reported
      // as a leak rather than a pass.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('an ordinary append grant keeps the write actions',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.patientsDao.upsert(patient);
      await db.syncMetaDao.setReadOnlyAccess(patient.id, value: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            // The screen reaches the API through the repository; the mock keeps
            // it away from shared_preferences and secure storage, neither of
            // which has a platform channel in a widget test.
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const ProviderPatientScreen(patientId: 'p_readonly'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Read-only access'), findsNothing);
      expect(find.text('Add visit'), findsOneWidget);
      expect(find.text('Register pregnancy'), findsOneWidget);

      // Unmount inside the test: disposing drift's stream store schedules a
      // zero-duration timer, and a test that ends before it fires is reported
      // as a leak rather than a pass.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
