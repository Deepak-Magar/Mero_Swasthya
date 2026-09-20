import 'package:drift/drift.dart' show Value;

import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../local/app_database.dart';
import '../sync/sync_payload.dart';
import 'syncable_repo.dart';

/// Paper capture (S22) and the documents grid (S10).
///
/// A document is two separate things travelling separately: the metadata row,
/// which rides the ordinary outbox, and the compressed image, which the upload
/// worker sends through presign → PUT → complete (spec §7). Capture only has to
/// make the local file and the metadata durable; everything else is retry.
class DocumentRepo extends SyncableRepo {
  const DocumentRepo(super.db, super.sync);

  Stream<List<Document>> watchByPatient(String patientId) =>
      db.documentsDao.watchByPatient(patientId);

  Future<Document?> findById(String id) => db.documentsDao.findById(id);

  /// Documents whose image ran out of upload retries — surfaced on S17.
  Stream<List<Document>> watchStuckUploads() =>
      db.documentsDao.watchStuckUploads();

  /// S22: the photo is already compressed and saved at [localPath].
  Future<void> capture(Document document, String localPath) {
    final row = document.copyWith(
      version: 0,
      status: DocumentStatus.pendingUpload,
    );
    return writeAndEnqueue(
      write: () => db.documentsDao.upsert(
        row,
        localPath: Value<String?>(localPath),
        uploadAttempts: const Value(0),
      ),
      table: SyncTables.documents,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }

  /// S10 rename / retype. Metadata only — the image is never re-sent.
  Future<void> updateMeta(Document document) async {
    final local = await db.documentsDao.findById(document.id);
    final baseVersion = local?.version ?? document.version;
    final row = document.copyWith(version: baseVersion);

    await writeAndEnqueue(
      write: () => db.documentsDao.upsert(row),
      table: SyncTables.documents,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  Future<void> softDelete(String id) async {
    final local = await db.documentsDao.findById(id);
    if (local == null) return;
    final row = local.copyWith(deleted: true);

    await writeAndEnqueue(
      write: () => db.documentsDao.upsert(row),
      table: SyncTables.documents,
      rowId: id,
      baseVersion: local.version,
      payload: row.toSyncJson(),
    );
  }

  // -------------------------------------------------------------------------
  // Upload worker hooks (driven by the sync engine, not by a screen)
  // -------------------------------------------------------------------------

  Future<List<DocumentRow>> pendingUploads() =>
      db.documentsDao.pendingUploads();

  Future<void> markUploaded(String id, {String? downloadUrl}) =>
      db.documentsDao.markUploaded(id, downloadUrl: downloadUrl);

  Future<void> recordUploadFailure(String id) =>
      db.documentsDao.recordUploadFailure(id);
}
