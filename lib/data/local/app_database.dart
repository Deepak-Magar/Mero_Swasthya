import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import 'connection.dart';
import 'converters.dart';
import 'daos/cache_dao.dart';
import 'daos/child_health_dao.dart';
import 'daos/documents_dao.dart';
import 'daos/patients_dao.dart';
import 'daos/pregnancies_dao.dart';
import 'daos/sync_meta_dao.dart';
import 'daos/visits_dao.dart';
import 'outbox.dart';

part 'app_database.g.dart';

/// Spec §6 — the local database.
///
/// Every table mirrors a Part A entity one-to-one with snake_case columns and
/// JSON TEXT columns for nested objects (drift derives the snake_case SQL name
/// from each Dart getter). Syncable tables carry `version`, `updated_at` and
/// `deleted`; three device-only tables are added: [Outbox], [SyncMeta] and the
/// read-only caches.
///
/// Row classes are suffixed `Row` so they never collide with the freezed domain
/// models of the same name — `PatientRow` is what sqlite holds, [Patient] is
/// what the rest of the app passes around.
///
/// Dates are TEXT in ISO-8601 exactly as Part A sends them; the models use
/// `String` for the same fields, so row ↔ model mapping stays lossless and no
/// timezone conversion can creep in.

// ---------------------------------------------------------------------------
// Syncable tables
// ---------------------------------------------------------------------------

/// Single row for the logged-in user.
@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get phone => text()();
  TextColumn get role => text().map(userRoleConverter)();
  TextColumn get name => text()();
  TextColumn get facilityId => text().nullable()();
  TextColumn get facilityName => text().nullable()();
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PatientRow')
class Patients extends Table {
  TextColumn get id => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get name => text()();
  TextColumn get sex => text().map(sexConverter)();

  /// YYYY-MM-DD (AD). BS is a display concern only — see core/dates/bs_date.dart.
  TextColumn get dob => text()();
  TextColumn get bloodGroup => text().nullable()();
  IntColumn get ward => integer().nullable()();
  TextColumn get municipality => text().nullable()();
  TextColumn get allergies =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get chronicConditions =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get emergencyContactPhone => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Device-only: set for patients a provider cached through a QR grant, so the
  /// row can be swept once the grant window closes (spec §6).
  TextColumn get accessUntil => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('VisitRow')
class Visits extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get providerUserId => text().withDefault(const Constant(''))();
  TextColumn get providerName => text().withDefault(const Constant(''))();
  TextColumn get facilityId => text().nullable()();
  TextColumn get facilityName => text().nullable()();
  TextColumn get visitAt => text()();
  TextColumn get chiefComplaintCode => text()();
  TextColumn get vitals => text().nullable().map(vitalsConverter)();
  TextColumn get diagnosisCodes =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  TextColumn get advice => text().nullable()();
  TextColumn get followUpAt => text().nullable()();
  TextColumn get referral => text().nullable().map(referralConverter)();

  /// Embedded, not a second table (spec §6).
  TextColumn get prescriptions => text()
      .map(const PrescriptionListConverter())
      .withDefault(const Constant('[]'))();
  TextColumn get supersedesId => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DocumentRow')
class Documents extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get uploadedByUserId => text().withDefault(const Constant(''))();
  TextColumn get type => text().map(documentTypeConverter)();
  TextColumn get title => text()();
  TextColumn get takenAt => text()();
  TextColumn get status => text()
      .map(documentStatusConverter)
      .withDefault(const Constant('pending_upload'))();
  TextColumn get downloadUrl => text().nullable()();
  TextColumn get aiSummary => text().nullable()();
  TextColumn get aiSummaryStatus => text()
      .map(aiSummaryStatusConverter)
      .withDefault(const Constant('none'))();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Device-only: the compressed file waiting for the upload worker (spec §7).
  TextColumn get localPath => text().nullable()();

