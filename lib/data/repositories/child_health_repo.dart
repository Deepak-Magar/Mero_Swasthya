import '../../core/ids/ids.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/epi_schedule.dart';
import '../local/app_database.dart';
import '../sync/sync_payload.dart';
import 'syncable_repo.dart';

/// Tier 3 — the only write path for immunisations and growth measurements
/// (spec §6.2).
///
/// Both tables are additive to Part A; see `docs/CONTRACT_ADDENDUM.md` for the
/// shapes the backend has to accept.
class ChildHealthRepo extends SyncableRepo {
  const ChildHealthRepo(super.db, super.sync);

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Stream<List<Immunisation>> watchSchedule(String patientId) =>
      db.childHealthDao.watchSchedule(patientId);

  Stream<List<GrowthMeasurement>> watchGrowth(String patientId) =>
      db.childHealthDao.watchGrowth(patientId);

  Future<List<Immunisation>> schedule(String patientId) =>
      db.childHealthDao.schedule(patientId);

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Create the child's schedule from their date of birth, once.
  ///
  /// Returns the number of rows written — zero when a schedule already exists,
  /// because the ids are deterministic and re-running this would otherwise
  /// re-enqueue every dose and undo any `givenAt` the server has since applied.
  ///
  /// Nothing is enqueued for the rows themselves. Like the eight ANC contacts of
  /// A.8.15, the server derives the same schedule from the same date of birth
  /// with the same ids; pushing thirty empty placeholder rows would be thirty
  /// ops that say nothing. Each dose is pushed by [recordDose] when it is
  /// actually given.
  Future<int> ensureSchedule({
    required String patientId,
    required DateTime dob,
    required EpiSchedule epi,
  }) async {
    if (await db.childHealthDao.countFor(patientId) > 0) return 0;

    final rows = epi.generateFor(patientId: patientId, dob: dob);
    if (rows.isEmpty) return 0;

    await db.childHealthDao.upsertImmunisations(rows);
    return rows.length;
  }

  /// Mark a dose given. This is the write that matters, so this is the one that
  /// goes in the outbox.
  Future<void> recordDose(
    Immunisation dose, {
    required DateTime givenAt,
    String? batchNo,
    String? givenByUserId,
  }) async {
    final local = await db.childHealthDao.findImmunisation(dose.id);
    final baseVersion = local?.version ?? dose.version;

    final row = dose.copyWith(
      givenAt: givenAt.toUtc().toIso8601String(),
      batchNo: (batchNo?.trim().isEmpty ?? true) ? null : batchNo!.trim(),
      givenByUserId: givenByUserId,
      version: baseVersion,
    );

    await writeAndEnqueue(
      write: () => db.childHealthDao.upsertImmunisation(row),
      table: SyncTables.immunisations,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  /// Undo — a dose recorded against the wrong child is a thing that happens,
  /// and the alternative is a row nobody can correct.
  Future<void> clearDose(Immunisation dose) async {
    final local = await db.childHealthDao.findImmunisation(dose.id);
    final baseVersion = local?.version ?? dose.version;

    final row = Immunisation(
      id: dose.id,
      patientId: dose.patientId,
      vaccineCode: dose.vaccineCode,
      doseNo: dose.doseNo,
      dueAt: dose.dueAt,
      version: baseVersion,
    );

    await writeAndEnqueue(
      write: () => db.childHealthDao.upsertImmunisation(row),
      table: SyncTables.immunisations,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  Future<void> addMeasurement(GrowthMeasurement measurement) {
    final row = measurement.copyWith(version: 0);
    return writeAndEnqueue(
      write: () => db.childHealthDao.upsertGrowth(row),
      table: SyncTables.growthMeasurements,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }

  /// A fresh measurement row for [patientId], ready to be filled in.
  GrowthMeasurement newMeasurement({
    required String patientId,
    required DateTime measuredAt,
    required double weightKg,
    double? heightCm,
    double? muacCm,
  }) {
    return GrowthMeasurement(
      id: newId(),
      patientId: patientId,
      measuredAt: measuredAt.toUtc().toIso8601String(),
      weightKg: weightKg,
      heightCm: heightCm,
      muacCm: muacCm,
    );
  }
}
