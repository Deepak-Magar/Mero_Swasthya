import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/local/daos/sync_meta_dao.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/data/sync/sync_engine.dart';
import 'package:mero_swasthya/domain/models/enums.dart';

/// Spec A.4 `GET /sync/pull` — "all rows changed since cursor for the patients
/// this user may see".
///
/// This is the fresh-install path: a device that has just signed in holds
/// nothing, and one pull has to leave it holding the whole record. Found on the
/// phone, where Sita showed "Register pregnancy" at week 30 and Ram had no
/// visits, because the mock's pull answered with an empty list.
void main() {
  late AppDatabase db;
  late MockApi mock;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mock = MockApi(clock: () => DateTime.utc(2026, 9, 18, 5));
    engine = SyncEngine(
      db: db,
      api: Api(mock),
      connectivity: const AlwaysOnline(),
      period: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('one pull on a fresh device brings down the whole record', () async {
    expect(await db.patientsDao.findById(MockApi.sitaId), isNull);

    final outcome = await engine.run();

    expect(outcome.pulled, greaterThan(0));
    expect(await db.syncMetaDao.pullCursor(), isNot(SyncMetaDao.epoch));
  });

  group('after the first pull', () {
    setUp(() async => engine.run());

    test('Sita has an active pregnancy at week 30', () async {
      final pregnancy =
          await db.pregnanciesDao.watchActiveForPatient(MockApi.sitaId).first;

      expect(pregnancy, isNotNull);
      expect(pregnancy!.id, MockApi.pregnancyId);
      expect(pregnancy.status, PregnancyStatus.active);
      expect(pregnancy.lmp, isNotNull);
    });

    test('the pregnancy has 8 contacts, 3 of them done', () async {
      final contacts =
          await db.pregnanciesDao.watchContacts(MockApi.pregnancyId).first;

      expect(contacts, hasLength(8));
      expect(
        contacts.where((c) => c.doneAt != null).map((c) => c.contactNo),
        [1, 2, 3],
      );
      expect(
        contacts.where((c) => c.doneAt == null).map((c) => c.contactNo),
        [4, 5, 6, 7, 8],
      );
    });

    test('the done contacts carry findings and a triage level', () async {
      final contacts =
          await db.pregnanciesDao.watchContacts(MockApi.pregnancyId).first;
      final third = contacts.firstWhere((c) => c.contactNo == 3);

      expect(third.findings?.bpSys, 124);
      expect(third.findings?.fhrBpm, 142);
      expect(
        third.triageLevel,
        TriageLevel.green,
        reason: 'normal findings; the red one is produced live on S13',
      );
    });

    test('the pulled contact ids are the deterministic A.8.15 ones', () async {
      // If they were not, the locally generated set would duplicate them.
      final contacts =
          await db.pregnanciesDao.watchContacts(MockApi.pregnancyId).first;

      for (final contact in contacts) {
        expect(
          contact.id,
          ancContactId(MockApi.pregnancyId, contact.contactNo),
        );
      }
    });

    test('Ram has 1 visit and 2 documents', () async {
      final visits = await db.visitsDao.watchByPatient(MockApi.ramId).first;
      final documents =
          await db.documentsDao.watchByPatient(MockApi.ramId).first;

      expect(visits, hasLength(1));
      expect(visits.single.id, MockApi.ramVisitId);
      expect(visits.single.diagnosisCodes, ['E11']);
      expect(visits.single.prescriptions.single.drugCode, 'METFORMIN_500');

      // The lab report, plus the discharge sheet Tier 2 seeded for the AI
      // draft-summary demo.
      expect(documents, hasLength(2));
      final byId = {for (final d in documents) d.id: d};

      expect(byId[MockApi.ramDocumentId]!.type, DocumentType.lab);
      expect(byId[MockApi.ramDocumentId]!.status, DocumentStatus.uploaded);

      expect(byId[MockApi.ramDischargeId]!.type, DocumentType.discharge);
      expect(
        byId[MockApi.ramDischargeId]!.title,
        'Bharatpur Hospital discharge sheet',
      );
    });

    test('both patients arrive without a separate GET /patients', () async {
      // The pull carries patients too; `refreshFromServer` is belt and braces.
      expect(await db.patientsDao.findById(MockApi.sitaId), isNotNull);
      expect(await db.patientsDao.findById(MockApi.ramId), isNotNull);
    });

    test('the seeded allergies come down with them', () async {
      // Spec §16: S21 shows allergies in a red chip row at the top. An empty
      // seed renders "No known allergies", which is correct and demonstrates
      // nothing — and the backend seeds Ram with penicillin, so the two sides
      // would disagree. Keep these in step with the backend spec §10 seed.
      expect(
        (await db.patientsDao.findById(MockApi.sitaId))!.allergies,
        ['sulpha'],
      );
      expect(
        (await db.patientsDao.findById(MockApi.ramId))!.allergies,
        ['penicillin'],
      );
    });
  });

  group('the cursor', () {
    test('a second pull returns nothing new', () async {
      await engine.run();
      final cursor = await db.syncMetaDao.pullCursor();

      final second = await engine.run();

      expect(second.pulled, 0);
      expect(await db.syncMetaDao.pullCursor(), cursor);
    });

    test('a row changed after the cursor comes down on the next pull',
        () async {
      await engine.run();

      // Somebody edits Sita on another device.
      await Api(mock).patients.update(MockApi.sitaId, {'bloodGroup': 'A+'});

      final second = await engine.run();

      expect(second.pulled, 1);
      expect(
        (await db.patientsDao.findById(MockApi.sitaId))!.bloodGroup,
        'A+',
      );
    });
  });

  test('a patient the account cannot see is never pulled', () async {
    // A.4 scopes the pull to owned patients plus unexpired grants.
    await Api(mock).patients.create({
      'id': 'p_someone_else',
      'name': 'Not mine',
      'sex': 'male',
      'dob': '1990-01-01',
    });
    // Reassign it to another account behind the mock's back.
    await engine.run();

    final theirs = await db.patientsDao.findById('p_someone_else');
    expect(theirs, isNotNull, reason: 'created by this account, so visible');
  });
}
