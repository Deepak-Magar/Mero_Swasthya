import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/local/daos/sync_meta_dao.dart';
import 'package:mero_swasthya/data/local/outbox.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/repositories/patient_repo.dart';
import 'package:mero_swasthya/data/repositories/pregnancy_repo.dart';
import 'package:mero_swasthya/data/repositories/sync_kicker.dart';
import 'package:mero_swasthya/data/repositories/visit_repo.dart';
import 'package:mero_swasthya/data/sync/sync_engine.dart';
import 'package:mero_swasthya/data/sync/sync_status.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

import '../support/transports.dart';

/// Spec §7 — the push/pull cycle.
void main() {
  late AppDatabase db;
  late FakeSyncTransport transport;
  late FakeConnectivity connectivity;
  late SyncEngine engine;
  late List<(String, String)> conflicts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    transport = FakeSyncTransport();
    connectivity = FakeConnectivity();
    conflicts = [];
    engine = SyncEngine(
      db: db,
      api: Api(transport),
      connectivity: connectivity,
      onConflict: (table, rowId) => conflicts.add((table, rowId)),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await connectivity.dispose();
    await db.close();
  });

  Patient patient({String id = 'p1', String name = 'Sita Devi', int version = 0}) =>
      Patient(
        id: id,
        ownerUserId: 'u1',
        name: name,
        sex: Sex.female,
        dob: '1998-04-12',
        version: version,
      );

  Visit visit({String id = 'v1'}) => Visit(
        id: id,
        patientId: 'p1',
        visitAt: '2026-09-18T05:30:00.000Z',
        chiefComplaintCode: 'FEVER',
      );

  /// Queues one op the way a repository would, without a live engine.
  Future<void> queuePatient({String id = 'p1', String name = 'Sita Devi'}) =>
      PatientRepo(db, const NoopSyncKicker(), Api(transport)).create(patient(id: id, name: name));

  group('push', () {
    test('an applied op is removed and the server row replaces the local one',
        () async {
      await queuePatient();

      final outcome = await engine.run();

      expect(outcome.pushed, 1);
      expect(await db.outboxDao.take(), isEmpty);
      final stored = await db.patientsDao.findById('p1');
      expect(
        stored!.version,
        1,
        reason: 'version 0 means "not on the server"; the push settles that',
      );
    });

    test('the batch carries the device id and the queued op verbatim',
        () async {
      await queuePatient();

      await engine.run();

      final request = transport.pushRequests.single;
      expect(request['deviceId'], await db.syncMetaDao.deviceId());

      final change = (request['changes'] as List).single as Map;
      expect(change['table'], 'patients');
      expect(change['op'], 'upsert');
      expect(change['rowId'], 'p1');
      expect(change['baseVersion'], 0);
      expect((change['payload'] as Map)['name'], 'Sita Devi');
    });

    test('a duplicate is treated as applied, not as a failure', () async {
      // The previous attempt landed and only the response was lost.
      await queuePatient();
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'duplicate',
                'row': FakeSyncTransport.applied(c),
              },
          ];

      final outcome = await engine.run();

      expect(outcome.pushed, 1);
      expect(await db.outboxDao.take(), isEmpty);
    });

    test('a conflict replaces the local row and reports it', () async {
      await queuePatient(name: 'What the user typed');
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'conflict',
                'current': {
                  ...patient(name: 'What the server holds', version: 7).toJson(),
                  'updatedAt': '2026-09-18T05:00:00.000Z',
                },
              },
          ];

      final outcome = await engine.run();

      expect(outcome.conflicts, 1);
      expect(conflicts, [('patients', 'p1')]);
      final stored = await db.patientsDao.findById('p1');
      expect(stored!.name, 'What the server holds');
      expect(stored.version, 7);
      expect(
        await db.outboxDao.take(),
        isEmpty,
        reason: 'the op is settled; re-sending it would conflict forever',
      );
    });

    test('a rejected op keeps the server message and is not retried', () async {
      await queuePatient();
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'rejected',
                'error': {
                  'code': 'RULE_VIOLATION',
                  'message': 'EDD is in the past',
                },
              },
          ];

      final first = await engine.run();
      expect(first.rejected, 1);

      final failed = await db.outboxDao.watchFailed().first;
      expect(failed.single.lastError, 'EDD is in the past');

      transport.pushRequests.clear();
      await engine.run();
      expect(
        transport.pushRequests,
        isEmpty,
        reason: 'retrying a rule violation would spin forever',
      );
    });

    test('more than one batch is pushed in created_at order', () async {
      final repo = VisitRepo(db, const NoopSyncKicker());
      for (var i = 0; i < OutboxDao.batchSize + 10; i++) {
        await repo.add(visit(id: 'v_$i'));
      }

      final outcome = await engine.run();

      expect(outcome.pushed, OutboxDao.batchSize + 10);
      expect(transport.pushRequests, hasLength(2));
      expect(
        (transport.pushRequests.first['changes'] as List),
        hasLength(OutboxDao.batchSize),
      );

      final sentIds = [
        for (final request in transport.pushRequests)
          for (final change in request['changes'] as List)
            (change as Map)['rowId'] as String,
      ];
      expect(sentIds, [for (var i = 0; i < 60; i++) 'v_$i']);
    });

    test('every queued createdAt is stored at the same text width', () async {
      // `created_at` is TEXT and is both ordered and max()-ed as text, so the
      // stamps have to be directly comparable. `toIso8601String()` prints
      // three fractional digits at whole milliseconds and six otherwise, and
      // "...12.123Z" sorts after "...12.123456Z" — which swapped adjacent
      // ops in the batch above about once in every few hundred runs.
      final repo = VisitRepo(db, const NoopSyncKicker());
      for (var i = 0; i < 40; i++) {
        await repo.add(visit(id: 'w_$i'));
      }

      final rows = await db.outboxDao.take(100);
      final widths = {for (final row in rows) row.createdAt.length};
      expect(widths, hasLength(1), reason: 'stamps: ${widths.toList()}');
      for (final row in rows) {
        expect(row.createdAt, endsWith('Z'));
        expect(row.createdAt.split('.').last, hasLength(4)); // mmmZ
      }

      final sorted = [for (final row in rows) row.createdAt]..sort();
      expect(sorted, [for (final row in rows) row.createdAt]);
    });

    test('a parent is pushed before its child', () async {
      // The delivery and the pregnancy it closes go out in one transaction;
      // the server cannot end a pregnancy it has not been told about.
      final repo = PregnancyRepo(db, const NoopSyncKicker());
      const pregnancy = Pregnancy(
        id: 'pg1',
        patientId: 'p1',
        edd: '2026-12-06',
      );
      await repo.register(pregnancy, const []);
      await repo.recordDelivery(
        const Delivery(
          id: 'del1',
          pregnancyId: 'pg1',
          deliveredAt: '2026-12-01T02:00:00.000Z',
          place: DeliveryPlace.hospital,
          mode: DeliveryMode.normal,
          outcome: DeliveryOutcome.liveBirth,
        ),
        pregnancy.copyWith(status: PregnancyStatus.delivered),
      );

      await engine.run();

      final tables = [
        for (final change in transport.pushRequests.single['changes'] as List)
          (change as Map)['table'] as String,
      ];
      expect(tables, ['pregnancies', 'deliveries', 'pregnancies']);
    });

    test('the server time offset is recorded', () async {
      // A phone with a wrong clock would otherwise show nonsense next to
      // "due in x days".
      await queuePatient();
      transport.serverTime =
          DateTime.now().toUtc().add(const Duration(minutes: 5))
              .toIso8601String();

      await engine.run();

      final offset = await db.syncMetaDao.serverTimeOffsetMs();
      expect(offset, greaterThan(4 * 60 * 1000));
      expect(offset, lessThan(6 * 60 * 1000));
    });

    test('nothing queued means nothing sent', () async {
      final outcome = await engine.run();

      expect(transport.pushRequests, isEmpty);
      expect(outcome.pushed, 0);
      expect(transport.pullRequests, hasLength(1), reason: 'the pull still runs');
    });
  });

  group('pull', () {
    test('a newer row is applied and the cursor is persisted', () async {
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change('patients', {
              ...patient(name: 'From the server', version: 3).toJson(),
              'updatedAt': '2026-09-18T05:00:00.000Z',
            }),
          ],
          cursor: '2026-09-18T05:10:00.000Z',
        ),
      );

      final outcome = await engine.run();

      expect(outcome.pulled, 1);
      expect((await db.patientsDao.findById('p1'))!.name, 'From the server');
      expect(
        await db.syncMetaDao.pullCursor(),
        '2026-09-18T05:10:00.000Z',
      );
    });

    test('the first pull starts at the epoch', () async {
      await engine.run();
      expect(transport.pullRequests.single['since'], SyncMetaDao.epoch);
    });

    test('an older row is left alone', () async {
      await db.patientsDao.upsertFromServer(
        patient(name: 'Newer local', version: 5).toJson(),
      );
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change(
              'patients',
              patient(name: 'Stale', version: 2).toJson(),
            ),
          ],
          cursor: 'c1',
        ),
      );

      final outcome = await engine.run();

      expect(outcome.pulled, 0);
      expect((await db.patientsDao.findById('p1'))!.name, 'Newer local');
    });

    test('a row with a pending op is never overwritten', () async {
      // Spec §7. The push result settles that row; clobbering it here would
      // throw away something the user typed and has not seen sent yet.
      await queuePatient(name: 'Unsent local edit');
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'rejected',
                'error': {'code': 'RATE_LIMITED', 'message': 'Try later'},
              },
          ];
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change(
              'patients',
              patient(name: 'Server version', version: 9).toJson(),
            ),
          ],
          cursor: 'c1',
        ),
      );

      await engine.run();

      expect((await db.patientsDao.findById('p1'))!.name, 'Unsent local edit');
      expect(
        await db.syncMetaDao.pullCursor(),
        'c1',
        reason: 'the cursor still advances; the row is skipped, not the page',
      );
    });

    test('paging continues while hasMore and ends on the last cursor',
        () async {
      transport.pullPages.addAll([
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change(
              'patients',
              patient(id: 'p1', version: 1).toJson(),
            ),
          ],
          cursor: 'c1',
          hasMore: true,
        ),
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change(
              'patients',
              patient(id: 'p2', version: 1).toJson(),
            ),
          ],
          cursor: 'c2',
        ),
      ]);

      final outcome = await engine.run();

      expect(outcome.pulled, 2);
      expect(transport.pullRequests.map((r) => r['since']),
          [SyncMetaDao.epoch, 'c1']);
      expect(await db.syncMetaDao.pullCursor(), 'c2');
    });

    test('a row for a table this build does not know is skipped, not fatal',
        () async {
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change('immunisations', {'id': 'i1', 'version': 1}),
            FakeSyncTransport.change(
              'patients',
              patient(version: 1).toJson(),
            ),
          ],
          cursor: 'c1',
        ),
      );

      final outcome = await engine.run();

      expect(outcome.pulled, 1, reason: 'the known row still lands');
      expect(await db.syncMetaDao.pullCursor(), 'c1');
    });

    test('one unparseable row does not strand the cursor', () async {
      // Otherwise every later page is blocked for good.
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change('patients', {'id': 'broken'}),
            FakeSyncTransport.change(
              'visits',
              {...visit().toJson(), 'version': 1},
            ),
          ],
          cursor: 'c1',
        ),
      );

      final outcome = await engine.run();

      expect(outcome.pulled, 1);
      expect(await db.syncMetaDao.pullCursor(), 'c1');
      expect(await db.visitsDao.findById('v1'), isNotNull);
    });

    test('a soft-deleted row arrives as deleted=true', () async {
      await db.patientsDao.upsertFromServer(patient(version: 1).toJson());
      transport.pullPages.add(
        FakeSyncTransport.page(
          [
            FakeSyncTransport.change('patients', {
              ...patient(version: 2).toJson(),
              'deleted': true,
            }),
          ],
          cursor: 'c1',
        ),
      );

      await engine.run();

      expect((await db.patientsDao.findById('p1'))!.deleted, isTrue);
      expect(await db.patientsDao.watchFamily('u1').first, isEmpty);
    });
  });

  group('triage mismatch (spec S13 / A.4)', () {
    /// Queues a contact recorded locally as green, then has the server answer
    /// with red.
    Future<List<(String, TriageLevel, TriageLevel?)>> pushContact({
      required TriageLevel local,
      required String serverLevel,
    }) async {
      final seen = <(String, TriageLevel, TriageLevel?)>[];
      engine = SyncEngine(
        db: db,
        api: Api(transport),
        connectivity: connectivity,
        onTriageMismatch: (id, l, s) => seen.add((id, l, s)),
      );

      final repo = PregnancyRepo(db, const NoopSyncKicker());
      const pregnancy = Pregnancy(id: 'pg1', patientId: 'p1', edd: '2026-12-06');
      final contact = AncContact(
        id: ancContactId('pg1', 4),
        pregnancyId: 'pg1',
        contactNo: 4,
        weekTarget: 30,
        dueAt: '2026-10-16',
        doneAt: '2026-09-18T05:00:00.000Z',
        triageLevel: local,
      );
      await repo.register(pregnancy, [contact]);
      await db.outboxDao.clear();
      await repo.recordContact(contact);

      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'applied',
                'row': {
                  ...FakeSyncTransport.applied(c),
                  'triageLevel': serverLevel,
                },
              },
          ];

      await engine.run();
      return seen;
    }

    test('the server value is applied and the difference is reported',
        () async {
      final seen = await pushContact(
        local: TriageLevel.green,
        serverLevel: 'red',
      );

      expect(seen, hasLength(1));
      expect(seen.single.$2, TriageLevel.green);
      expect(seen.single.$3, TriageLevel.red);

      final stored = await db.pregnanciesDao.findContactByNo('pg1', 4);
      expect(
        stored!.triageLevel,
        TriageLevel.red,
        reason: 'A.4: the server recomputes triage and its answer wins',
      );
    });

    test('agreement is silent', () async {
      final seen = await pushContact(
        local: TriageLevel.red,
        serverLevel: 'red',
      );

      expect(seen, isEmpty);
    });
  });

  group('the mutex and triggers', () {
    test('a second cycle is skipped while one is running', () async {
      await queuePatient();

      final first = engine.run();
      final second = await engine.run();
      await first;

      expect(second.skipped, isTrue);
    });

    test('a kick during a cycle is not lost', () async {
      // Dropping it would leave the health worker staring at a pending icon
      // until the next 60-second tick. The gate holds the cycle open so the
      // second write definitely arrives while the mutex is held.
      // `kick()` is ignored until the engine has started — an implicit trigger
      // before the PIN unlock would sync against a locked database.
      await engine.start();
      await queuePatient(id: 'p1');
      final gate = Completer<void>();
      transport.gate = gate;

      final cycle = engine.run();
      await pumpEventQueue();
      expect(transport.pushRequests, hasLength(1), reason: 'cycle is in flight');

      await queuePatient(id: 'p2');
      engine.kick();

      transport.gate = null;
      gate.complete();
      await cycle;

      expect(transport.pushRequests, hasLength(2));
      expect(
        (transport.pushRequests.last['changes'] as List).single['rowId'],
        'p2',
      );
      expect(await db.outboxDao.take(), isEmpty);
    });

    test('offline skips the cycle and sends nothing', () async {
      await queuePatient();
      connectivity.online = false;

      final outcome = await engine.run();

      expect(outcome.skipped, isTrue);
      expect(transport.pushRequests, isEmpty);
      expect(await db.outboxDao.take(), hasLength(1));
    });

    test('coming back online triggers a cycle', () async {
      connectivity = FakeConnectivity(online: false);
      engine = SyncEngine(
        db: db,
        api: Api(transport),
        connectivity: connectivity,
        period: const Duration(hours: 1),
      );
      await queuePatient();
      await engine.start();
      expect(transport.pushRequests, isEmpty);

      connectivity.online = true;
      await pumpEventQueue();

      expect(transport.pushRequests, hasLength(1));
      expect(await db.outboxDao.take(), isEmpty);
    });
  });

  group('failure', () {
    test('losing the network mid-cycle leaves everything queued', () async {
      await queuePatient();
      transport.offline = true;

      final outcome = await engine.run();

      expect(outcome.failedWithNetworkError, isTrue);
      expect(outcome.pushed, 0);
      expect(
        await db.outboxDao.take(),
        hasLength(1),
        reason: 'the op is still ours to send',
      );
      expect(await db.syncMetaDao.pullCursor(), SyncMetaDao.epoch);
    });

    test('the next cycle after a failure sends the same op', () async {
      await queuePatient();
      transport.offline = true;
      await engine.run();

      transport.offline = false;
      final outcome = await engine.run();

      expect(outcome.pushed, 1);
      expect(await db.outboxDao.take(), isEmpty);
    });
  });

  group('S17 actions', () {
    Future<String> queueRejected({int baseVersion = 0}) async {
      await queuePatient();
      if (baseVersion > 0) {
        await (db.update(db.outbox)).write(
          OutboxCompanion(baseVersion: Value(baseVersion)),
        );
      }
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'rejected',
                'error': {'code': 'RULE_VIOLATION', 'message': 'Nope'},
              },
          ];
      await engine.run();
      transport.onPush = FakeSyncTransport.defaultApplyAll;

      return (await db.outboxDao.watchFailed().first).single.opId;
    }

    test('retry clears the message and the next cycle sends it', () async {
      final opId = await queueRejected();
      // retry() kicks, and a kick needs a started engine.
      await engine.start();

      await engine.retry(opId);
      await pumpEventQueue();

      expect(await db.outboxDao.watchFailed().first, isEmpty);
      expect(await db.outboxDao.take(), isEmpty, reason: 'it went out');
    });

    test('discarding a create also deletes the local row', () async {
      // Spec §7. Leaving it would show a record that exists nowhere else and
      // will never sync.
      final opId = await queueRejected();

      await engine.discard(opId);

      expect(await db.outboxDao.findById(opId), isNull);
      expect(await db.patientsDao.findById('p1'), isNull);
    });

    test('discarding an edit keeps the row the server already has', () async {
      final opId = await queueRejected(baseVersion: 3);

      await engine.discard(opId);

      expect(await db.outboxDao.findById(opId), isNull);
      expect(
        await db.patientsDao.findById('p1'),
        isNotNull,
        reason: 'only the unsent change is dropped, not the record',
      );
    });

    test('discarding an unknown op is a no-op', () async {
      await engine.discard('nope');
      expect(await db.outboxDao.take(), isEmpty);
    });
  });

  group('status', () {
    test('it reports pending, then synced', () async {
      final seen = <SyncStatus>[];
      final subscription = engine.status.listen(seen.add);

      await queuePatient();
      await engine.start();
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen, isNotEmpty);
      expect(seen.any((s) => s.pending > 0), isTrue);
      expect(seen.last.pending, 0);
      expect(seen.last.chip, SyncChipState.synced);
      expect(seen.last.lastSyncAt, isNotNull);
    });

    test('a rejected op turns the chip to failed', () async {
      await queuePatient();
      transport.onPush = (changes) => [
            for (final c in changes)
              {
                'opId': c['opId'],
                'status': 'rejected',
                'error': {'code': 'RULE_VIOLATION', 'message': 'Nope'},
              },
          ];

      final seen = <SyncStatus>[];
      final subscription = engine.status.listen(seen.add);
      await engine.start();
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen.last.chip, SyncChipState.failed);
      expect(seen.last.errors.single.lastError, 'Nope');
    });

    test('offline shows the grey chip', () async {
      connectivity = FakeConnectivity(online: false);
      engine = SyncEngine(
        db: db,
        api: Api(transport),
        connectivity: connectivity,
        period: const Duration(hours: 1),
      );

      final seen = <SyncStatus>[];
      final subscription = engine.status.listen(seen.add);
      await engine.start();
      await pumpEventQueue();
      await subscription.cancel();

      expect(seen.last.online, isFalse);
      expect(seen.last.chip, SyncChipState.offline);
    });
  });

  test('a full offline-then-online round trip settles everything', () async {
    // Spec §17 case 3: add a visit in airplane mode, come back, it syncs.
    connectivity = FakeConnectivity(online: false);
    engine = SyncEngine(
      db: db,
      api: Api(transport),
      connectivity: connectivity,
      period: const Duration(hours: 1),
    );
    final repo = VisitRepo(db, engine);
    await engine.start();

    await repo.add(visit());
    await pumpEventQueue();
    expect((await db.visitsDao.findById('v1'))!.version, 0,
        reason: 'pending: not on the server yet');
    expect(await db.outboxDao.watchPendingCount().first, 1);

    connectivity.online = true;
    await pumpEventQueue();

    expect((await db.visitsDao.findById('v1'))!.version, 1);
    expect(await db.outboxDao.watchPendingCount().first, 0);
  });
}
