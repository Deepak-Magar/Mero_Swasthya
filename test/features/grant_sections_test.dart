import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/provider/provider_patient_screen.dart';

import 'harness.dart';

/// Tier 3 — fine-grained consent on a QR grant.
///
/// Two halves, and the first is the one that matters: the **server** filters
/// the bundle. Consent a client enforces is not consent, because a provider
/// with a debugger would still have the whole record.
void main() {
  late Api api;

  setUp(() => api = Api(MockApi(clock: DateTime.now)));

  Future<RedeemResult> redeemWith(List<GrantSection> sections) async {
    final grant = await api.grants.create(
      patientId: MockApi.sitaId,
      sections: sections,
    );
    return api.grants.redeem(grant.qrPayload);
  }

  group('the mock filters the bundle', () {
    test('no sections means the whole record, as it always did', () async {
      final result = await redeemWith(const []);

      expect(result.grant.sections, isEmpty);
      expect(result.pregnancy, isNotNull);
      expect(result.summary.allergies, contains('sulpha'));
      expect(result.timeline, isNotEmpty);
    });

    test('sharing only the pregnancy withholds everything else', () async {
      final result = await redeemWith([GrantSection.pregnancy]);

      expect(result.grant.sections, [GrantSection.pregnancy]);
      expect(result.pregnancy, isNotNull);
      expect(result.ancContacts, isNotEmpty);

      // The summary is present but empty — A.4 types it as required, so
      // withholding a section must not change the shape of the envelope.
      expect(result.summary.activeProblems, isEmpty);
      expect(result.summary.currentMedicines, isEmpty);
      expect(result.summary.visitCount, 0);

      // No visits and no documents reached the timeline.
      final kinds = result.timeline.map((i) => i.kind.wire).toSet();
      expect(kinds, isNot(contains('visit')));
      expect(kinds, isNot(contains('document')));
    });

    test('sharing only the summary withholds the pregnancy', () async {
      final result = await redeemWith([GrantSection.summary]);

      expect(result.pregnancy, isNull);
      expect(result.ancContacts, isEmpty);
      expect(result.summary.allergies, contains('sulpha'));

      final kinds = result.timeline.map((i) => i.kind.wire).toSet();
      expect(kinds, isNot(contains('pregnancy_registered')));
    });

    test('the patient row — and so the allergies — always travels', () async {
      // Hiding a sulpha allergy because somebody ticked only "pregnancy" would
      // be a consent feature that could kill a patient. `allergies` lives on
      // the patient row, which is never withheld.
      final result = await redeemWith([GrantSection.child]);

      expect(result.patient.name, 'Sita Chaudhary');
      expect(result.patient.allergies, contains('sulpha'));
    });

    test('visits and documents are separately shareable', () async {
      final ram = await api.grants.create(
        patientId: MockApi.ramId,
        sections: [GrantSection.visits],
      );
      final result = await api.grants.redeem(ram.qrPayload);

      final kinds = result.timeline.map((i) => i.kind.wire).toSet();
      expect(kinds, contains('visit'));
      expect(kinds, isNot(contains('document')));
    });

    test('child sections carry immunisations and growth', () async {
      final aarav = await api.grants.create(
        patientId: MockApi.aaravId,
        sections: [GrantSection.child],
      );
      final result = await api.grants.redeem(aarav.qrPayload);

      final kinds = result.timeline.map((i) => i.kind.wire).toSet();
      expect(kinds, containsAll(['immunisation', 'growth']));
    });

    test('withholding the child section drops them again', () async {
      final aarav = await api.grants.create(
        patientId: MockApi.aaravId,
        sections: [GrantSection.summary],
      );
      final result = await api.grants.redeem(aarav.qrPayload);

      final kinds = result.timeline.map((i) => i.kind.wire).toSet();
      expect(kinds, isNot(contains('immunisation')));
      expect(kinds, isNot(contains('growth')));
    });

    test('several sections combine', () async {
      final result =
          await redeemWith([GrantSection.summary, GrantSection.pregnancy]);

      expect(result.summary.allergies, isNotEmpty);
      expect(result.pregnancy, isNotNull);
      expect(
        result.timeline.map((i) => i.kind.wire).toSet(),
        isNot(contains('visit')),
      );
    });

    test('the sections come back on the grant so the app can say so', () async {
      final result =
          await redeemWith([GrantSection.pregnancy, GrantSection.child]);

      expect(
        result.grant.sections,
        [GrantSection.pregnancy, GrantSection.child],
      );
    });
  });

  group('the wire format', () {
    test('every section maps to the string the contract names', () {
      expect(
        GrantSection.values.map((s) => s.wire).toList(),
        ['summary', 'visits', 'documents', 'pregnancy', 'child', 'audit'],
      );
    });

    test('an unknown section string is ignored, not fatal', () {
      // A server a version ahead must not crash an older app.
      expect(GrantSection.fromWire('summary'), GrantSection.summary);
      expect(GrantSection.fromWire('something_new'), isNull);
    });
  });

  group('S21 shows only what was shared', () {
    const patient = Patient(
      id: 'p_sections',
      ownerUserId: 'u_other',
      name: 'Sita Chaudhary',
      sex: Sex.female,
      dob: '2002-04-11',
      allergies: ['sulpha'],
      chronicConditions: ['E11'],
    );

    Future<AppDatabase> seed(List<String> sections) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.patientsDao.upsert(patient);
      await db.syncMetaDao.setReadOnlyAccess(patient.id, value: false);
      await db.syncMetaDao.setGrantSections(patient.id, sections);
      return db;
    }

    Future<void> pump(WidgetTester tester, AppDatabase db) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: appShellForTest(
            const ProviderPatientScreen(patientId: 'p_sections'),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('a narrow grant says so and hides the rest', (tester) async {
      final db = await seed(['pregnancy']);
      await pump(tester, db);

      expect(find.textContaining('Patient shared'), findsOneWidget);
      expect(find.textContaining('Pregnancy'), findsWidgets);
      // Chronic conditions belong to the summary, which was not shared.
      expect(find.text('E11'), findsNothing);
      // The allergy is on the patient row and is never withheld.
      expect(find.textContaining('sulpha'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('an unrestricted grant shows everything and says nothing',
        (tester) async {
      final db = await seed(const []);
      await pump(tester, db);

      expect(find.textContaining('Patient shared'), findsNothing);
      expect(find.text('E11'), findsOneWidget);

      await unmount(tester);
    });
  });
}