  /// Device-only: the worker gives up at 5 (spec §7).
  IntColumn get uploadAttempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PregnancyRow')
class Pregnancies extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get lmp => text().nullable()();
  TextColumn get edd => text()();
  IntColumn get gravida => integer().withDefault(const Constant(1))();
  IntColumn get para => integer().withDefault(const Constant(0))();
  TextColumn get riskFactors =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get riskLevel =>
      text().map(riskLevelConverter).withDefault(const Constant('normal'))();
  TextColumn get status =>
      text().map(pregnancyStatusConverter).withDefault(const Constant('active'))();
  TextColumn get birthPlan => text().nullable().map(birthPlanConverter)();
  TextColumn get registeredByUserId => text().withDefault(const Constant(''))();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ids are deterministic (uuid v5, spec A.8.15), so a pregnancy registered
/// offline and the server's own eight contacts converge instead of duplicating.
@DataClassName('AncContactRow')
class AncContacts extends Table {
  TextColumn get id => text()();
  TextColumn get pregnancyId => text()();
  IntColumn get contactNo => integer()();
  IntColumn get weekTarget => integer()();
  TextColumn get dueAt => text()();
  TextColumn get doneAt => text().nullable()();
  TextColumn get providerUserId => text().nullable()();
  TextColumn get findings => text().nullable().map(findingsConverter)();
  TextColumn get dangerSigns =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get triageLevel =>
      text().nullable().map(nullableTriageLevelConverter)();
  TextColumn get triageReasons =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  TextColumn get referral => text().nullable().map(referralConverter)();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DeliveryRow')
class Deliveries extends Table {
  TextColumn get id => text()();
  TextColumn get pregnancyId => text()();
  TextColumn get deliveredAt => text()();
  TextColumn get place => text().map(deliveryPlaceConverter)();
  TextColumn get mode => text().map(deliveryModeConverter)();
  TextColumn get outcome => text().map(deliveryOutcomeConverter)();
  RealColumn get babyWeightKg => real().nullable()();
  TextColumn get babySex => text().nullable().map(nullableSexConverter)();
  TextColumn get complications =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Tier 3 — one row per scheduled dose on the national EPI schedule.
///
/// Additive to Part A (see `docs/CONTRACT_ADDENDUM.md`). Rows exist from the
/// moment a child is registered, with `given_at` null: the schedule is the
/// point, and a vaccine nobody has given yet is exactly the row a health worker
/// needs to see.
@DataClassName('ImmunisationRow')
class Immunisations extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get vaccineCode => text()();
  IntColumn get doseNo => integer()();
  TextColumn get dueAt => text()();
  TextColumn get givenAt => text().nullable()();
  TextColumn get givenByUserId => text().nullable()();
  TextColumn get batchNo => text().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Tier 3 — weight / height / MUAC over time. Additive; append-only in practice.
@DataClassName('GrowthMeasurementRow')
class GrowthMeasurements extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get measuredAt => text()();
  RealColumn get weightKg => real()();
  RealColumn get heightCm => real().nullable()();
  RealColumn get muacCm => real().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Read-only caches (server-owned; never enqueued in the outbox)
// ---------------------------------------------------------------------------

@DataClassName('ReminderRow')
class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get pregnancyId => text().nullable()();
  TextColumn get kind => text().map(reminderKindConverter)();
  TextColumn get dueAt => text()();
  TextColumn get channel =>
      text().map(reminderChannelConverter).withDefault(const Constant('sms'))();
  TextColumn get recipientPhone => text().withDefault(const Constant(''))();
  TextColumn get recipientRole => text()
      .map(recipientRoleConverter)
      .withDefault(const Constant('patient'))();
  TextColumn get messageNp => text().withDefault(const Constant(''))();
  TextColumn get messageEn => text().withDefault(const Constant(''))();
  TextColumn get status =>
      text().map(reminderStatusConverter).withDefault(const Constant('pending'))();
  TextColumn get sentAt => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AuditEntryRow')
class AuditEntries extends Table {
  TextColumn get id => text()();
  TextColumn get patientId => text()();
  TextColumn get actorUserId => text()();
  TextColumn get actorName => text().withDefault(const Constant(''))();
  TextColumn get actorFacilityName => text().nullable()();
  TextColumn get action => text().map(auditActionConverter)();
  TextColumn get at => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FacilityRow')
class Facilities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get type => text().map(facilityTypeConverter)();
  BoolColumn get hasBirthingCentre =>
      boolean().withDefault(const Constant(false))();
  TextColumn get phone => text().nullable()();
  RealColumn get lat => real().withDefault(const Constant(0))();
  RealColumn get lng => real().withDefault(const Constant(0))();
  TextColumn get municipality => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CodelistItemRow')
class CodelistItems extends Table {
  TextColumn get kind => text().map(codeListKindConverter)();
  TextColumn get code => text()();
  TextColumn get labelEn => text()();
  TextColumn get labelNp => text()();
  TextColumn get meta => text().nullable().map(const NullableJsonMapConverter())();

