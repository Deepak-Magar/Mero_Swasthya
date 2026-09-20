import 'package:drift/drift.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'documents_dao.g.dart';

@DriftAccessor(tables: [Documents])
class DocumentsDao extends DatabaseAccessor<AppDatabase>
    with _$DocumentsDaoMixin {
  DocumentsDao(super.db);

  /// Spec §7: the upload worker gives up after five failures.
  static const int maxUploadAttempts = 5;

  /// S10 documents grid — newest first.
  Stream<List<Document>> watchByPatient(String patientId) {
    return (select(documents)
          ..where((t) => t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// S10 needs `local_path` to draw the captured thumbnail, and that column is
  /// device-only so it never reaches the [Document] model. The grid therefore
  /// watches rows rather than models.
  Stream<List<DocumentRow>> watchRowsByPatient(String patientId) {
    return (select(documents)
          ..where((t) => t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]))
        .watch();
  }

  Future<Document?> findById(String id) async {
    final row = await (select(documents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// The file on disk that still has to reach the server, if any.
  Future<String?> localPathOf(String id) async {
    final row = await (select(documents)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.localPath;
  }

  Future<void> upsert(
    Document document, {
    Value<String?> localPath = const Value.absent(),
    Value<int> uploadAttempts = const Value.absent(),
  }) {
    return into(documents).insertOnConflictUpdate(
      document.toCompanion(
        localPath: localPath,
        uploadAttempts: uploadAttempts,
      ),
    );
  }

  Future<void> upsertFromServer(Map<String, dynamic> json) =>
      upsert(Document.fromJson(json));

  Future<bool> upsertIfNewer(Map<String, dynamic> json) async {
    final incoming = Document.fromJson(json);
    final local = await findById(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsert(incoming);
    return true;
  }

  /// The upload worker's queue: captured locally, not yet on the server, and
  /// not yet out of retries.
  Future<List<DocumentRow>> pendingUploads() {
    return (select(documents)
          ..where((t) =>
              t.status.equalsValue(DocumentStatus.pendingUpload) &
              t.localPath.isNotNull() &
              t.uploadAttempts.isSmallerThanValue(maxUploadAttempts) &
              t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.takenAt)]))
        .get();
  }

  /// Documents that exhausted their retries — S17 shows these as stuck.
  Stream<List<Document>> watchStuckUploads() {
    return (select(documents)
          ..where((t) =>
              t.status.equalsValue(DocumentStatus.pendingUpload) &
              t.uploadAttempts.isBiggerOrEqualValue(maxUploadAttempts)))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<void> recordUploadFailure(String id) async {
    await customUpdate(
      'UPDATE documents SET upload_attempts = upload_attempts + 1 WHERE id = ?',
      variables: [Variable<String>(id)],
      updates: {documents},
      updateKind: UpdateKind.update,
    );
  }

  /// POST /documents/:id/complete came back: the bytes are on the server.
  ///
  /// `local_path` is deliberately **kept**. The status alone takes the row out
  /// of [pendingUploads], and the file on disk is what lets S10 draw the
  /// thumbnail and the detail view with no network — which is the whole point
  /// of the app. Dropping the path here made the app fetch a picture it was
  /// already holding, and show a placeholder whenever it could not.
  Future<void> markUploaded(String id, {String? downloadUrl}) {
    return (update(documents)..where((t) => t.id.equals(id))).write(
      DocumentsCompanion(
        status: const Value(DocumentStatus.uploaded),
        downloadUrl:
            downloadUrl == null ? const Value.absent() : Value(downloadUrl),
      ),
    );
  }
}
