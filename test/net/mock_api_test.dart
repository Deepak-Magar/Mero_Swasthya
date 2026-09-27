import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/errors/app_error.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/data/remote/api/api.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

/// Spec §15. The point of these tests is not the mock's own behaviour but the
/// shapes: every response is parsed by the same freezed models the real backend
/// will feed, so a mock that drifts from Part A fails here rather than on demo
/// day.
void main() {
  late DateTime now;
  late MockApi mock;
  late Api api;

  setUp(() {
    now = DateTime.utc(2026, 9, 18, 5);
    mock = MockApi(clock: () => now);
    api = Api(mock);
  });

  group('auth', () {
    test('the demo OTP is accepted and anything else is a field error',
        () async {
      final requested = await api.auth.requestOtp('+9779801000001');
      expect(requested.demoOtp, MockApi.demoOtp);

      final verified = await api.auth.verifyOtp(
        phone: '+9779801000001',
        otp: MockApi.demoOtp,
      );
      expect(verified.tempToken, isNotEmpty);

      await expectLater(
        api.auth.verifyOtp(phone: '+9779801000001', otp: '000000'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', AppError.validationError)
              .having((e) => e.fieldErrors.keys, 'fields', contains('otp')),
        ),
      );
    });

    test('a brand-new phone has no PIN, so S03 routes to Set PIN', () async {
      // Found on device: the mock answered `hasPin: true` to the very first
      // verification, so a fresh install skipped S05 entirely and §17 item 2
      // ("fresh install -> OTP -> set PIN") could not be walked.
      final verified = await api.auth.verifyOtp(
        phone: '+9779801000001',
        otp: MockApi.demoOtp,
      );

      expect(verified.hasPin, isFalse);
      expect(verified.isNewUser, isTrue);
    });

    test('once a PIN is set the same phone reports hasPin', () async {
      final first = await api.auth.verifyOtp(
        phone: '+9779801000001',
        otp: MockApi.demoOtp,
      );
      await api.auth.setPin(
        tempToken: first.tempToken,
        pin: '4321',
        name: 'Sita Chaudhary',
      );

      final second = await api.auth.verifyOtp(
        phone: '+9779801000001',
        otp: MockApi.demoOtp,
      );
      expect(second.hasPin, isTrue);
      expect(second.isNewUser, isFalse);
    });

    test('any four-digit PIN logs in and returns a full session', () async {
      final session = await api.auth.loginWithPin(
        phone: '+9779801000001',
        pin: '4321',
      );

      expect(session.accessToken, isNotEmpty);
      expect(session.refreshToken, isNotEmpty);
      expect(session.user.role, UserRole.patient);
      expect(session.user.name, 'Sita Chaudhary');
    });

    test('a PIN of the wrong length is rejected', () async {
      await expectLater(
        api.auth.loginWithPin(phone: '+9779801000001', pin: '12'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'VALIDATION_ERROR')),
      );
    });

    test('the demo invite codes upgrade the role and attach a facility',
        () async {
      final provider =
          await api.auth.activateProvider(MockApi.providerInviteCode);
      expect(provider.role, UserRole.provider);
      expect(provider.facilityName, 'Ghorahi Health Post');

      final fchv = await api.auth.activateProvider(MockApi.fchvInviteCode);
      expect(fchv.role, UserRole.fchv);

      await expectLater(
        api.auth.activateProvider('NOPE'),
        throwsA(isA<AppError>()),
      );
    });

    test('/me reflects the activated role', () async {
      await api.auth.activateProvider(MockApi.providerInviteCode);
      expect((await api.auth.me()).role, UserRole.provider);
    });

    test('an activation is reported so it can outlive this instance', () async {
      String? remembered;
      final mock = MockApi(onActivated: (role) => remembered = role);

      await Api(mock).auth.activateProvider(MockApi.providerInviteCode);

      expect(remembered, 'provider');
    });

    test('a remembered role is restored by the next instance', () async {
      // Found on the phone: S18 activated, the app was relaunched, and the app
      // bar was back to "I am a health worker". A fresh MockApi had never heard
      // of the activation, so `GET /me` handed the device the seeded patient
      // and overwrote the role it had already stored.
      final relaunched = Api(MockApi(activatedRole: 'provider'));

      final me = await relaunched.auth.me();
      expect(me.role, UserRole.provider);
      expect(me.facilityName, 'Ghorahi Health Post');
    });

    test('restoring a role does not re-check the invite code', () async {
      // It was validated when the user typed it; the mock is only replaying.
      final relaunched = Api(MockApi(activatedRole: 'fchv'));

      expect((await relaunched.auth.me()).role, UserRole.fchv);
    });
  });

  group('patients', () {
    // Tier 2 seeds three more women the health post follows through grants.
    // They must not appear here: `GET /patients` is S06's family list, and the
    // dashboard reaches them through the sync pull instead.
    test('the seed holds Sita, Ram and Aarav', () async {
      // Aarav is the Tier 3 addition: an under-five so the child-health module
      // has an immunisation card and a growth chart to show. The three women
      // the S19 dashboard counts are *not* here — they are reached through
      // grants and arrive on the sync pull, not on S06's family list.
      final patients = await api.patients.list();

      expect(patients.map((p) => p.name), [
        'Sita Chaudhary',
        'Ram Bahadur Chaudhary',
        'Aarav Chaudhary',
      ]);
      expect(patients.first.sex, Sex.female);
      expect(
        patients.firstWhere((p) => p.id == MockApi.ramId).chronicConditions,
        ['E11'],
      );
    });

    test('creating with the same id twice returns the existing row', () async {
      // The idempotency the outbox depends on when it replays an op.
      final first = await api.patients.create({
        'id': 'p_new',
        'name': 'Kamala',
        'sex': 'female',
        'dob': '1990-01-01',
      });
      final second = await api.patients.create({
        'id': 'p_new',
        'name': 'Someone else',
        'sex': 'female',
        'dob': '1990-01-01',
      });

      expect(second.name, 'Kamala');
      expect(second.version, first.version);
      expect(await api.patients.list(), hasLength(4));
    });

    test('a patch bumps the version', () async {
      final updated =
          await api.patients.update(MockApi.sitaId, {'bloodGroup': 'A+'});

      expect(updated.bloodGroup, 'A+');
      expect(updated.version, 2);
    });

    test('the detail response parses into PatientDetail with its summary',
        () async {
      final detail = await api.patients.detail(MockApi.ramId);

      expect(detail.patient.name, 'Ram Bahadur Chaudhary');
      expect(detail.summary.activeProblems.single.code, 'E11');
      expect(detail.summary.lastVisitAt, isNotNull);
    });

    test('Ram has the seeded diabetes visit with its prescription', () async {
      final visits = await api.patients.visits(MockApi.ramId);

      expect(visits, hasLength(1));
      expect(visits.single.diagnosisCodes, ['E11']);
      expect(visits.single.vitals?.bpSys, 138);
      expect(
        visits.single.prescriptions.single.frequency,
        PrescriptionFrequency.bd,
      );
    });

    test('a new visit comes back with the provider filled in from the token',
        () async {
      await api.auth.activateProvider(MockApi.providerInviteCode);

      final visit = await api.patients.addVisit(MockApi.sitaId, {
        'id': 'v_new',
        'visitAt': now.toIso8601String(),
        'chiefComplaintCode': 'FEVER',
      });

      expect(visit.providerName, isNotEmpty);
      expect(visit.facilityName, 'Ghorahi Health Post');
      expect(visit.version, 1);
    });

    test('the timeline merges visits and the pregnancy, newest first',
        () async {
      final page = await api.patients.timeline(MockApi.sitaId);

      expect(page.items, isNotEmpty);
      expect(page.items.first.kind, TimelineKind.pregnancyRegistered);
      final times = page.items.map((i) => i.at).toList();
      expect(times, List.of(times)..sort((a, b) => b.compareTo(a)));
    });

    test('the two seeded reminders are attached to Sita', () async {
      final reminders = await api.patients.reminders(MockApi.sitaId);

      expect(reminders, hasLength(2));
      expect(reminders.first.kind, ReminderKind.ancDue);
      expect(reminders.first.messageNp, isNotEmpty);
    });
  });

  group('grants', () {
    test('a fresh grant redeems into the full bundle', () async {
      final created = await api.grants.create(patientId: MockApi.sitaId);
      expect(created.qrPayload, startsWith(GrantsApi.qrPrefix));

      final redeemed = await api.grants.redeem(created.qrPayload);

      expect(redeemed.patient.id, MockApi.sitaId);
      expect(redeemed.grant.accessUntil, isNotNull);
      expect(redeemed.pregnancy, isNotNull);
      expect(redeemed.ancContacts, hasLength(8));
      expect(redeemed.timeline, isNotEmpty);
    });

    test('a grant older than ten minutes is expired', () async {
      final created = await api.grants.create(patientId: MockApi.sitaId);

      now = now.add(const Duration(minutes: 11));

      await expectLater(
        api.grants.redeem(created.qrPayload),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.grantExpired),
        ),
      );
    });

    test('a revoked grant cannot be redeemed', () async {
      final created = await api.grants.create(patientId: MockApi.sitaId);
      final revoked = await api.grants.revoke(created.grant.id);

      expect(revoked.revokedAt, isNotNull);
      await expectLater(
        api.grants.redeem(created.qrPayload),
        throwsA(isA<AppError>()),
      );
    });

    test('a code this instance never issued is adopted for the demo', () async {
      // DEMO: mock only. Two phones each run their own MockApi, so the code
      // the patient's phone draws is unknown to the provider's. Without this
      // the one moment the demo exists to show dies on "Unknown QR code".
      const foreign =
          'SWC1:mock_grant_3f2504e0-4f89-41d3-9a0c-0305e82c3301';

      final redeemed = await api.grants.redeem(foreign);

      expect(redeemed.patient.id, MockApi.sitaId);
      expect(redeemed.patient.allergies, contains('sulpha'));
      expect(redeemed.grant.accessUntil, isNotNull);
      expect(
        DateTime.parse(redeemed.grant.accessUntil!)
            .difference(now.toUtc())
            .inHours,
        24,
      );
      expect(redeemed.pregnancy, isNotNull);
      expect(redeemed.ancContacts, hasLength(8));
      expect(redeemed.timeline, isNotEmpty);

      final audit = await api.patients.audit(MockApi.sitaId);
      expect(
        audit.map((a) => a.action),
        contains(AuditAction.grantRedeemed),
      );
    });

    test('an adopted code is still one-shot and still expires', () async {
      const foreign =
          'SWC1:mock_grant_9b2c1d44-1111-4222-8333-444455556666';
      await api.grants.redeem(foreign);

      // Adopted or not, it is a grant now: the ten-minute window applies.
      now = now.add(const Duration(minutes: 11));
      await expectLater(
        api.grants.redeem(foreign),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.grantExpired),
        ),
      );
    });

    test('leniency does not extend to payloads that are not grant codes',
        () async {
      for (final bad in [
        'HELLO',
        'SWC1:HELLO',
        'SWC1:mock_grant_not-a-uuid',
        // The right shape, but without the prefix it is not a Swasthya code.
        'mock_grant_3f2504e0-4f89-41d3-9a0c-0305e82c3301',
        'SWC1:mock_grant_3f2504e0-4f89-41d3-9a0c-0305e82c33',
      ]) {
        await expectLater(
          api.grants.redeem(bad),
          throwsA(
            isA<AppError>().having((e) => e.code, 'code', 'NOT_FOUND'),
          ),
          reason: bad,
        );
      }
    });

    test('an unknown QR is a 404 rather than a crash', () async {
      await expectLater(
        api.grants.redeem('SWC1:not_a_real_token'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });

    test('redeeming writes an audit entry the owner can see', () async {
      final created = await api.grants.create(patientId: MockApi.sitaId);
      await api.grants.redeem(created.qrPayload);

      final audit = await api.patients.audit(MockApi.sitaId);
      expect(
        audit.map((e) => e.action),
        containsAll([AuditAction.grantCreated, AuditAction.grantRedeemed]),
      );
    });
  });

  group('maternal', () {
    test('the seeded pregnancy has eight contacts with deterministic ids',
        () async {
      final bundle = await api.pregnancies.find(MockApi.pregnancyId);

      expect(bundle.ancContacts, hasLength(8));
      expect(
        bundle.ancContacts.map((c) => c.weekTarget),
        MockApi.ancScheduleWeeks,
      );
      // The ids the app derives locally must be the ids the server uses.
      for (final contact in bundle.ancContacts) {
        expect(contact.id, ancContactId(MockApi.pregnancyId, contact.contactNo));
      }
      expect(bundle.delivery, isNull);
    });

    test('registering for a male patient is a rule violation', () async {
      await expectLater(
        api.pregnancies.register(MockApi.ramId, const {'lmp': '2026-02-20'}),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.ruleViolation),
        ),
      );
    });

    test('EDD is derived from LMP when it is not supplied', () async {
      final created = await api.pregnancies.register(MockApi.sitaId, const {
        'id': 'pg_second',
        'lmp': '2026-02-20',
      });

      expect(created.pregnancy.edd, '2026-11-27');
      expect(created.ancContacts, hasLength(8));
    });

    test('a contact with a high BP comes back red with a referral facility',
        () async {
      final result = await api.pregnancies.recordContact(
        MockApi.pregnancyId,
        4,
        {
          'doneAt': now.toIso8601String(),
          'findings': {'bpSys': 150, 'bpDia': 95, 'hbGdl': 9.2},
          'dangerSigns': ['SEVERE_HEADACHE_BLURRED_VISION'],
        },
      );

      expect(result.ancContact.triageLevel, TriageLevel.red);
      expect(result.ancContact.triageReasons, contains('bp_high'));
      expect(result.nearestReferral, isNotNull);
      expect(result.ancContact.version, 2);
    });

    test('a normal contact is green with no referral', () async {
      final result = await api.pregnancies.recordContact(
        MockApi.pregnancyId,
        1,
        {
          'findings': {'bpSys': 110, 'bpDia': 70, 'hbGdl': 11.5},
          'dangerSigns': <String>[],
        },
      );

      expect(result.ancContact.triageLevel, TriageLevel.green);
      expect(result.ancContact.triageReasons, isEmpty);
      expect(result.nearestReferral, isNull);
    });

    test('a contact number outside 1..8 is a rule violation', () async {
      await expectLater(
        api.pregnancies.recordContact(MockApi.pregnancyId, 9, const {}),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.ruleViolation),
        ),
      );
    });

    test('a delivery closes the pregnancy and a second one is refused',
        () async {
      final result = await api.pregnancies.recordDelivery(
        MockApi.pregnancyId,
        {
          'id': 'dl_0001',
          'deliveredAt': now.toIso8601String(),
          'place': 'hospital',
          'mode': 'normal',
          'outcome': 'live_birth',
          'babyWeightKg': 2.9,
          'babySex': 'female',
        },
      );

      expect(result.pregnancy.status, PregnancyStatus.delivered);
      expect(result.delivery.outcome, DeliveryOutcome.liveBirth);
      expect(result.delivery.babySex, Sex.female);

      await expectLater(
        api.pregnancies.recordDelivery(MockApi.pregnancyId, const {}),
        throwsA(
          isA<AppError>().having((e) => e.code, 'code', AppError.ruleViolation),
        ),
      );
    });

    test('a patch bumps the version and keeps the birth plan', () async {
      final updated = await api.pregnancies.update(
        MockApi.pregnancyId,
        version: 1,
        changes: const {
          'birthPlan': {
            'facilityId': 'f_0002',
            'facilityName': 'Rapti Provincial Hospital',
            'transport': "Neighbour's jeep",
            'moneySaved': true,
          },
        },
      );

      expect(updated.version, 2);
      expect(updated.birthPlan?.facilityName, 'Rapti Provincial Hospital');
      expect(updated.birthPlan?.moneySaved, isTrue);
    });
  });

  group('documents', () {
    Future<PresignResult> presign() => api.documents.presign(
          id: 'd_0001',
          patientId: MockApi.sitaId,
          type: 'discharge',
          title: 'Discharge sheet',
          takenAt: '2026-07-02',
          contentType: 'image/jpeg',
          sizeBytes: 240000,
        );

    test('the three-step handshake ends with an uploaded document', () async {
      final presigned = await presign();
      expect(presigned.document.status, DocumentStatus.pendingUpload);
      expect(presigned.uploadHeaders['Content-Type'], 'image/jpeg');

      await api.documents.upload(presigned, bytes: const [1, 2, 3]);
      final completed = await api.documents.complete('d_0001');

      expect(completed.status, DocumentStatus.uploaded);
      expect(completed.downloadUrl, isNotNull);
      expect(completed.version, 2);
    });

    test('summarize only queues the job', () async {
      await presign();
      final queued = await api.documents.summarize('d_0001');

      expect(queued.aiSummaryStatus, AiSummaryStatus.queued);
      expect(queued.aiSummary, isNull);
    });

    test('an unknown document id is a 404', () async {
      await expectLater(
        api.documents.find('nope'),
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'NOT_FOUND')),
      );
    });
  });

  group('sync', () {
    SyncChange change(
      String opId, {
      String table = 'visits',
      String rowId = 'v_sync',
      int baseVersion = 0,
      Map<String, dynamic>? payload,
    }) =>
        SyncChange(
          opId: opId,
          table: table,
          op: 'upsert',
          rowId: rowId,
          baseVersion: baseVersion,
          payload: payload ??
              {
                'patientId': MockApi.sitaId,
                'visitAt': '2026-09-18T05:30:00.000Z',
                'chiefComplaintCode': 'FEVER',
              },
        );

    test('a create is applied at version 1', () async {
      final response = await api.sync.push(
        deviceId: 'dev_1',
        changes: [change('op_1')],
      );

      final result = response.results.single;
      expect(result.status, SyncOpStatus.applied);
      expect(result.row!['version'], 1);
      expect(result.row!['id'], 'v_sync');
      expect(response.serverTime, isNotEmpty);
    });

    test('replaying the same opId answers duplicate, not a second row',
        () async {
      await api.sync.push(deviceId: 'dev_1', changes: [change('op_1')]);
      final replay =
          await api.sync.push(deviceId: 'dev_1', changes: [change('op_1')]);

      expect(replay.results.single.status, SyncOpStatus.duplicate);
      expect(await api.patients.visits(MockApi.sitaId), hasLength(1));
    });

    test('a stale baseVersion answers conflict and carries the current row',
        () async {
      await api.sync.push(deviceId: 'dev_1', changes: [change('op_1')]);

      final conflicted = await api.sync.push(
        deviceId: 'dev_1',
        changes: [change('op_2', baseVersion: 0)],
      );

      final result = conflicted.results.single;
      expect(result.status, SyncOpStatus.conflict);
      expect(result.current!['version'], 1);
    });

    test('a server-owned table is rejected with a reason', () async {
      final response = await api.sync.push(
        deviceId: 'dev_1',
        changes: [change('op_1', table: 'reminders')],
      );

      final result = response.results.single;
      expect(result.status, SyncOpStatus.rejected);
      expect(result.error!.message, contains('reminders'));
    });

    test('a batch reports per-change results in order', () async {
      final response = await api.sync.push(
        deviceId: 'dev_1',
        changes: [
          change('op_1', rowId: 'v_a'),
          change('op_2', table: 'reminders', rowId: 'r_a'),
          change('op_3', rowId: 'v_b'),
        ],
      );

      expect(
        response.results.map((r) => r.status),
        [SyncOpStatus.applied, SyncOpStatus.rejected, SyncOpStatus.applied],
      );
    });

    test('the first pull carries the whole visible record', () async {
      // A.4: "All rows changed since cursor for the patients this user may
      // see". A fresh install holds nothing, so this one call has to deliver
      // the pregnancy, its contacts, the visits and the documents.
      final pulled = await api.sync.pull(
        since: '1970-01-01T00:00:00.000Z',
        deviceId: 'dev_1',
      );

      final tables = pulled.changes.map((c) => c.table).toSet();
      expect(
        tables,
        containsAll(['patients', 'pregnancies', 'anc_contacts', 'visits',
            'documents']),
      );
      expect(pulled.hasMore, isFalse);
      expect(pulled.cursor, isNotEmpty);
    });

    test('changes come back in updatedAt order', () async {
      // The cursor advances past what it returned, so out-of-order rows would
      // be skipped for good.
      final pulled = await api.sync.pull(
        since: '1970-01-01T00:00:00.000Z',
        deviceId: 'dev_1',
      );

      final times = [
        for (final change in pulled.changes) '${change.row['updatedAt']}',
      ];
      expect(times, List.of(times)..sort());
    });

    test('pulling again from the new cursor returns nothing', () async {
      final first = await api.sync.pull(
        since: '1970-01-01T00:00:00.000Z',
        deviceId: 'dev_1',
      );

      final second =
          await api.sync.pull(since: first.cursor, deviceId: 'dev_1');

      expect(second.changes, isEmpty);
      expect(second.hasMore, isFalse);
    });
  });

  group('reference data', () {
    test('config reports the flags the app keys features off', () async {
      final config = await api.reference.config();

      expect(config.smsMode, 'mock');
      // Tier 2 turned this on: S10's "Draft summary (AI)" button is hidden
      // unless the server says it can answer `POST /documents/:id/summarize`,
      // so a mock that reports false makes the feature undemonstrable.
      expect(config.aiSummaryEnabled, isTrue);
      expect(config.otpDemo, isTrue);
      expect(config.rulesVersion, MockApi.configVersion);

      // Tier 3 integrations. False, and honestly so: none of these has a
      // government API to talk to. The Settings rows say what each one would do
      // and the Connect button is disabled. Flipping one of these on is what
      // lights the row up, with no app change.
      expect(config.nidEnabled, isFalse);
      expect(config.hmisExportEnabled, isFalse);
      expect(config.councilVerifyEnabled, isFalse);
    });

    test('codelists can be fetched whole or one kind at a time', () async {
      final all = await api.reference.codelists();
      expect(all.items.length, greaterThan(1));
      expect(all.version, MockApi.configVersion);

      final drugs = await api.reference.codelists(kind: CodeListKind.drug);
      expect(drugs.items.map((i) => i.kind), everyElement(CodeListKind.drug));
      expect(drugs.items.single.labelNp, isNotEmpty);
    });

    test('nearby facilities can be filtered to birthing centres', () async {
      final all = await api.reference.nearbyFacilities(lat: 28.03, lng: 82.49);
      expect(all, hasLength(2));
      expect(all.first.distanceKm, isNotNull);

      final birthing = await api.reference.nearbyFacilities(
        lat: 28.03,
        lng: 82.49,
        birthingOnly: true,
      );
      expect(birthing.single.name, 'Rapti Provincial Hospital');
      expect(birthing.single.type, FacilityType.hospital);
    });

    test('the demo SMS panel returns the two seeded messages', () async {
      final messages = await api.reference.demoSms();

      expect(messages, hasLength(2));
      expect(messages.first.to, '+9779801000009');
      expect(messages.first.text, isNotEmpty);
    });

    test('rules come back raw, with a version to compare against the asset',
        () async {
      final rules = await api.reference.rules();
      expect(rules['version'], MockApi.configVersion);
    });
  });

  test('an unrouted path fails loudly rather than returning empty data',
      () async {
    await expectLater(
      mock.get('/not/a/real/endpoint'),
      throwsA(
        isA<AppError>().having((e) => e.message, 'message', contains('no route')),
      ),
    );
  });
}
