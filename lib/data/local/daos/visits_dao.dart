import 'package:drift/drift.dart';

import '../../../domain/models/models.dart';
import '../app_database.dart';
import '../mappers.dart';

part 'visits_dao.g.dart';

@DriftAccessor(tables: [Visits])
class VisitsDao extends DatabaseAccessor<AppDatabase> with _$VisitsDaoMixin {
  VisitsDao(super.db);

  /// S09 timeline and S08 patient home — newest visit first.
  Stream<List<Visit>> watchByPatient(String patientId) {
    return (select(visits)
          ..where((t) => t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.visitAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  /// Visits are append-only, so "the latest" is simply the newest row; S08 uses
  /// it for the last-vitals block when the server summary is unavailable.
  Future<Visit?> latestForPatient(String patientId) async {
    final row = await (select(visits)
          ..where((t) => t.patientId.equals(patientId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.visitAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.toModel();
  }

  /// Every visit on this device from [fromIso] onwards — the provider Home
  /// tab's "visits recorded today".
  ///
  /// `visit_at` is an ISO-8601 string and is compared as text, so the caller
  /// passes a bound a day early and narrows to the exact local day itself: two
  /// stamps a few milliseconds apart are not reliably ordered as text, and a
  /// day's slack costs a handful of rows.
  Stream<List<Visit>> watchSince(String fromIso) {
    return (select(visits)
          ..where((t) =>
              t.visitAt.isBiggerOrEqualValue(fromIso) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.visitAt)]))
        .watch()
        .map((rows) => rows.map((r) => r.toModel()).toList());
  }

  Stream<Visit?> watchById(String id) {
    return (select(visits)..where((t) => t.id.equals(id)))
        .watchSingleOrNull()
        .map((row) => row?.toModel());
  }

  Future<Visit?> findById(String id) async {
    final row =
        await (select(visits)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toModel();
  }

  Future<void> upsert(Visit visit) =>
      into(visits).insertOnConflictUpdate(visit.toCompanion());

  Future<void> upsertFromServer(Map<String, dynamic> json) =>
      upsert(Visit.fromJson(json));

  Future<bool> upsertIfNewer(Map<String, dynamic> json) async {
    final incoming = Visit.fromJson(json);
    final local = await findById(incoming.id);
    if (local != null && incoming.version <= local.version) return false;
    await upsert(incoming);
    return true;
  }
}