  @override
  Set<Column<Object>> get primaryKey => {kind, code};
}

// ---------------------------------------------------------------------------
// Device-only tables
// ---------------------------------------------------------------------------

/// The heart of offline-first (spec §6/§7): every local write enqueues one row
/// here, and the sync engine drains it in `created_at` order.
@DataClassName('OutboxRow')
class Outbox extends Table {
  TextColumn get opId => text()();

  /// Named explicitly because `tableName` is already a member of drift's
  /// [Table]; the SQL column is still `table_name` as the spec requires.
  TextColumn get targetTable => text().named('table_name')();
  TextColumn get op => text().map(outboxOpConverter)();
  TextColumn get rowId => text()();
  IntColumn get baseVersion => integer()();
  TextColumn get payload => text().map(const JsonMapConverter())();
  TextColumn get createdAt => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Set when the server rejects the op; S17 shows it and offers retry/discard.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {opId};
}

/// Key/value scratch space. Keys are listed in [SyncMetaKeys].
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The `sync_meta` keys named in spec §6.
abstract final class SyncMetaKeys {
  static const String pullCursor = 'pull_cursor';
  static const String lastPushAt = 'last_push_at';
  static const String lastPullAt = 'last_pull_at';
  static const String deviceId = 'device_id';
  static const String rulesVersion = 'rules_version';
  static const String codelistVersion = 'codelist_version';
  static const String serverTimeOffsetMs = 'server_time_offset_ms';
}

/// The `outbox.table_name` values the sync engine understands. These are the
/// Part A table names, not drift's Dart class names.
abstract final class SyncTables {
  static const String patients = 'patients';
  static const String visits = 'visits';
  static const String documents = 'documents';
  static const String pregnancies = 'pregnancies';
  static const String ancContacts = 'anc_contacts';
  static const String deliveries = 'deliveries';

  /// Tier 3, additive (see `docs/CONTRACT_ADDENDUM.md`).
  static const String immunisations = 'immunisations';
  static const String growthMeasurements = 'growth_measurements';

  /// Tables a client may push. Reminders, audit, facilities and codelists are
  /// server-owned and pull-only.
  static const List<String> pushable = [
    patients,
    visits,
    documents,
    pregnancies,
    ancContacts,
    deliveries,
    immunisations,
    growthMeasurements,
  ];
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    Users,
    Patients,
    Visits,
    Documents,
    Pregnancies,
    AncContacts,
    Deliveries,
    Immunisations,
    GrowthMeasurements,
    Reminders,
    AuditEntries,
    Facilities,
    CodelistItems,
    Outbox,
    SyncMeta,
  ],
  daos: [
    PatientsDao,
    VisitsDao,
    DocumentsDao,
    PregnanciesDao,
    ChildHealthDao,
    CacheDao,
    SyncMetaDao,
    OutboxDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppDatabase());

  /// For tests and for the in-memory demo mode.
  AppDatabase.forTesting(super.executor);

  /// 1 → 2 adds the Tier 3 child-health tables.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Additive only: two new tables, nothing existing touched. A phone
          // that already holds a demo record keeps every row it had — which is
          // the whole reason this is a migration and not a wipe.
          if (from < 2) {
            await m.createTable(immunisations);
            await m.createTable(growthMeasurements);
          }
        },
        beforeOpen: (details) async {
          // Drift does not enable this by default and the sync engine relies on
          // it when a discarded outbox op deletes a locally created row.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Wipes every table. Used by logout (spec §12: "Sign out clears the local
  /// database") and by tests between cases.
  Future<void> clearAll() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}
