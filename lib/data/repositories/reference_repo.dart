import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/errors/app_error.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../local/app_database.dart';
import '../remote/api/api.dart';

/// The read-only halves of the record: reminders (S15), audit (S16), and the
/// picklists and facilities every form depends on.
///
/// The pattern is the same in all four cases and is the whole reason these are
/// repositories rather than direct API calls: **the screen reads the local
/// cache, and a refresh is a side effect that may fail**. Losing the network
/// must never empty a list the user was already looking at.
class ReferenceRepo {
  const ReferenceRepo(this.db, this.api);

  final AppDatabase db;
  final Api api;

  // -------------------------------------------------------------------------
  // Reminders (S15)
  // -------------------------------------------------------------------------

  Stream<List<Reminder>> watchReminders(String patientId) =>
      db.cacheDao.watchReminders(patientId);

  /// Returns true when the cache was refreshed, false when the request failed
  /// and the cached rows were left alone.
  Future<bool> refreshReminders(String patientId) async {
    try {
      final items = await api.patients.reminders(patientId);
      await db.cacheDao.replaceReminders(patientId, items);
      return true;
    } on AppError {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Audit (S16)
  // -------------------------------------------------------------------------

  Stream<List<AuditEntry>> watchAudit(String patientId) =>
      db.cacheDao.watchAudit(patientId);

  /// Record that a record was opened from an offline snapshot.
  ///
  /// Written locally because there is no server in this flow at all — that is
  /// the whole point of it. It merges with whatever the server sends later,
  /// since the audit table is append-only and keyed by id.
  Future<void> recordOfflineSnapshot(String patientId, {DateTime? at}) {
    final when = (at ?? DateTime.now().toUtc()).toIso8601String();
    return db.cacheDao.upsertAudit([
      AuditEntry(
        id: 'offline:$patientId:$when',
        patientId: patientId,
        actorUserId: '',
        action: AuditAction.offlineSnapshot,
        at: when,
      ),
    ]);
  }

  Future<bool> refreshAudit(String patientId) async {
    try {
      // Append-only on the server, so this merges rather than replaces and an
      // older cached page is never thrown away.
      await db.cacheDao.upsertAudit(await api.patients.audit(patientId));
      return true;
    } on AppError {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Codelists — the picklists must work before the first sync ever runs
  // -------------------------------------------------------------------------

  Stream<List<CodeListItem>> watchCodelist(CodeListKind kind) =>
      db.cacheDao.watchCodelist(kind);

  Future<CodeListItem?> findCode(CodeListKind kind, String code) =>
      db.cacheDao.findCode(kind, code);

  /// One-shot read, for code→label lookups that are not rebuilding a widget.
  Future<List<CodeListItem>> codelist(CodeListKind kind) =>
      db.cacheDao.codelist(kind);

  /// Loads `assets/codelists.json` on first launch so S21's picklists are
  /// populated before the device has ever been online (spec §4).
  ///
  /// Does nothing once the table has rows, so it cannot undo a later refresh.
  Future<void> seedFromAssetsIfEmpty() async {
    if (await db.cacheDao.codelistCount() > 0) return;

    final decoded = jsonDecode(
      await rootBundle.loadString('assets/codelists.json'),
    ) as Map<String, dynamic>;

    await db.cacheDao.upsertCodelist(
      (decoded['items'] as List)
          .map((e) => CodeListItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
    await db.syncMetaDao
        .set(SyncMetaKeys.codelistVersion, '${decoded['version'] ?? ''}');
  }

  /// Refreshes only when the server reports a version we do not hold — the
  /// codelists are a few hundred rows and change about never.
  Future<bool> refreshCodelistsIfStale(String serverVersion) async {
    final cached = await db.syncMetaDao.get(SyncMetaKeys.codelistVersion);
    if (cached == serverVersion && await db.cacheDao.codelistCount() > 0) {
      return false;
    }

    try {
      final response = await api.reference.codelists();
      await db.cacheDao.upsertCodelist(response.items);
      await db.syncMetaDao
          .set(SyncMetaKeys.codelistVersion, response.version);
      return true;
    } on AppError {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Facilities — referral picker and the birth-plan facility field
  // -------------------------------------------------------------------------

  Stream<List<Facility>> watchFacilities() => db.cacheDao.watchFacilities();

  Future<List<Facility>> birthingCentres() =>
      db.cacheDao.facilitiesWithBirthingCentre();

  Future<void> seedFacilitiesFromAssetsIfEmpty() async {
    if (await db.cacheDao.facilityCount() > 0) return;

    final decoded =
        jsonDecode(await rootBundle.loadString('assets/facilities.json'));
    final items = decoded is Map ? decoded['items'] as List : decoded as List;

    await db.cacheDao.upsertFacilities(
      items
          .map((e) => Facility.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  /// `GET /facilities/nearby` also refreshes the cache, so the referral picker
  /// keeps working after the provider walks out of coverage.
  Future<List<Facility>> nearbyFacilities({
    required double lat,
    required double lng,
    bool birthingOnly = false,
    int limit = 5,
  }) async {
    try {
      final items = await api.reference.nearbyFacilities(
        lat: lat,
        lng: lng,
        birthingOnly: birthingOnly,
        limit: limit,
      );
      await db.cacheDao.upsertFacilities(items);
      return items;
    } on AppError {
      final cached = birthingOnly
          ? await db.cacheDao.facilitiesWithBirthingCentre()
          : await db.cacheDao.watchFacilities().first;
      return cached.take(limit).toList();
    }
  }
}
