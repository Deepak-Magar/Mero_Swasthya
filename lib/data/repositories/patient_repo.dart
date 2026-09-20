import 'package:drift/drift.dart' show Value;

import '../../domain/models/models.dart';
import '../../core/errors/app_error.dart';
import '../local/app_database.dart';
import '../remote/api/api.dart';
import '../sync/sync_payload.dart';
import 'syncable_repo.dart';

/// Family profiles (S06, S07) and the patients a provider holds through a grant.
class PatientRepo extends SyncableRepo {
  const PatientRepo(super.db, super.sync, this.api);

  final Api api;

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Stream<List<Patient>> watchFamily(String ownerUserId) =>
      db.patientsDao.watchFamily(ownerUserId);

  Stream<Patient?> watchById(String id) => db.patientsDao.watchById(id);

  Future<Patient?> findById(String id) => db.patientsDao.findById(id);

  /// S19 provider home. Evaluated against [now] rather than a stored "is
  /// active" flag so an expired grant disappears without anything running.
  Stream<List<Patient>> watchGranted({DateTime? now}) => db.patientsDao
      .watchGranted((now ?? DateTime.now()).toUtc().toIso8601String());

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// S07 "add family member". Version 0 marks the row as not yet on the server,
  /// which is also what the pending cloud icon keys off.
  Future<void> create(Patient patient) {
    final row = patient.copyWith(version: 0);
    return writeAndEnqueue(
      write: () => db.patientsDao.upsert(row),
      table: SyncTables.patients,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }

  /// S07 edit. `baseVersion` is read from the local row rather than taken from
  /// the caller, so a screen holding a stale object cannot silently overwrite a
  /// newer pull.
  Future<void> update(Patient patient) async {
    final local = await db.patientsDao.findById(patient.id);
    final baseVersion = local?.version ?? patient.version;
    final row = patient.copyWith(version: baseVersion);

    await writeAndEnqueue(
      write: () => db.patientsDao.upsert(row),
      table: SyncTables.patients,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  /// Soft delete — the row stays so the server can reconcile it, and every
  /// query already filters on `deleted`.
  Future<void> softDelete(String id) async {
    final local = await db.patientsDao.findById(id);
    if (local == null) return;
    final row = local.copyWith(deleted: true);

    await writeAndEnqueue(
      write: () => db.patientsDao.upsert(row),
      table: SyncTables.patients,
      rowId: id,
      baseVersion: local.version,
      payload: row.toSyncJson(),
    );
  }

  /// S20 QR redeem: cache someone else's patient for the length of the grant.
  ///
  /// No outbox op — the grant gives read (or append) access to that patient's
  /// record, not ownership of the profile row.
  Future<void> cacheGranted(Patient patient, String accessUntil) {
    return db.patientsDao
        .upsert(patient, accessUntil: Value<String?>(accessUntil));
  }

  /// Spec S06: "GET /patients (on refresh), plus local DB read".
  ///
  /// The sync pull carries patients too, but only ones changed since the
  /// cursor — a device that has just signed in on an account with existing
  /// records needs the list itself. Returns true when the fetch landed; a
  /// failure leaves the cached rows untouched.
  Future<bool> refreshFromServer() async {
    try {
      for (final patient in await api.patients.list()) {
        // Never clobber a row the user has edited and not yet sent.
        if (await db.outboxDao.hasPendingOp(patient.id)) continue;
        await db.patientsDao.upsertIfNewer(patient.toJson());
      }
      return true;
    } on AppError {
      return false;
    }
  }

  /// Called on app start and after each sync so a provider's phone does not
  /// keep records past the grant window.
  /// When this device's grant for [id] closes, or null when there is no
  /// window on it.
  Stream<DateTime?> watchAccessUntil(String id) =>
      db.patientsDao.watchAccessUntil(id);

  Future<int> purgeExpiredGrants({DateTime? now}) => db.patientsDao
      .purgeExpiredGrants((now ?? DateTime.now()).toUtc().toIso8601String());
}
