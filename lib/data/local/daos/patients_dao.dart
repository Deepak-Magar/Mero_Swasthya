import 'package:drift/drift.dart';

import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'patients_dao.g.dart';

@DriftAccessor(tables: [Patients])
class PatientsDao extends DatabaseAccessor<AppDatabase> with _$PatientsDaoMixin {
  PatientsDao(super.db);

  /// S06 family list — the profiles this account owns.
  Stream<List<Patient>> watchFamily(String ownerUserId) {
    return (select(patients)
          ..where((t) => t.ownerUserId.equals(ownerUserId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Stream<Patient?> watchById(String id) {
    return (select(patients)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  Future<Patient?> findById(String id) async {
    final row =
        await (select(patients)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toModel();
  }

  /// S19 provider home — patients cached through a QR grant that has not
  /// expired yet. [nowIso] is compared as text because `access_until` is stored
  /// as an ISO-8601 UTC string, where lexical order is chronological order.
  Stream<List<Patient>> watchGranted(String nowIso) {
    return (select(patients)
          ..where((t) =>
              t.accessUntil.isNotNull() &
              t.accessUntil.isBiggerThanValue(nowIso) &
              t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// Every patient this device still has the right to look at.
  ///
  /// That is: owned records and ones pulled as part of the account's visible
  /// set (both have no `access_until`), plus QR grants that have not run out.
  /// A grant that *has* expired is excluded — the row stays on disk until the
  /// next sync tidies it, but it must not be counted in a health-post total.
  Stream<List<Patient>> watchCachedForProvider(String nowIso) {
    return (select(patients)
          ..where((t) =>
              t.deleted.equals(false) &
              (t.accessUntil.isNull() |
                  t.accessUntil.isBiggerThanValue(nowIso)))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// When this device's access to [id] runs out, or null if it never does.
  ///
  /// Null covers both an owned record and one pulled as part of the account's
  /// visible set; only a QR redeem writes a window.
  Stream<DateTime?> watchAccessUntil(String id) {
    return (select(patients)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row?.accessUntil == null
            ? null
            : DateTime.tryParse(row!.accessUntil!)?.toUtc());
  }

  /// Local write path. [accessUntil] is only supplied by a QR redeem.
  Future<void> upsert(
    Patient patient, {
    Value<String?> accessUntil = const Value.absent(),
  }) {
    return into(patients)
        .insertOnConflictUpdate(patient.toCompanion(accessUntil: accessUntil));
  }

  /// Applies a row the server returned, unconditionally (push result).
  Future<void> upsertFromServer(Map<String, dynamic> json) =>
      upsert(Patient.fromJson(json));

  /// Applies a pulled row only when it is newer than what we hold (spec §7).
  ///
  /// The caller is responsible for skipping rows with a pending outbox op —
  /// see [OutboxDao.hasPendingOp]; the push result settles those instead.
  Future<bool> upsertIfNewer(Map<String, dynamic> json) async {
    final incoming = Patient.fromJson(json);
    final local = await findById(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsert(incoming);
    return true;
  }

  /// Drops grant-cached patients whose window has closed, so a provider's phone
  /// does not keep records it may no longer read.
  Future<int> purgeExpiredGrants(String nowIso) {
    return (delete(patients)
          ..where((t) =>
              t.accessUntil.isNotNull() &
              t.accessUntil.isSmallerOrEqualValue(nowIso)))
        .go();
  }
}
