import '../../domain/models/models.dart';
import '../local/app_database.dart';
import '../local/converters.dart';
import '../sync/sync_payload.dart';
import 'syncable_repo.dart';

/// Pregnancy registration (S11), the ANC checklist (S12), the dashboard (S13)
/// and the delivery record (S14).
class PregnancyRepo extends SyncableRepo {
  const PregnancyRepo(super.db, super.sync);

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Stream<Pregnancy?> watchActiveForPatient(String patientId) =>
      db.pregnanciesDao.watchActiveForPatient(patientId);

  Stream<Pregnancy?> watchLatestForPatient(String patientId) =>
      db.pregnanciesDao.watchLatestForPatient(patientId);

  Stream<PregnancyBundle> watchBundle(String pregnancyId) =>
      db.pregnanciesDao.watchBundle(pregnancyId);

  Stream<List<AncContact>> watchContacts(String pregnancyId) =>
      db.pregnanciesDao.watchContacts(pregnancyId);

  Future<Pregnancy?> findById(String id) => db.pregnanciesDao.findById(id);

  Future<AncContact?> findContactByNo(String pregnancyId, int contactNo) =>
      db.pregnanciesDao.findContactByNo(pregnancyId, contactNo);

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// S11 register. [contacts] is the eight-visit schedule the rules engine
  /// generated, with the deterministic uuid v5 ids from spec A.8.15.
  ///
  /// Only the pregnancy is enqueued. The server creates the same eight contacts
  /// itself on `POST /pregnancies`, and because both sides derive the ids from
  /// `pregnancyId:contactNo` they land on the same rows instead of duplicating.
  /// The local placeholders exist so the checklist renders immediately; each one
  /// is pushed by [recordContact] when it is actually filled in.
  Future<void> register(Pregnancy pregnancy, List<AncContact> contacts) {
    final row = pregnancy.copyWith(version: 0);
    return writeAndEnqueue(
      write: () async {
        await db.pregnanciesDao.upsertPregnancy(row);
        await db.pregnanciesDao.upsertContacts(contacts);
      },
      table: SyncTables.pregnancies,
      rowId: row.id,
      baseVersion: 0,
      payload: row.toSyncJson(),
    );
  }

  /// S13 edits: risk factors, risk level, birth plan.
  Future<void> updatePregnancy(Pregnancy pregnancy) async {
    final local = await db.pregnanciesDao.findById(pregnancy.id);
    final baseVersion = local?.version ?? pregnancy.version;
    final row = pregnancy.copyWith(version: baseVersion);

    await writeAndEnqueue(
      write: () => db.pregnanciesDao.upsertPregnancy(row),
      table: SyncTables.pregnancies,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  /// S12 save. The contact row already exists as a placeholder, so this is an
  /// edit and `baseVersion` is whatever the local row currently holds — 0 while
  /// the placeholder has never been near the server, higher once it has.
  ///
  /// [contact] carries the triage level and reasons the rules engine produced;
  /// the server recomputes them and its answer wins on the next pull.
  Future<void> recordContact(AncContact contact) async {
    final local = await db.pregnanciesDao.findContact(contact.id);
    final baseVersion = local?.version ?? contact.version;
    final row = contact.copyWith(version: baseVersion);

    await writeAndEnqueue(
      write: () => db.pregnanciesDao.upsertContact(row),
      table: SyncTables.ancContacts,
      rowId: row.id,
      baseVersion: baseVersion,
      payload: row.toSyncJson(),
    );
  }

  /// S14. Recording a delivery also ends the pregnancy, and both rows have to
  /// reach the server or neither should — hence one transaction, two ops.
  Future<void> recordDelivery(Delivery delivery, Pregnancy pregnancy) async {
    final local = await db.pregnanciesDao.findById(pregnancy.id);
    final pregnancyBaseVersion = local?.version ?? pregnancy.version;
    final deliveryRow = delivery.copyWith(version: 0);
    final pregnancyRow = pregnancy.copyWith(version: pregnancyBaseVersion);

    await db.transaction(() async {
      await db.pregnanciesDao.upsertDelivery(deliveryRow);
      await db.pregnanciesDao.upsertPregnancy(pregnancyRow);

      await db.outboxDao.enqueue(
        table: SyncTables.deliveries,
        op: OutboxOp.upsert,
        rowId: deliveryRow.id,
        baseVersion: 0,
        payload: deliveryRow.toSyncJson(),
      );
      await db.outboxDao.enqueue(
        table: SyncTables.pregnancies,
        op: OutboxOp.upsert,
        rowId: pregnancyRow.id,
        baseVersion: pregnancyBaseVersion,
        payload: pregnancyRow.toSyncJson(),
      );
    });
    sync.kick();
  }
}
