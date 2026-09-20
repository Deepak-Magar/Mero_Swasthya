import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/data/local/converters.dart';
import 'package:mero_swasthya/data/local/daos/sync_meta_dao.dart';
import 'package:mero_swasthya/data/repositories/document_repo.dart';
import 'package:mero_swasthya/data/repositories/patient_repo.dart';
import 'package:mero_swasthya/data/repositories/pregnancy_repo.dart';
import 'package:mero_swasthya/data/repositories/sync_kicker.dart';
import 'package:mero_swasthya/data/repositories/syncable_repo.dart';
import 'package:mero_swasthya/data/repositories/visit_repo.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

import '../support/transports.dart';

/// Spec §6.2: repositories are the only write path, and every local write is a
/// row plus an outbox op, committed together.
class RecordingKicker implements SyncKicker {
  int kicks = 0;

  @override
  void kick() => kicks++;
}

/// Exposes [SyncableRepo.writeAndEnqueue] so the invariant can be tested with a
/// deliberately invalid op.
class TestRepo extends SyncableRepo {
  const TestRepo(super.db, super.sync);
}

Patient buildPatient({
  String id = 'p1',
  String name = 'Sita Devi',
  int version = 0,
}) {
  return Patient(
    id: id,
    ownerUserId: 'u1',
    name: name,
    sex: Sex.female,
    dob: '1998-04-12',
    version: version,
  );
}

Visit buildVisit({String id = 'v1', String patientId = 'p1'}) {
  return Visit(
    id: id,
    patientId: patientId,
    visitAt: '2026-09-18T05:30:00.000Z',
    chiefComplaintCode: 'FEVER',
  );
}

