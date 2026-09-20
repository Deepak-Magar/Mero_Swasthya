import 'package:drift/drift.dart';

import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'child_health_dao.g.dart';

/// Tier 3 — immunisations and growth measurements.
///
/// Both tables are additive to Part A (see `docs/CONTRACT_ADDENDUM.md`) and
/// both follow the same rules as everything else syncable: the screen reads the
/// local database, the repository is the only write path, and every write ends
/// with an outbox row.
@DriftAccessor(tables: [Immunisations, GrowthMeasurements])
class ChildHealthDao extends DatabaseAccessor<AppDatabase>
    with _$ChildHealthDaoMixin {
  ChildHealthDao(super.db);

  // -------------------------------------------------------------------------
  // Immunisations
  // -------------------------------------------------------------------------

  /// The child's whole schedule, in the order the doses fall due.
  ///
  /// Ordered by `due_at` and then by vaccine code so two doses due the same day
  /// — and at six weeks there are five — come out in a stable order rather than
  /// shuffling between rebuilds.
  Stream<List<Immunisation>> watchSchedule(String patientId) {
    return (select(immunisations)
          ..where((t) =>
              t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dueAt),
            (t) => OrderingTerm.asc(t.vaccineCode),
            (t) => OrderingTerm.asc(t.doseNo),
          ]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<List<Immunisation>> schedule(String patientId) async {
    final rows = await (select(immunisations)
          ..where((t) =>
              t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dueAt),
            (t) => OrderingTerm.asc(t.vaccineCode),
            (t) => OrderingTerm.asc(t.doseNo),
          ]))
        .get();
    return rows.map((r) => r.toModel()).toList();
  }

  Future<Immunisation?> findImmunisation(String id) async {
    final row = await (select(immunisations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.toModel();
  }

  Future<int> countFor(String patientId) async {
    final rows = await (select(immunisations)
          ..where((t) => t.patientId.equals(patientId)))
        .get();
    return rows.length;
  }

  Future<void> upsertImmunisation(Immunisation row) =>
      into(immunisations).insertOnConflictUpdate(row.toCompanion());

  Future<void> upsertImmunisations(List<Immunisation> rows) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(
        immunisations,
        rows.map((r) => r.toCompanion()).toList(),
      );
    });
  }

  Future<void> upsertImmunisationFromServer(Map<String, dynamic> json) =>
      upsertImmunisation(Immunisation.fromJson(json));

  Future<bool> upsertImmunisationIfNewer(Map<String, dynamic> json) async {
    final incoming = Immunisation.fromJson(json);
    final local = await findImmunisation(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsertImmunisation(incoming);
    return true;
  }

  // -------------------------------------------------------------------------
  // Growth
  // -------------------------------------------------------------------------

  /// Oldest first, which is the order a chart wants to draw them in.
  Stream<List<GrowthMeasurement>> watchGrowth(String patientId) {
    return (select(growthMeasurements)
          ..where((t) =>
              t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.measuredAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Future<GrowthMeasurement?> findGrowth(String id) async {
    final row =
        await (select(growthMeasurements)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row?.toModel();
  }

  Future<void> upsertGrowth(GrowthMeasurement row) =>
      into(growthMeasurements).insertOnConflictUpdate(row.toCompanion());

  Future<void> upsertGrowthFromServer(Map<String, dynamic> json) =>
      upsertGrowth(GrowthMeasurement.fromJson(json));

  Future<bool> upsertGrowthIfNewer(Map<String, dynamic> json) async {
    final incoming = GrowthMeasurement.fromJson(json);
    final local = await findGrowth(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsertGrowth(incoming);
    return true;
  }

  // -------------------------------------------------------------------------
  // Whole-device reads (the provider dashboard could grow to use these)
  // -------------------------------------------------------------------------

  Stream<List<Immunisation>> watchAllImmunisations() {
    return (select(immunisations)..where((t) => t.deleted.equals(false)))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }
}
