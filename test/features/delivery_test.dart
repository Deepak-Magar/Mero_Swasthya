import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/repositories/pregnancy_repo.dart';
import 'package:mero_swasthya/data/repositories/sync_kicker.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/delivery_complications.dart';
import 'package:mero_swasthya/features/family/family_screen.dart';
import 'package:mero_swasthya/features/maternal/pregnancy_dashboard_screen.dart';
import 'package:mero_swasthya/features/patient_home/patient_home_screen.dart';

import 'harness.dart';

/// S14 — the delivery record, and the two places the rest of the app has to
/// notice that a pregnancy has ended.
class _NoopKicker implements SyncKicker {
  int kicks = 0;

  @override
  void kick() => kicks++;
}

void main() {
  const patientId = 'p_delivery';
  const pregnancyId = 'pg_delivery';

  Pregnancy pregnancy({
    PregnancyStatus status = PregnancyStatus.active,
    int version = 1,
  }) {
    return Pregnancy(
      id: pregnancyId,
      patientId: patientId,
      edd: '2026-11-25',
      status: status,
      version: version,
    );
  }

  Delivery delivery({List<String> complications = const []}) {
    return Delivery(
      id: 'dl_0001',
      pregnancyId: pregnancyId,
      deliveredAt: '2026-11-25T02:00:00.000Z',
      place: DeliveryPlace.hospital,
      mode: DeliveryMode.normal,
      outcome: DeliveryOutcome.liveBirth,
      babyWeightKg: 2.9,
      babySex: Sex.female,
      complications: complications,
    );
  }

  group('the repository write', () {
    late AppDatabase db;
    late _NoopKicker kicker;
    late PregnancyRepo repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      kicker = _NoopKicker();
      repo = PregnancyRepo(db, kicker);
      await db.pregnanciesDao.upsertPregnancy(pregnancy());
    });

    tearDown(() => db.close());

    test('writes the delivery, closes the pregnancy and queues both', () async {
      await repo.recordDelivery(
        delivery(complications: const ['PPH']),
        pregnancy(status: PregnancyStatus.delivered),
      );

      final stored = await db.pregnanciesDao.findDelivery('dl_0001');
      expect(stored, isNotNull);
      expect(stored!.complications, ['PPH']);
      expect(stored.babyWeightKg, 2.9);

      final closed = await db.pregnanciesDao.findById(pregnancyId);
      expect(closed!.status, PregnancyStatus.delivered);

      // Spec S14: both rows or neither. The delivery has to be pushed before
      // the row that says the pregnancy it belongs to is over.
      final ops = await db.outboxDao.take();
      expect(ops.map((o) => o.targetTable).toList(), [
        SyncTables.deliveries,
        SyncTables.pregnancies,
      ]);
      expect(ops.first.baseVersion, 0, reason: 'a delivery is a create');
      expect(
        ops.last.baseVersion,
        1,
        reason: "the pregnancy's local version, not the one passed in",
      );
      expect(kicker.kicks, 1);
    });

    test('a weight the stepper produced is stored rounded', () async {
      // 0.1 thirty-four times is 3.4000000000000004 in binary floating point.
      var weight = 0.0;
      for (var i = 0; i < 34; i++) {
        weight += 0.1;
      }
      expect(weight, isNot(3.4), reason: 'the premise of the rounding');

      await repo.recordDelivery(
        delivery().copyWith(
          babyWeightKg: double.parse(weight.toStringAsFixed(1)),
        ),
        pregnancy(status: PregnancyStatus.delivered),
      );

      final stored = await db.pregnanciesDao.findDelivery('dl_0001');
      expect(stored!.babyWeightKg, 3.4);
    });

    test('the latest-pregnancy stream keeps reporting a closed pregnancy',
        () async {
      // S06 keys its badge off this. Watching only active pregnancies made the
      // badge vanish the moment a delivery was recorded.
      await repo.recordDelivery(
        delivery(),
        pregnancy(status: PregnancyStatus.delivered),
      );

      expect(await repo.watchActiveForPatient(patientId).first, isNull);
      final latest = await repo.watchLatestForPatient(patientId).first;
      expect(latest, isNotNull);
      expect(latest!.status, PregnancyStatus.delivered);
    });

    test('the bundle carries the delivery so S12 can render it', () async {
      await repo.recordDelivery(
        delivery(complications: const ['PPH', 'RETAINED_PLACENTA']),
        pregnancy(status: PregnancyStatus.delivered),
      );

      final bundle = await repo
          .watchBundle(pregnancyId)
          .firstWhere((b) => b.delivery != null);
      expect(bundle.pregnancy.status, PregnancyStatus.delivered);
      expect(bundle.delivery!.complications, hasLength(2));
    });
  });

  group('the mock endpoint', () {
    late MockApi mock;
    late Api api;

    setUp(() {
      mock = MockApi(clock: () => DateTime.utc(2026, 9, 18, 5));
      api = Api(mock);
    });

    test('POST /pregnancies/:id/delivery answers with both rows, A.4 shapes',
        () async {
      final result = await api.pregnancies.recordDelivery(
        MockApi.pregnancyId,
        const {
          'id': 'dl_mock',
          'deliveredAt': '2026-11-25T02:00:00.000Z',
          'place': 'birthing_centre',
          'mode': 'normal',
          'outcome': 'live_birth',
          'babyWeightKg': 3.1,
          'babySex': 'male',
          'complications': <String>['PPH'],
        },
      );

      expect(result.delivery.id, 'dl_mock');
      expect(result.delivery.place, DeliveryPlace.birthingCentre);
      expect(result.delivery.complications, ['PPH']);
      expect(result.delivery.version, 1);
      expect(result.pregnancy.status, PregnancyStatus.delivered);
    });

    test('a delivery on a closed pregnancy is A.6 case 12-style RULE_VIOLATION',
        () async {
      Future<void> record() => api.pregnancies.recordDelivery(
            MockApi.pregnancyId,
            const {
              'id': 'dl_mock',
              'deliveredAt': '2026-11-25T02:00:00.000Z',
              'place': 'hospital',
              'mode': 'normal',
              'outcome': 'live_birth',
              'complications': <String>[],
            },
          );

      await record();
      await expectLater(
        record(),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppError.ruleViolation)
              .having((e) => e.httpStatus, 'status', 422),
        ),
      );
    });

    test('a pushed deliveries row is applied and comes back on the pull',
        () async {
      final pushed = await api.sync.push(
        deviceId: 'dev1',
        changes: const [
          SyncChange(
            opId: 'op1',
            table: 'deliveries',
            op: 'upsert',
            rowId: 'dl_push',
            baseVersion: 0,
            payload: {
              'id': 'dl_push',
              'pregnancyId': MockApi.pregnancyId,
              'deliveredAt': '2026-11-25T02:00:00.000Z',
              'place': 'home',
              'mode': 'normal',
              'outcome': 'live_birth',
              'complications': <String>[],
            },
          ),
        ],
      );

      expect(pushed.results.single.status, SyncOpStatus.applied);
      expect(pushed.results.single.row!['version'], 1);

      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');
      final tables = pulled.changes.map((c) => c.table).toSet();
      expect(
        tables,
        contains('deliveries'),
        reason: 'A.8: the pull must carry every table the account can see',
      );
    });
  });

  group('the screens', () {
    testWidgets('S12 swaps "Record delivery" for the delivery card',
        (tester) async {
      // Deliberately not closed in a tear-down: S12's bundle is a
      // `combineLatest4` over four drift streams, and closing the database
      // while their cancellation is still in flight wedges the fake-async
      // zone the test runs in. The database is in memory and dies with the
      // test.
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      await db.pregnanciesDao
          .upsertPregnancy(pregnancy(status: PregnancyStatus.delivered));
      await db.pregnanciesDao
          .upsertDelivery(delivery(complications: const ['PPH']));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const PregnancyDashboardScreen(pregnancyId: pregnancyId),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Record delivery'), findsNothing);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.textContaining('Hospital'), findsOneWidget);
      expect(
        find.text('Heavy bleeding after birth (PPH)'),
        findsOneWidget,
        reason: 'a complication code has to read as words',
      );
      // Binary floating point turns 3.4 into 3.4000000000000004; nobody wants
      // to read that off a birth record.
      expect(find.textContaining('2.9 kg'), findsOneWidget);
      expect(find.textContaining('2.9000'), findsNothing);

      await unmount(tester);
    });

    testWidgets('S12 still offers "Record delivery" while the pregnancy is open',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.pregnanciesDao.upsertPregnancy(pregnancy());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const PregnancyDashboardScreen(pregnancyId: pregnancyId),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Record delivery'), findsOneWidget);
      expect(find.text('Delivered'), findsNothing);

      await unmount(tester);
    });

    testWidgets('S08 keeps a way back into a pregnancy that has been closed',
        (tester) async {
      // Found on the phone: S08 showed the pregnancy card only while the
      // pregnancy was active, so recording a delivery made the delivery record
      // reachable from nowhere at all.
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      await db.patientsDao.upsert(
        const Patient(
          id: patientId,
          ownerUserId: 'u1',
          name: 'Sita Chaudhary',
          sex: Sex.female,
          dob: '2002-04-11',
        ),
      );
      await db.pregnanciesDao
          .upsertPregnancy(pregnancy(status: PregnancyStatus.delivered));
      await db.pregnanciesDao.upsertDelivery(delivery());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const PatientHomeScreen(patientId: patientId),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Delivered'), findsOneWidget);
      // And the next pregnancy can still be started.
      expect(find.text('Register pregnancy'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('the S06 badge reads Delivered once the pregnancy is closed',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          Column(
            children: [
              PregnantBadge(pregnancy: pregnancy()),
              PregnantBadge(
                pregnancy: pregnancy(status: PregnancyStatus.delivered),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Pregnant'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
    });
  });

  group('the complication list', () {
    test('every offered code has a label that is not the code itself', () {
      // A chip that renders its own code is a chip nobody can act on.
      expect(deliveryComplicationCodes, isNotEmpty);
      for (final code in deliveryComplicationCodes) {
        expect(isKnownComplication(code), isTrue);
      }
      expect(isKnownComplication('SOMETHING_ELSE'), isFalse);
    });
  });
}