void main() {
  late AppDatabase db;
  late RecordingKicker kicker;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    kicker = RecordingKicker();
  });
  tearDown(() => db.close());

  group('PatientRepo', () {
    late PatientRepo repo;
    late FlakyTransport transport;

    setUp(() {
      transport = FlakyTransport(MockApi(clock: () => DateTime.utc(2026, 9, 18)));
      repo = PatientRepo(db, kicker, Api(transport));
    });

    test('create writes the row at version 0 and queues one op', () async {
      await repo.create(buildPatient());

      final stored = await repo.findById('p1');
      expect(stored!.version, 0);
      expect(stored.name, 'Sita Devi');

      final ops = await db.outboxDao.take();
      expect(ops, hasLength(1));
      expect(ops.single.targetTable, 'patients');
      expect(ops.single.op, OutboxOp.upsert);
      expect(ops.single.rowId, 'p1');
      expect(ops.single.baseVersion, 0);
      expect(kicker.kicks, 1);
    });

    test('the payload drops the fields the server owns', () async {
      await repo.create(buildPatient());

      final payload = (await db.outboxDao.take()).single.payload;
      expect(payload, isNot(contains('version')));
      expect(payload, isNot(contains('updatedAt')));
      expect(payload, isNot(contains('deleted')));
      expect(payload['id'], 'p1');
      expect(payload['sex'], 'female', reason: 'wire string, not Dart name');
    });

    test('update takes baseVersion from the stored row, not the caller',
        () async {
      await repo.create(buildPatient());
      // A pull lands while an edit screen is open.
      await db.patientsDao.upsertFromServer(
        buildPatient(version: 4).toJson()..['updatedAt'] = '2026-09-18T06:00:00.000Z',
      );
      await db.outboxDao.clear();

      // The screen still holds the object it opened with, at version 0.
      await repo.update(buildPatient(name: 'Sita Devi Sharma'));

      final op = (await db.outboxDao.take()).single;
      expect(
        op.baseVersion,
        4,
        reason: 'a stale screen must not claim to be editing version 0',
      );
      expect((await repo.findById('p1'))!.name, 'Sita Devi Sharma');
    });

    test('softDelete keeps the row and hides it from the family list',
        () async {
      await repo.create(buildPatient());
      await repo.softDelete('p1');

      expect(await repo.findById('p1'), isNotNull);
      expect(await repo.watchFamily('u1').first, isEmpty);
    });

    test('refreshFromServer pulls the account patients into the database',
        () async {
      // Found on device: S06 read only the local database, so the seeded
      // records never appeared on a fresh install — spec S06 lists
      // "GET /patients (on refresh)" for exactly this.
      expect(await repo.watchFamily('u_0001').first, isEmpty);

      expect(await repo.refreshFromServer(), isTrue);

      final family = await repo.watchFamily('u_0001').first;
      expect(family.map((p) => p.name),
          containsAll(['Sita Chaudhary', 'Ram Bahadur Chaudhary']));
    });

    test('a refresh never clobbers a row with unsent local edits', () async {
      await repo.create(buildPatient(id: MockApi.sitaId, name: 'My edit'));

      await repo.refreshFromServer();

      expect(
        (await repo.findById(MockApi.sitaId))!.name,
        'My edit',
        reason: 'the queued op has not been sent yet',
      );
    });

    test('an offline refresh leaves the cached list alone', () async {
      await repo.refreshFromServer();
      final before = await repo.watchFamily('u_0001').first;

      transport.offline = true;
      expect(await repo.refreshFromServer(), isFalse);
      expect(await repo.watchFamily('u_0001').first, hasLength(before.length));
    });

    test('softDelete of an unknown id is a no-op', () async {
      await repo.softDelete('nope');
      expect(await db.outboxDao.take(), isEmpty);
    });

    group('granted patients', () {
      test('caching a granted patient never queues an op', () async {
        await repo.cacheGranted(
          buildPatient(id: 'p9', name: 'Kamala'),
          '2026-09-18T06:00:00.000Z',
        );

        expect(await db.outboxDao.take(), isEmpty);
        expect(kicker.kicks, 0);
      });

      test('watchGranted only returns grants that are still open', () async {
        await repo.cacheGranted(
          buildPatient(id: 'open'),
          '2026-09-18T06:00:00.000Z',
        );
        await repo.cacheGranted(
          buildPatient(id: 'closed'),
          '2026-09-18T05:00:00.000Z',
        );

        final visible = await repo
            .watchGranted(now: DateTime.utc(2026, 9, 18, 5, 30))
            .first;
        expect(visible.map((p) => p.id), ['open']);
      });

      test('watchAccessUntil reports the window S21 has to check', () async {
        // The row survives until the next sync tidies it, so the screen — not
        // the query that built the list an hour ago — is what has to decide
        // whether the window is still open. Found on the handset: with the
        // clock moved a day forward S21 still showed the whole record.
        await repo.create(buildPatient(id: 'mine'));
        await repo.cacheGranted(
          buildPatient(id: 'granted'),
          '2026-09-18T06:00:00.000Z',
        );

        expect(await repo.watchAccessUntil('mine').first, isNull);
        expect(
          await repo.watchAccessUntil('granted').first,
          DateTime.utc(2026, 9, 18, 6),
        );
      });

      test('purgeExpiredGrants drops closed grants and leaves own family',
          () async {
        await repo.create(buildPatient(id: 'mine'));
        await repo.cacheGranted(
          buildPatient(id: 'closed'),
          '2026-09-18T05:00:00.000Z',
        );

        final removed =
            await repo.purgeExpiredGrants(now: DateTime.utc(2026, 9, 18, 5, 30));

        expect(removed, 1);
        expect(await repo.findById('mine'), isNotNull);
        expect(await repo.findById('closed'), isNull);
      });

      test('a pulled row does not wipe access_until', () async {
        // The whole reason mappers leave device-only columns absent.
        await repo.cacheGranted(
          buildPatient(id: 'p9'),
          '2026-09-18T06:00:00.000Z',
        );

        await db.patientsDao
            .upsertFromServer(buildPatient(id: 'p9', version: 2).toJson());

        final visible = await repo
            .watchGranted(now: DateTime.utc(2026, 9, 18, 5, 30))
            .first;
        expect(visible.map((p) => p.id), ['p9']);
      });
    });
  });

  group('VisitRepo', () {
    late VisitRepo repo;
    setUp(() => repo = VisitRepo(db, kicker));

    test('add queues an append-only op at baseVersion 0', () async {
      await repo.add(buildVisit());

      final op = (await db.outboxDao.take()).single;
      expect(op.targetTable, 'visits');
      expect(op.baseVersion, 0);
      expect(await repo.findById('v1'), isNotNull);
    });

    test('a correction is a new row that points at the original', () async {
      await repo.add(buildVisit());
      await repo.supersede(buildVisit(id: 'v2'), 'v1');

      final corrected = await repo.findById('v2');
      expect(corrected!.supersedesId, 'v1');
      expect(
        await repo.findById('v1'),
        isNotNull,
        reason: 'the original stays in the record',
      );
      expect((await repo.watchByPatient('p1').first), hasLength(2));
    });

    test('nested objects survive the payload round trip', () async {
      await repo.add(
        buildVisit().copyWith(
          vitals: const Vitals(bpSys: 150, bpDia: 100),
          prescriptions: const [
            Prescription(
              id: 'rx1',
              drugCode: 'PARA500',
              dose: '500mg',
              frequency: PrescriptionFrequency.tds,
              durationDays: 3,
            ),
          ],
        ),
      );

      final payload = (await db.outboxDao.take()).single.payload;
      expect((payload['vitals'] as Map)['bpSys'], 150);
      expect((payload['prescriptions'] as List).single['frequency'], 'TDS');
    });
  });

  group('DocumentRepo', () {
    late DocumentRepo repo;
    setUp(() => repo = DocumentRepo(db, kicker));

    Document buildDocument({String id = 'd1'}) => Document(
          id: id,
          patientId: 'p1',
          type: DocumentType.prescription,
          title: 'Old prescription',
          takenAt: '2026-09-18T04:00:00.000Z',
        );

    test('capture stores the file path and queues only the metadata', () async {
      await repo.capture(buildDocument(), '/data/app/d1.jpg');

      final op = (await db.outboxDao.take()).single;
      expect(op.targetTable, 'documents');
      expect(
        op.payload,
        isNot(contains('localPath')),
        reason: 'the path is device-only and means nothing to the server',
      );

      final pending = await repo.pendingUploads();
      expect(pending.single.localPath, '/data/app/d1.jpg');
      expect(pending.single.uploadAttempts, 0);
    });

    test('a document runs out of upload retries after five failures', () async {
      await repo.capture(buildDocument(), '/data/app/d1.jpg');

      for (var i = 0; i < 5; i++) {
        await repo.recordUploadFailure('d1');
      }

      expect(await repo.pendingUploads(), isEmpty);
      expect((await repo.watchStuckUploads().first).single.id, 'd1');
    });

    test('markUploaded stops the worker but keeps the file on disk', () async {
      // The local copy is what draws the thumbnail offline; the status alone
      // is enough to dequeue.
      await repo.capture(buildDocument(), '/data/app/d1.jpg');
      await repo.markUploaded('d1', downloadUrl: 'https://cdn/d1.jpg');

      final stored = await repo.findById('d1');
      expect(stored!.status, DocumentStatus.uploaded);
      expect(stored.downloadUrl, 'https://cdn/d1.jpg');
      expect(await repo.pendingUploads(), isEmpty);

      final row = await db.documentsDao.watchRowsByPatient('p1').first;
      expect(
        row.single.localPath,
        '/data/app/d1.jpg',
        reason: 'the picture must still render with no network',
      );
    });

    test('a metadata edit does not disturb a queued upload', () async {
      await repo.capture(buildDocument(), '/data/app/d1.jpg');
      await repo.updateMeta(buildDocument().copyWith(title: 'Lab report'));

      final pending = await repo.pendingUploads();
      expect(pending.single.localPath, '/data/app/d1.jpg');
      expect(pending.single.title, 'Lab report');
    });
  });

  group('PregnancyRepo', () {
    late PregnancyRepo repo;
    setUp(() => repo = PregnancyRepo(db, kicker));

    Pregnancy buildPregnancy({int version = 0}) => Pregnancy(
          id: 'pg1',
          patientId: 'p1',
          lmp: '2026-03-01',
          edd: '2026-12-06',
          version: version,
        );

    List<AncContact> buildSchedule() {
      const weeks = [12, 20, 26, 30, 34, 36, 38, 40];
      return [
        for (var i = 0; i < weeks.length; i++)
          AncContact(
            id: 'pg1-contact-${i + 1}',
            pregnancyId: 'pg1',
            contactNo: i + 1,
            weekTarget: weeks[i],
            dueAt: '2026-0${(i % 9) + 1}-01T00:00:00.000Z',
          ),
      ];
    }

    test('register stores the schedule but queues only the pregnancy',
        () async {
      await repo.register(buildPregnancy(), buildSchedule());

      expect(await repo.watchContacts('pg1').first, hasLength(8));

      final ops = await db.outboxDao.take();
      expect(ops, hasLength(1));
      expect(ops.single.targetTable, 'pregnancies');
      expect(
        ops.single.payload,
        isNot(contains('gestationalAgeDays')),
        reason: 'computed on read by the server, never stored or sent',
      );
      expect(ops.single.payload, isNot(contains('nextContact')));
    });

    test('recording a contact queues that contact alone', () async {
      await repo.register(buildPregnancy(), buildSchedule());
      await db.outboxDao.clear();

      final contact = (await repo.findContactByNo('pg1', 1))!;
      await repo.recordContact(
        contact.copyWith(
          doneAt: '2026-06-01T04:00:00.000Z',
          findings: const Findings(bpSys: 150, bpDia: 100),
          triageLevel: TriageLevel.red,
          triageReasons: const ['bp_high'],
        ),
      );

      final op = (await db.outboxDao.take()).single;
      expect(op.targetTable, 'anc_contacts');
      expect(op.rowId, 'pg1-contact-1');
      expect(op.payload['triageLevel'], 'red');

      final stored = await repo.findContactByNo('pg1', 1);
      expect(stored!.triageLevel, TriageLevel.red);
      expect(stored.findings!.bpSys, 150);
    });

    test('recordDelivery queues the delivery before the pregnancy', () async {
      await repo.register(buildPregnancy(), buildSchedule());
      await db.outboxDao.clear();

      final pregnancy = (await repo.findById('pg1'))!;
      await repo.recordDelivery(
        const Delivery(
          id: 'del1',
          pregnancyId: 'pg1',
          deliveredAt: '2026-12-01T02:00:00.000Z',
          place: DeliveryPlace.birthingCentre,
          mode: DeliveryMode.normal,
          outcome: DeliveryOutcome.liveBirth,
        ),
        pregnancy.copyWith(status: PregnancyStatus.delivered),
      );

      final ops = await db.outboxDao.take();
      expect(
        ops.map((op) => op.targetTable),
        ['deliveries', 'pregnancies'],
        reason: 'the pregnancy cannot end before the delivery exists',
      );
      expect(
        (await repo.watchBundle('pg1').first).pregnancy.status,
        PregnancyStatus.delivered,
      );
    });

    test('the bundle repaints when any of its four tables changes', () async {
      await repo.register(buildPregnancy(), buildSchedule());

      final bundles = <PregnancyBundle>[];
      final subscription = repo.watchBundle('pg1').listen(bundles.add);
      await pumpEventQueue();

      final contact = (await repo.findContactByNo('pg1', 1))!;
      await repo.recordContact(
        contact.copyWith(doneAt: '2026-06-01T04:00:00.000Z'),
      );
      await pumpEventQueue();

      await subscription.cancel();

      expect(bundles.length, greaterThanOrEqualTo(2));
      expect(bundles.last.ancContacts.first.doneAt, '2026-06-01T04:00:00.000Z');
    });
  });

  group('the write invariant', () {
    test('a failed enqueue rolls the row back', () async {
      // 'reminders' is server-owned, so enqueue asserts. The row written just
      // before it must not survive, or the app would show data the server will
      // never hear about.
      final testRepo = TestRepo(db, kicker);

      await expectLater(
        testRepo.writeAndEnqueue(
          write: () => db.patientsDao.upsert(buildPatient()),
          table: 'reminders',
          rowId: 'p1',
          baseVersion: 0,
          payload: const {},
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(await db.patientsDao.findById('p1'), isNull);
      expect(kicker.kicks, 0, reason: 'nothing was queued, so nothing to send');
    });

    test('the kick happens after the row is durable', () async {
      final repo = PatientRepo(db, kicker, Api(MockApi()));
      expect(kicker.kicks, 0);

      await repo.create(buildPatient());

      expect(kicker.kicks, 1);
      expect(await repo.findById('p1'), isNotNull);
      expect(await db.outboxDao.take(), hasLength(1));
    });
  });

  group('SyncMetaDao', () {
    test('the device id is generated once and then reused', () async {
      final first = await db.syncMetaDao.deviceId();
      final second = await db.syncMetaDao.deviceId();

      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('the pull cursor starts at the epoch', () async {
      expect(await db.syncMetaDao.pullCursor(), SyncMetaDao.epoch);

      await db.syncMetaDao.setPullCursor('2026-09-18T05:00:00.000Z');
      expect(await db.syncMetaDao.pullCursor(), '2026-09-18T05:00:00.000Z');
    });

    test('signing in as somebody else replaces the single user row', () async {
      await db.syncMetaDao.setCurrentUser(
        const User(
          id: 'u1',
          phone: '9800000001',
          role: UserRole.patient,
          name: 'Sita',
          createdAt: '2026-09-18T00:00:00.000Z',
        ),
      );
      await db.syncMetaDao.setCurrentUser(
        const User(
          id: 'u2',
          phone: '9800000002',
          role: UserRole.provider,
          name: 'HA Ghorahi',
          createdAt: '2026-09-18T00:00:00.000Z',
        ),
      );

      final user = await db.syncMetaDao.currentUser();
      expect(user!.id, 'u2');
      expect(user.role, UserRole.provider);
    });
  });

  group('CacheDao', () {
    test('replacing reminders drops ones the server cancelled', () async {
      Reminder reminder(String id) => Reminder(
            id: id,
            patientId: 'p1',
            kind: ReminderKind.ancDue,
            dueAt: '2026-10-01T03:00:00.000Z',
          );

      await db.cacheDao.replaceReminders('p1', [reminder('r1'), reminder('r2')]);
      await db.cacheDao.replaceReminders('p1', [reminder('r1')]);

      expect(
        (await db.cacheDao.watchReminders('p1').first).map((r) => r.id),
        ['r1'],
      );
    });

    test('audit entries merge instead of replacing', () async {
      AuditEntry entry(String id, String at) => AuditEntry(
            id: id,
            patientId: 'p1',
            actorUserId: 'u2',
            action: AuditAction.recordViewed,
            at: at,
          );

      await db.cacheDao.upsertAudit([entry('a1', '2026-09-18T01:00:00.000Z')]);
      await db.cacheDao.upsertAudit([entry('a2', '2026-09-18T02:00:00.000Z')]);

      expect(
        (await db.cacheDao.watchAudit('p1').first).map((e) => e.id),
        ['a2', 'a1'],
        reason: 'newest first',
      );
    });

    test('codelists are looked up by kind and code', () async {
      await db.cacheDao.upsertCodelist(const [
        CodeListItem(
          kind: CodeListKind.drug,
          code: 'IFA',
          labelEn: 'Iron folic acid',
          labelNp: 'आइरन फोलिक एसिड',
        ),
      ]);

      final item = await db.cacheDao.findCode(CodeListKind.drug, 'IFA');
      expect(item!.labelNp, 'आइरन फोलिक एसिड');
      expect(await db.cacheDao.findCode(CodeListKind.diagnosis, 'IFA'), isNull);
      expect(await db.cacheDao.codelistCount(), 1);
    });
  });

  test('clearAll wipes the outbox too, so sign-out leaves nothing queued',
      () async {
    final repo = PatientRepo(db, kicker, Api(MockApi()));
    await repo.create(buildPatient());
    await db.patientsDao
        .upsert(buildPatient(id: 'p2'), accessUntil: const Value('x'));

    await db.clearAll();

    expect(await db.outboxDao.take(), isEmpty);
    expect(await repo.findById('p1'), isNull);
  });
}
