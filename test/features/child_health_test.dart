import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/repositories/child_health_repo.dart';
import 'package:mero_swasthya/data/repositories/sync_kicker.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/epi_schedule.dart';

/// Tier 3 — the child-health module end to end below the UI: the repository's
/// write path, the mock's seed, and the two new tables travelling through sync.
class _NoopKicker implements SyncKicker {
  int kicks = 0;

  @override
  void kick() => kicks++;
}

void main() {
  late EpiSchedule epi;

  setUpAll(() {
    final raw = File('assets/epi_schedule.json').readAsStringSync();
    epi = EpiSchedule.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  });

  group('the repository', () {
    late AppDatabase db;
    late _NoopKicker kicker;
    late ChildHealthRepo repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      kicker = _NoopKicker();
      repo = ChildHealthRepo(db, kicker);
    });

    tearDown(() => db.close());

    test('generates the schedule once and never twice', () async {
      final dob = DateTime.utc(2026, 1, 6);

      final first =
          await repo.ensureSchedule(patientId: 'p1', dob: dob, epi: epi);
      expect(first, greaterThan(0));

      // Re-running would re-enqueue every dose and undo any `givenAt` the
      // server has since applied.
      final second =
          await repo.ensureSchedule(patientId: 'p1', dob: dob, epi: epi);
      expect(second, 0);

      final stored = await repo.schedule('p1');
      expect(stored, hasLength(first));
    });

    test('the schedule itself is not pushed — only the doses given are',
        () async {
      // Like A.8.15's eight ANC contacts: the server derives the same rows from
      // the same date of birth with the same ids. Thirty empty placeholders
      // would be thirty ops that say nothing.
      await repo.ensureSchedule(
        patientId: 'p1',
        dob: DateTime.utc(2026, 1, 6),
        epi: epi,
      );

      expect(await db.outboxDao.take(), isEmpty);
      expect(kicker.kicks, 0);
    });

    test('recording a dose writes the row and queues exactly one op', () async {
      await repo.ensureSchedule(
        patientId: 'p1',
        dob: DateTime.utc(2026, 1, 6),
        epi: epi,
      );

      final schedule = await repo.schedule('p1');
      final bcg = schedule.firstWhere((d) => d.vaccineCode == 'BCG');

      await repo.recordDose(
        bcg,
        givenAt: DateTime.utc(2026, 1, 7, 10),
        batchNo: '  b-42  ',
        givenByUserId: 'u_0002',
      );

      final stored = await db.childHealthDao.findImmunisation(bcg.id);
      expect(stored!.givenAt, isNotNull);
      expect(stored.batchNo, 'b-42', reason: 'a batch number is trimmed');
      expect(stored.givenByUserId, 'u_0002');

      final ops = await db.outboxDao.take();
      expect(ops, hasLength(1));
      expect(ops.single.targetTable, SyncTables.immunisations);
      expect(ops.single.rowId, bcg.id);
      expect(kicker.kicks, 1);
    });

    test('an empty batch number is stored as null, not as a blank', () async {
      await repo.ensureSchedule(
        patientId: 'p1',
        dob: DateTime.utc(2026, 1, 6),
        epi: epi,
      );
      final bcg =
          (await repo.schedule('p1')).firstWhere((d) => d.vaccineCode == 'BCG');

      await repo.recordDose(bcg, givenAt: DateTime.utc(2026, 1, 7), batchNo: '  ');

      final stored = await db.childHealthDao.findImmunisation(bcg.id);
      expect(stored!.batchNo, isNull);
    });

    test('clearing a dose puts it back to not-given and queues that too',
        () async {
      await repo.ensureSchedule(
        patientId: 'p1',
        dob: DateTime.utc(2026, 1, 6),
        epi: epi,
      );
      final bcg =
          (await repo.schedule('p1')).firstWhere((d) => d.vaccineCode == 'BCG');

      await repo.recordDose(bcg, givenAt: DateTime.utc(2026, 1, 7));
      final given = await db.childHealthDao.findImmunisation(bcg.id);
      expect(given!.givenAt, isNotNull);

      await repo.clearDose(given);
      final cleared = await db.childHealthDao.findImmunisation(bcg.id);
      expect(cleared!.givenAt, isNull);
      expect(cleared.batchNo, isNull);
      // The due date survives — the dose is still on the schedule.
      expect(cleared.dueAt, bcg.dueAt);
    });

    test('a measurement is written and queued', () async {
      final measurement = repo.newMeasurement(
        patientId: 'p1',
        measuredAt: DateTime.utc(2026, 6, 1),
        weightKg: 7.4,
        heightCm: 65,
      );
      await repo.addMeasurement(measurement);

      final stored = await repo.watchGrowth('p1').first;
      expect(stored, hasLength(1));
      expect(stored.single.weightKg, 7.4);
      expect(stored.single.heightCm, 65);
      expect(stored.single.muacCm, isNull);

      final ops = await db.outboxDao.take();
      expect(ops.single.targetTable, SyncTables.growthMeasurements);
      expect(ops.single.baseVersion, 0, reason: 'a measurement is a create');
    });

    test('measurements come back oldest first, which is chart order', () async {
      for (final (day, kg) in [(3, 8.0), (1, 6.0), (2, 7.0)]) {
        await repo.addMeasurement(
          repo.newMeasurement(
            patientId: 'p1',
            measuredAt: DateTime.utc(2026, 6, day),
            weightKg: kg,
          ),
        );
      }

      final stored = await repo.watchGrowth('p1').first;
      expect(stored.map((m) => m.weightKg).toList(), [6.0, 7.0, 8.0]);
    });
  });

  group('the mock', () {
    late Api api;

    setUp(() => api = Api(MockApi(clock: DateTime.now)));

    test('seeds Aarav with a schedule, six-plus doses given and one overdue',
        () async {
      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');

      final patients = [
        for (final c in pulled.changes)
          if (c.table == 'patients') Patient.fromJson(c.row),
      ];
      final aarav = patients.firstWhere((p) => p.id == MockApi.aaravId);
      expect(aarav.name, 'Aarav Chaudhary');

      final dob = DateTime.parse(aarav.dob);
      expect(isUnderFive(dob), isTrue, reason: 'he has to be under five');

      final doses = [
        for (final c in pulled.changes)
          if (c.table == 'immunisations') Immunisation.fromJson(c.row),
      ].where((d) => d.patientId == MockApi.aaravId).toList();

      expect(doses, isNotEmpty);
      final progress = immunisationProgress(doses);
      expect(
        progress.given,
        greaterThanOrEqualTo(6),
        reason: 'the card should look like a real child, not an empty one',
      );

      final overdue = overdueDoses(doses);
      expect(overdue, isNotEmpty, reason: 'the demo needs a row to point at');
      expect(
        overdue.any((d) => d.vaccineCode == 'MR' && d.doseNo == 2),
        isTrue,
        reason: 'the 15-month MR booster is the one he has missed',
      );
    });

    test('the seeded ids match what the app would generate', () async {
      // The whole point of the deterministic id. If these ever diverge a child
      // registered offline gets two of every vaccine.
      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');
      final doses = [
        for (final c in pulled.changes)
          if (c.table == 'immunisations') Immunisation.fromJson(c.row),
      ].where((d) => d.patientId == MockApi.aaravId);

      for (final d in doses) {
        expect(
          d.id,
          immunisationId(d.patientId, d.vaccineCode, d.doseNo),
          reason: '${d.vaccineCode} dose ${d.doseNo}',
        );
      }
    });

    test('the mock seeds exactly the schedule the asset generates', () async {
      // The mock keeps its own copy of the EPI rows because a unit test has no
      // asset bundle. That duplication is how the fIPV error survived: the
      // asset said 6 and 14 weeks and so did the mock, so nothing disagreed.
      // This is the check that makes the two copies unable to drift again —
      // it compares what the mock actually seeds against what the shipped
      // asset generates for the same child and the same date of birth.
      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');

      final aarav = [
        for (final c in pulled.changes)
          if (c.table == 'patients') Patient.fromJson(c.row),
      ].firstWhere((p) => p.id == MockApi.aaravId);

      final seeded = [
        for (final c in pulled.changes)
          if (c.table == 'immunisations') Immunisation.fromJson(c.row),
      ].where((d) => d.patientId == MockApi.aaravId).toList();

      final expected = epi.generateFor(
        patientId: MockApi.aaravId,
        dob: DateTime.parse(aarav.dob),
      );

      String key(Immunisation d) =>
          '${d.vaccineCode}:${d.doseNo}:${d.dueAt}:${d.id}';

      expect(
        seeded.map(key).toSet(),
        expected.map(key).toSet(),
        reason: 'the mock and assets/epi_schedule.json have drifted apart',
      );
    });

    test('seeds three weights', () async {
      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');
      final growth = [
        for (final c in pulled.changes)
          if (c.table == 'growth_measurements') GrowthMeasurement.fromJson(c.row),
      ].where((g) => g.patientId == MockApi.aaravId).toList();

      expect(growth, hasLength(3));
      expect(growth.every((g) => g.weightKg > 0), isTrue);
    });

    test('a given dose reaches the timeline; a scheduled one does not',
        () async {
      final items = (await api.patients.timeline(MockApi.aaravId)).items;
      final kinds = items.map((i) => i.kind.wire).toSet();

      expect(kinds, contains('immunisation'));
      expect(kinds, contains('growth'));

      // Every immunisation row on the timeline must be one that happened.
      for (final item in items.where((i) => i.kind.wire == 'immunisation')) {
        expect(Immunisation.fromJson(item.payload).givenAt, isNotNull);
      }
    });

    test('both new tables push and come back on the pull', () async {
      final pushed = await api.sync.push(
        deviceId: 'dev1',
        changes: [
          SyncChange(
            opId: 'op-imm',
            table: 'immunisations',
            op: 'upsert',
            rowId: immunisationId(MockApi.aaravId, 'BCG', 1),
            baseVersion: 1,
            payload: {
              'id': immunisationId(MockApi.aaravId, 'BCG', 1),
              'patientId': MockApi.aaravId,
              'vaccineCode': 'BCG',
              'doseNo': 1,
              'dueAt': '2023-07-14',
              'givenAt': '2023-07-16T10:00:00.000Z',
              'batchNo': 'PUSHED-1',
            },
          ),
          const SyncChange(
            opId: 'op-growth',
            table: 'growth_measurements',
            op: 'upsert',
            rowId: 'gm-pushed',
            baseVersion: 0,
            payload: {
              'id': 'gm-pushed',
              'patientId': MockApi.aaravId,
              'measuredAt': '2026-09-01T10:00:00.000Z',
              'weightKg': 13.9,
            },
          ),
        ],
      );

      expect(
        pushed.results.map((r) => r.status).toList(),
        [SyncOpStatus.applied, SyncOpStatus.applied],
      );
      expect(pushed.results.first.row!['batchNo'], 'PUSHED-1');

      final pulled = await api.sync.pull(since: '', deviceId: 'dev1');
      final tables = pulled.changes.map((c) => c.table).toSet();
      expect(tables, containsAll(['immunisations', 'growth_measurements']));
    });
  });
}
