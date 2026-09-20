import 'package:drift/drift.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'cache_dao.g.dart';

/// The server-owned tables (spec §6): reminders, audit entries, facilities and
/// codelists. Nothing here is ever enqueued in the outbox — the app only ever
/// replaces a cache with what the server last said, so that S15/S16 and the
/// picklists still render with the network off.
@DriftAccessor(tables: [Reminders, AuditEntries, Facilities, CodelistItems])
class CacheDao extends DatabaseAccessor<AppDatabase> with _$CacheDaoMixin {
  CacheDao(super.db);

  // -------------------------------------------------------------------------
  // Reminders (S15)
  // -------------------------------------------------------------------------

  Stream<List<Reminder>> watchReminders(String patientId) {
    return (select(reminders)
          ..where((t) => t.patientId.equals(patientId))
          ..orderBy([(t) => OrderingTerm.asc(t.dueAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// Replaces this patient's cached reminders with the server's list. A plain
  /// upsert would leave behind reminders the server has since cancelled.
  Future<void> replaceReminders(String patientId, List<Reminder> items) async {
    await transaction(() async {
      await (delete(reminders)..where((t) => t.patientId.equals(patientId)))
          .go();
      await batch((b) {
        b.insertAll(reminders, items.map((r) => r.toCompanion()).toList());
      });
    });
  }

  // -------------------------------------------------------------------------
  // Audit (S16)
  // -------------------------------------------------------------------------

  Stream<List<AuditEntry>> watchAudit(String patientId) {
    return (select(auditEntries)
          ..where((t) => t.patientId.equals(patientId))
          ..orderBy([(t) => OrderingTerm.desc(t.at)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// Audit is append-only on the server, so new pages merge rather than replace.
  Future<void> upsertAudit(List<AuditEntry> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        auditEntries,
        entries.map((e) => e.toCompanion()).toList(),
      );
    });
  }

  // -------------------------------------------------------------------------
  // Codelists — picklists must work before the first sync (seeded from assets)
  // -------------------------------------------------------------------------

  Stream<List<CodeListItem>> watchCodelist(CodeListKind kind) {
    return (select(codelistItems)
          ..where((t) => t.kind.equalsValue(kind))
          ..orderBy([(t) => OrderingTerm.asc(t.labelEn)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<List<CodeListItem>> codelist(CodeListKind kind) async {
    final rows = await (select(codelistItems)
          ..where((t) => t.kind.equalsValue(kind))
          ..orderBy([(t) => OrderingTerm.asc(t.labelEn)]))
        .get();
    return rows.map((r) => r.toModel()).toList();
  }

  Future<CodeListItem?> findCode(CodeListKind kind, String code) async {
    final row = await (select(codelistItems)
          ..where((t) => t.kind.equalsValue(kind) & t.code.equals(code)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<int> codelistCount() async {
    final count = codelistItems.code.count();
    final row =
        await (selectOnly(codelistItems)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> upsertCodelist(List<CodeListItem> items) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        codelistItems,
        items.map((i) => i.toCompanion()).toList(),
      );
    });
  }

  // -------------------------------------------------------------------------
  // Facilities — referral picker and the birth-plan facility field
  // -------------------------------------------------------------------------

  Stream<List<Facility>> watchFacilities() {
    return (select(facilities)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<List<Facility>> facilitiesWithBirthingCentre() async {
    final rows = await (select(facilities)
          ..where((t) => t.hasBirthingCentre.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map((r) => r.toModel()).toList();
  }

  Future<int> facilityCount() async {
    final count = facilities.id.count();
    final row = await (selectOnly(facilities)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> upsertFacilities(List<Facility> items) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        facilities,
        items.map((f) => f.toCompanion()).toList(),
      );
    });
  }
}
