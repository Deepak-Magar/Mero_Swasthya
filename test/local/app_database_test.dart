import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/local/converters.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';

/// Guards spec §6: the local schema is a contract shared with the backend's
/// sync payloads, so a renamed column is a broken app, not a refactor.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  group('schema', () {
    test('every table from spec §6 exists', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get();

      expect(rows.map((r) => r.read<String>('name')), [
        'anc_contacts',
        'audit_entries',
        'codelist_items',
        'deliveries',
        'documents',
        'facilities',
        // Tier 3, additive (docs/CONTRACT_ADDENDUM.md).
        'growth_measurements',
        'immunisations',
        'outbox',
        'patients',
        'pregnancies',
        'reminders',
        'sync_meta',
        'users',
        'visits',
      ]);
    });

    test('patients columns match the spec, including access_until', () async {
      expect(await columnsOf('patients'), [
        'id',
        'owner_user_id',
        'name',
        'sex',
        'dob',
        'blood_group',
        'ward',
        'municipality',
        'allergies',
        'chronic_conditions',
        'emergency_contact_phone',
        'version',
        'updated_at',
        'deleted',
        'access_until',
      ]);
    });

    test('outbox columns match the spec', () async {
      expect(await columnsOf('outbox'), [
        'op_id',
        'table_name',
        'op',
        'row_id',
        'base_version',
        'payload',
        'created_at',
        'attempts',
        'last_error',
      ]);
    });

    test('documents keeps the two device-only columns last', () async {
      final columns = await columnsOf('documents');
      expect(columns, contains('local_path'));
      expect(columns, contains('upload_attempts'));
    });

    test('codelist_items is keyed by (kind, code)', () async {
      await db.into(db.codelistItems).insert(
            CodelistItemsCompanion.insert(
              kind: CodeListKind.drug,
              code: 'IFA',
              labelEn: 'Iron folic acid',
              labelNp: 'आइरन फोलिक एसिड',
            ),
          );
      await db.into(db.codelistItems).insert(
            CodelistItemsCompanion.insert(
              kind: CodeListKind.diagnosis,
              // Same code, different kind — must not collide.
              code: 'IFA',
              labelEn: 'Iron deficiency',
              labelNp: 'रगतको कमी',
            ),
          );

      expect(await db.select(db.codelistItems).get(), hasLength(2));
    });
  });

  group('converters', () {
    test('patient round-trips enums and JSON list columns', () async {
      await db.into(db.patients).insert(
            PatientsCompanion.insert(
              id: 'p1',
              ownerUserId: 'u1',
              name: 'Sita Devi',
              sex: Sex.female,
              dob: '1998-04-12',
              allergies: const Value(['penicillin', 'sulfa']),
              chronicConditions: const Value(['asthma']),
              ward: const Value(5),
            ),
          );

      final row = await db.select(db.patients).getSingle();
      expect(row.sex, Sex.female);
      expect(row.allergies, ['penicillin', 'sulfa']);
      expect(row.chronicConditions, ['asthma']);
      expect(row.version, 0, reason: 'version 0 = not yet on the server');
      expect(row.deleted, isFalse);
    });

    test('enums are stored as the Part A wire string, not the Dart name',
        () async {
      await db.into(db.documents).insert(
            DocumentsCompanion.insert(
              id: 'd1',
              patientId: 'p1',
              type: DocumentType.lab,
              title: 'CBC',
              takenAt: '2026-09-18T04:00:00.000Z',
              status: const Value(DocumentStatus.pendingUpload),
            ),
          );

      final raw = await db
          .customSelect('SELECT status, ai_summary_status FROM documents')
          .getSingle();
      expect(raw.read<String>('status'), 'pending_upload');
      expect(raw.read<String>('ai_summary_status'), 'none');
    });

    test('visit round-trips embedded vitals, referral and prescriptions',
        () async {
      await db.into(db.visits).insert(
            VisitsCompanion.insert(
              id: 'v1',
              patientId: 'p1',
              visitAt: '2026-09-18T05:30:00.000Z',
              chiefComplaintCode: 'FEVER',
              vitals: const Value(Vitals(bpSys: 130, bpDia: 85, tempC: 38.4)),
              diagnosisCodes: const Value(['URTI']),
              referral: const Value(
                Referral(
                  facilityName: 'Ghorahi PHCC',
                  reason: 'High BP',
                  urgency: ReferralUrgency.urgent,
                ),
              ),
              prescriptions: const Value([
                Prescription(
                  id: 'rx1',
                  drugCode: 'PARA500',
                  dose: '500mg',
                  frequency: PrescriptionFrequency.tds,
                  durationDays: 3,
                ),
              ]),
            ),
          );

      final row = await db.select(db.visits).getSingle();
      expect(row.vitals?.bpSys, 130);
      expect(row.vitals?.tempC, 38.4);
      expect(row.referral?.urgency, ReferralUrgency.urgent);
      expect(row.prescriptions.single.drugCode, 'PARA500');
      expect(row.prescriptions.single.frequency, PrescriptionFrequency.tds);
      expect(row.diagnosisCodes, ['URTI']);
    });

    test('nullable enum and object columns stay null', () async {
      await db.into(db.ancContacts).insert(
            AncContactsCompanion.insert(
              id: 'a1',
              pregnancyId: 'pg1',
              contactNo: 1,
              weekTarget: 12,
              dueAt: '2026-10-01T00:00:00.000Z',
            ),
          );

      final row = await db.select(db.ancContacts).getSingle();
      expect(row.triageLevel, isNull);
      expect(row.findings, isNull);
      expect(row.referral, isNull);
      expect(row.dangerSigns, isEmpty);
      expect(row.triageReasons, isEmpty);
    });

    test('an unknown enum value from a newer server falls back, not throws',
        () async {
      await db.customStatement(
        "INSERT INTO documents (id, patient_id, uploaded_by_user_id, type, "
        "title, taken_at, status, ai_summary_status, version, deleted, "
        "upload_attempts) VALUES ('d9', 'p1', '', 'ultrasound_video', 'Scan', "
        "'2026-09-18T04:00:00.000Z', 'uploaded', 'none', 3, 0, 0)",
      );

      final row = await db.select(db.documents).getSingle();
      expect(row.type, DocumentType.other);
    });
  });

  group('outbox', () {
    test('enqueued op keeps its payload as an object', () async {
      await db.into(db.outbox).insert(
            OutboxCompanion.insert(
              opId: 'op1',
              targetTable: SyncTables.visits,
              op: OutboxOp.upsert,
              rowId: 'v1',
              baseVersion: 0,
              payload: {'id': 'v1', 'chiefComplaintCode': 'FEVER'},
              createdAt: '2026-09-18T05:30:01.000Z',
            ),
          );

      final row = await db.select(db.outbox).getSingle();
      expect(row.targetTable, 'visits');
      expect(row.op, OutboxOp.upsert);
      expect(row.payload['chiefComplaintCode'], 'FEVER');
      expect(row.attempts, 0);
      expect(row.lastError, isNull);
    });

    test('only the client-writable tables are pushable', () {
      // Reminders, audit entries, facilities and codelists are server-owned and
      // must never appear here. The last two are Tier 3 additions.
      expect(SyncTables.pushable, [
        'patients',
        'visits',
        'documents',
        'pregnancies',
        'anc_contacts',
        'deliveries',
        'immunisations',
        'growth_measurements',
      ]);
    });
  });

  test('clearAll empties every table', () async {
    await db.into(db.syncMeta).insert(
          SyncMetaCompanion.insert(
            key: SyncMetaKeys.deviceId,
            value: 'device-1',
          ),
        );
    await db.into(db.patients).insert(
          PatientsCompanion.insert(
            id: 'p1',
            ownerUserId: 'u1',
            name: 'Sita Devi',
            sex: Sex.female,
            dob: '1998-04-12',
          ),
        );

    await db.clearAll();

    expect(await db.select(db.patients).get(), isEmpty);
    expect(await db.select(db.syncMeta).get(), isEmpty);
  });
}
