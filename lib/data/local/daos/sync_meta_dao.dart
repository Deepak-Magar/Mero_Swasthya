import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'sync_meta_dao.g.dart';

/// `sync_meta` plus the single `users` row (spec §6).
///
/// Both are device state rather than patient data: the sync cursor, the device
/// id every sync call carries, the cached rules/codelist versions, and whoever
/// is currently signed in.
@DriftAccessor(tables: [SyncMeta, Users])
class SyncMetaDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  /// Spec §7: the pull cursor starts at the epoch so the first sync is a full
  /// download.
  static const String epoch = '1970-01-01T00:00:00.000Z';

  Future<String?> get(String key) async {
    final row = await (select(syncMeta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) {
    return into(syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(key: key, value: value),
    );
  }

  Future<int?> getInt(String key) async {
    final raw = await get(key);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> setInt(String key, int value) => set(key, '$value');

  Stream<String?> watch(String key) {
    return (select(syncMeta)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  // -------------------------------------------------------------------------
  // Well-known keys
  // -------------------------------------------------------------------------

  /// Generated once and reused for the life of the install (spec §5).
  Future<String> deviceId() async {
    final existing = await get(SyncMetaKeys.deviceId);
    if (existing != null) return existing;
    final generated = newId();
    await set(SyncMetaKeys.deviceId, generated);
    return generated;
  }

  Future<String> pullCursor() async =>
      await get(SyncMetaKeys.pullCursor) ?? epoch;

  Future<void> setPullCursor(String cursor) =>
      set(SyncMetaKeys.pullCursor, cursor);

  Stream<String?> watchLastPushAt() => watch(SyncMetaKeys.lastPushAt);

  Stream<String?> watchLastPullAt() => watch(SyncMetaKeys.lastPullAt);

  /// The gap between this device's clock and the server's, measured on every
  /// push (spec §7). Used when showing "x minutes ago" so a phone with a wrong
  /// clock does not report nonsense.
  Future<int> serverTimeOffsetMs() async =>
      await getInt(SyncMetaKeys.serverTimeOffsetMs) ?? 0;

  Future<void> setServerTimeOffsetMs(int offset) =>
      setInt(SyncMetaKeys.serverTimeOffsetMs, offset);

  // -------------------------------------------------------------------------
  // Grant scope (A.7 printed card)
  // -------------------------------------------------------------------------

  /// Whether the grant this device holds for [patientId] is read-only.
  ///
  /// It lives in `sync_meta` rather than on the patient row because it is a
  /// property of *this device's* access, not of the patient — the same record
  /// is fully writable for whoever owns it. Keeping it here also means no
  /// schema migration, and a sign-out clears it with everything else.
  static String readOnlyKey(String patientId) => 'read_only_access:$patientId';

  Future<void> setReadOnlyAccess(String patientId, {required bool value}) =>
      set(readOnlyKey(patientId), value ? 'true' : 'false');

  Stream<bool> watchReadOnlyAccess(String patientId) =>
      watch(readOnlyKey(patientId)).map((value) => value == 'true');

  Future<bool> readOnlyAccess(String patientId) async =>
      await get(readOnlyKey(patientId)) == 'true';

  /// Tier 3 — which sections the grant this device holds actually covers.
  ///
  /// Stored as a comma-separated list; empty means the whole record, which is
  /// what every grant meant before fine-grained consent existed. Like the
  /// read-only flag this is a property of *this device's* access, not of the
  /// patient, so it lives here rather than on the patient row.
  static String sectionsKey(String patientId) => 'grant_sections:$patientId';

  Future<void> setGrantSections(String patientId, List<String> sections) =>
      set(sectionsKey(patientId), sections.join(','));

  Stream<List<String>> watchGrantSections(String patientId) {
    return watch(sectionsKey(patientId)).map(_parseSections);
  }

  Future<List<String>> grantSections(String patientId) async =>
      _parseSections(await get(sectionsKey(patientId)));

  /// When this device took an offline snapshot of [patientId], or null when
  /// the record arrived the ordinary way.
  ///
  /// S21 draws its banner from this. It lives beside the read-only flag for
  /// the same reason: it is a fact about *this device's copy*, not about the
  /// patient.
  static String offlineSnapshotKey(String patientId) =>
      'offline_snapshot_at:$patientId';

  Future<void> setOfflineSnapshotAt(String patientId, String iso) =>
      set(offlineSnapshotKey(patientId), iso);

  Stream<DateTime?> watchOfflineSnapshotAt(String patientId) =>
      watch(offlineSnapshotKey(patientId))
          .map((value) => value == null ? null : DateTime.tryParse(value));

  static List<String> _parseSections(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  // -------------------------------------------------------------------------
  // Signed-in user
  // -------------------------------------------------------------------------

  Future<User?> currentUser() async {
    final row = await select(users).getSingleOrNull();
    return row?.toModel();
  }

  Stream<User?> watchCurrentUser() =>
      select(users).watchSingleOrNull().map((row) => row?.toModel());

  /// Only ever one row: signing in as somebody else replaces the previous user.
  Future<void> setCurrentUser(User user) async {
    await transaction(() async {
      await delete(users).go();
      await into(users).insert(user.toCompanion());
    });
  }
}
