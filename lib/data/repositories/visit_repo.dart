import '../../domain/models/models.dart';
import '../local/app_database.dart';
import '../sync/sync_payload.dart';
import 'syncable_repo.dart';

/// Visits (S21, the 60-second form) and the visit half of the timeline.
///
/// Visits are append-only: a correction is a new row pointing at the old one
/// through `supersedesId`, never an edit. That is why every write here goes out
/// with `baseVersion: 0` — spec A.4 notes that for append-only tables a
/// conflict can only mean an id collision.
class VisitRepo extends SyncableRepo {
  const VisitRepo(super.db, super.sync);

  Stream<List<Visit>> watchByPatient(String patientId) =>
      db.visitsDao.watchByPatient(patientId);

  Stream<Visit?> watchById(String id) => db.visitsDao.watchById(id);

  Future<Visit?> findById(String id) => db.visitsDao.findById(id);

  /// Feeds the last-vitals block on S08 when the server summary is unreachable.
  Future<Visit?> latestForPatient(String patientId) =>
      db.visitsDao.latestForPatient(patientId);

  /// S21 save. Returns as soon as the row and its outbox op are durable.
  Future<void> add(Visit visit) {
    final row = visit.copyWith(version: 0);
    return writeAndEnqueue(
      write: () => db.visitsDao.upsert(row),
      table: SyncTables.visits,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }

  /// A correction: a fresh row that supersedes [supersedes]. The original stays
  /// visible — a health record is not something you quietly rewrite.
  Future<void> supersede(Visit correction, String supersedes) {
    final row = correction.copyWith(version: 0, supersedesId: supersedes);
    return writeAndEnqueue(
      write: () => db.visitsDao.upsert(row),
      table: SyncTables.visits,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }
}
