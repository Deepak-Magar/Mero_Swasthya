import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../local/app_database.dart';
import '../local/outbox.dart';
import '../remote/api/api.dart';
import '../repositories/sync_kicker.dart';
import 'connectivity.dart';
import 'sync_status.dart';
import 'upload_worker.dart';

/// Spec §7 — one singleton, started after PIN unlock.
///
/// Triggers: connectivity changes, app resume, a manual [kick] from any
/// repository write, and a 60-second timer while the app is in the foreground.
/// It owns a mutex so only one push/pull cycle runs at a time.
///
/// The ordering inside a cycle is not arbitrary. Push first, so the user's own
/// work is the thing that reaches the server soonest and so the pull that
/// follows already includes it. Uploads next, because a document's metadata row
/// has to exist server-side before its bytes are presigned. Pull last, so the
/// cycle ends with the device holding everything.
class SyncEngine implements SyncKicker {
  SyncEngine({
    required this.db,
    required this.api,
    required this.connectivity,
    UploadWorker? uploadWorker,
    this.period = const Duration(seconds: 60),
    this.onConflict,
    this.onTriageMismatch,
  }) : uploadWorker = uploadWorker ?? UploadWorker(db: db, api: api);

  final AppDatabase db;
  final Api api;
  final ConnectivityMonitor connectivity;
  final UploadWorker uploadWorker;

  /// Foreground poll interval (spec §7).
  final Duration period;

  /// Spec §7 asks for a "Updated from server" toast when a conflict replaces
  /// what the user typed. The engine has no BuildContext, so it reports and the
  /// UI decides.
  final void Function(String table, String rowId)? onConflict;

  /// Spec S13: the app "MUST display the server value if they differ (log a
  /// warning)". The engine logs; a listener can also surface it.
  final void Function(String contactId, TriageLevel local, TriageLevel? server)?
      onTriageMismatch;

  final StreamController<SyncStatus> _status =
      StreamController<SyncStatus>.broadcast();
  final List<StreamSubscription<void>> _subscriptions = [];

  Timer? _timer;
  bool _running = false;
  bool _started = false;
  bool _online = false;

  /// Set while a cycle is running if something asked for another one. Spec §7
  /// says `kick()` is non-blocking and the mutex makes it a no-op, but dropping
  /// it entirely would lose the write that triggered it until the next timer
  /// tick — up to a minute of a health worker staring at a pending icon.
  bool _rerunRequested = false;

  Stream<SyncStatus> get status => _status.stream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Called once, after the PIN unlocks the database.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _online = await connectivity.isOnline();

    _subscriptions.add(
      connectivity.onChanged.listen((online) {
        _online = online;
        unawaited(_publishStatus());
        // Coming back online is the moment that matters; going offline only
        // changes the chip.
        if (online) unawaited(run());
      }),
    );

    // Any change to the outbox moves the pending count and the error list.
    _subscriptions.add(
      db.outboxDao.watchPendingCount().listen((_) => unawaited(_publishStatus())),
    );

    _timer = Timer.periodic(period, (_) => unawaited(run()));

    await _publishStatus();
    await run();
  }

  /// Spec §6.2: every repository write ends with this. Non-blocking.
  ///
  /// Ignored until [start] has run. An implicit trigger before the PIN unlock
  /// would push with no session, take a 401, burn the refresh token and drop
  /// the user back to the login screen. An explicit [run] — S17's "Sync now" —
  /// is not gated, because reaching that screen means already being unlocked.
  @override
  void kick() {
    if (!_started) return;
    unawaited(run());
  }

  /// Wired to `AppLifecycleState.resumed` in `app.dart` (spec §7 trigger).
  void onResume() => kick();

  /// True once [start] has run, so the lifecycle listener can tell the
  /// difference between "not unlocked yet" and "idle".
  bool get isStarted => _started;

  Future<void> dispose() async {
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _status.close();
  }

  // ---------------------------------------------------------------------------
  // The cycle
  // ---------------------------------------------------------------------------

  Future<SyncOutcome> run() async {
    if (_running) {
      _rerunRequested = true;
      return const SyncOutcome(skipped: true);
    }

    // Claim the mutex *before* the first await. Checking `_running` and then
    // awaiting the connectivity probe would let two near-simultaneous kicks
    // both pass the test and run overlapping cycles, pushing the same ops
    // twice — survivable, because the server is idempotent by opId, but it
    // would also double the pull work and race two writers into one table.
    _running = true;

    var outcome = const SyncOutcome(skipped: true);
    try {
      _online = await connectivity.isOnline();
      if (_online) {
        await _publishStatus();
        outcome = await _cycle();
      }
    } finally {
      _running = false;
      await _publishStatus();
    }

    // A kick that arrived mid-cycle asked for work this cycle may have started
    // too early to see.
    final rerunWanted = _rerunRequested;
    _rerunRequested = false;
    if (rerunWanted && _online && !outcome.failedWithNetworkError) {
      await run();
    }

    return outcome;
  }

  Future<SyncOutcome> _cycle() async {
    var pushed = 0;
    var conflicts = 0;
    var rejected = 0;
    var uploaded = 0;
    var pulled = 0;

    try {
      final push = await _pushOutbox();
      pushed = push.pushed;
      conflicts = push.conflicts;
      rejected = push.rejected;

      uploaded = await uploadWorker.run();
      pulled = await _pull();

      await db.syncMetaDao.set(SyncMetaKeys.lastPullAt, _nowIso());
    } on AppError catch (e) {
      if (!e.isNetwork) debugPrint('[sync] cycle failed: $e');
      // Nothing is lost: the outbox still holds every unsent op and the pull
      // cursor has only moved for pages that actually arrived.
      return SyncOutcome(
        pushed: pushed,
        conflicts: conflicts,
        rejected: rejected,
        uploaded: uploaded,
        pulled: pulled,
        failedWithNetworkError: e.isNetwork,
      );
    }

    return SyncOutcome(
      pushed: pushed,
      conflicts: conflicts,
      rejected: rejected,
      uploaded: uploaded,
      pulled: pulled,
    );
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<({int pushed, int conflicts, int rejected})> _pushOutbox() async {
    var pushed = 0;
    var conflicts = 0;
    var rejected = 0;

    // Spec §7 recurses while a full batch comes back; a loop does the same
    // without risking a deep stack on a phone that has been offline for a week.
    while (true) {
      final ops = await db.outboxDao.take();
      if (ops.isEmpty) break;

      final response = await api.sync.push(
        deviceId: await db.syncMetaDao.deviceId(),
        changes: ops.map(_toChange).toList(growable: false),
      );

      final byId = {for (final op in ops) op.opId: op};
      for (final result in response.results) {
        final op = byId[result.opId];
        if (op == null) continue;

        switch (result.status) {
          case SyncOpStatus.applied:
          case SyncOpStatus.duplicate:
            // `duplicate` means the server already had this opId — the previous
            // attempt landed and only the response was lost.
            if (result.row != null) {
              await _applyFromServer(op.targetTable, result.row!);
            }
            await db.outboxDao.remove(op.opId);
            pushed++;

          case SyncOpStatus.conflict:
            // The server's row wins. The user's edit is not silently kept —
            // spec §7 replaces the local row and tells them.
            if (result.current != null) {
              await _applyFromServer(op.targetTable, result.current!);
            }
            await db.outboxDao.remove(op.opId);
            onConflict?.call(op.targetTable, op.rowId);
            conflicts++;

          case SyncOpStatus.rejected:
            // Retrying cannot fix a rule violation, so the op stays put with
            // the server's message for S17 to show.
            await db.outboxDao.markError(
              op.opId,
              result.error?.message ?? 'Rejected by the server',
            );
            rejected++;
        }
      }

      await _recordServerTime(response.serverTime);

      if (ops.length < OutboxDao.batchSize) break;
    }

    if (pushed > 0 || conflicts > 0) {
      await db.syncMetaDao.set(SyncMetaKeys.lastPushAt, _nowIso());
    }
    return (pushed: pushed, conflicts: conflicts, rejected: rejected);
  }

  SyncChange _toChange(OutboxRow op) => SyncChange(
        opId: op.opId,
        table: op.targetTable,
        op: op.op.wire,
        rowId: op.rowId,
        baseVersion: op.baseVersion,
        payload: op.payload,
      );

  /// Spec §7: `server_time_offset_ms = serverTime - now`. A phone with a wrong
  /// clock would otherwise show "in 3 hours" next to a reminder due today.
  Future<void> _recordServerTime(String serverTime) async {
    final server = DateTime.tryParse(serverTime);
    if (server == null) return;

    await db.syncMetaDao.setServerTimeOffsetMs(
      server.millisecondsSinceEpoch -
          DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  // ---------------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------------

  Future<int> _pull() async {
    var since = await db.syncMetaDao.pullCursor();
    final deviceId = await db.syncMetaDao.deviceId();
    var applied = 0;

    while (true) {
      final response = await api.sync.pull(since: since, deviceId: deviceId);

      // Read once per page rather than per row: a page is 200 rows and the set
      // cannot change while this cycle holds the mutex.
      final pending = await db.outboxDao.pendingRowIds();

      for (final change in response.changes) {
        final rowId = change.row['id'];
        // Spec §7: never overwrite a row that still has a pending op. The push
        // result will settle it, and clobbering it here would throw away
        // something the user typed and has not seen sent yet.
        if (rowId is String && pending.contains(rowId)) continue;

        if (await _applyIfNewer(change.table, change.row)) applied++;
      }

      since = response.cursor;
      await db.syncMetaDao.setPullCursor(since);

      if (!response.hasMore) break;
    }

    return applied;
  }

  // ---------------------------------------------------------------------------
  // Table dispatch
  // ---------------------------------------------------------------------------

  /// A row the server just handed back: applied unconditionally, because it is
  /// by definition newer than what we sent.
  Future<void> _applyFromServer(String table, Map<String, dynamic> row) async {
    switch (table) {
      case SyncTables.patients:
        await db.patientsDao.upsertFromServer(row);
      case SyncTables.visits:
        await db.visitsDao.upsertFromServer(row);
      case SyncTables.documents:
        await db.documentsDao.upsertFromServer(row);
      case SyncTables.pregnancies:
        await db.pregnanciesDao.upsertPregnancyFromServer(row);
      case SyncTables.ancContacts:
        // Spec S13 / A.4: the server recomputes triage from the same RULES and
        // its answer wins. If the two ever disagree the rule tables have
        // drifted apart, which the A.6 cases exist to prevent — so say so
        // loudly rather than letting a red quietly become a green.
        await _warnIfTriageDiffers(row);
        await db.pregnanciesDao.upsertContactFromServer(row);
      case SyncTables.deliveries:
        await db.pregnanciesDao.upsertDeliveryFromServer(row);
      case SyncTables.immunisations:
        await db.childHealthDao.upsertImmunisationFromServer(row);
      case SyncTables.growthMeasurements:
        await db.childHealthDao.upsertGrowthFromServer(row);
      default:
        debugPrint('[sync] ignoring push result for unknown table "$table"');
    }
  }

  Future<void> _warnIfTriageDiffers(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id is! String) return;

    final local = await db.pregnanciesDao.findContact(id);
    if (local?.triageLevel == null) return;

    final serverLevel = TriageLevel.fromWire(row['triageLevel'] as String?);
    if (serverLevel == local!.triageLevel) return;

    debugPrint(
      '[sync] TRIAGE MISMATCH on contact $id: local '
      '${local.triageLevel?.wire}, server ${serverLevel?.wire}. '
      'The server value has been applied. Rule tables may have drifted — '
      'check RULES.version on both sides against spec A.6.',
    );
    onTriageMismatch?.call(id, local.triageLevel!, serverLevel);
  }

  /// A pulled row: applied only if its version beats the local one.
  ///
  /// An unknown table is skipped rather than fatal — a backend that starts
  /// sending a table this build predates should not stop the cycle, and the
  /// cursor still advances past it.
  Future<bool> _applyIfNewer(String table, Map<String, dynamic> row) async {
    try {
      return switch (table) {
        SyncTables.patients => await db.patientsDao.upsertIfNewer(row),
        SyncTables.visits => await db.visitsDao.upsertIfNewer(row),
        SyncTables.documents => await db.documentsDao.upsertIfNewer(row),
        SyncTables.pregnancies =>
          await db.pregnanciesDao.upsertPregnancyIfNewer(row),
        SyncTables.ancContacts =>
          await db.pregnanciesDao.upsertContactIfNewer(row),
        SyncTables.deliveries =>
          await db.pregnanciesDao.upsertDeliveryIfNewer(row),
        SyncTables.immunisations =>
          await db.childHealthDao.upsertImmunisationIfNewer(row),
        SyncTables.growthMeasurements =>
          await db.childHealthDao.upsertGrowthIfNewer(row),
        _ => _skipUnknown(table),
      };
    } on Object catch (e) {
      // One malformed row must not strand the cursor and block every later
      // page for good.
      debugPrint('[sync] skipping unparseable $table row: $e');
      return false;
    }
  }

  bool _skipUnknown(String table) {
    debugPrint('[sync] ignoring pulled row for unknown table "$table"');
    return false;
  }

  // ---------------------------------------------------------------------------
  // S17 actions
  // ---------------------------------------------------------------------------

  /// "Retry" on a rejected op: clear the message so the next cycle picks it up.
  Future<void> retry(String opId) async {
    await db.outboxDao.retry(opId);
    kick();
  }

  /// "Discard" on a rejected op.
  ///
  /// Spec §7: discarding also deletes the local row if the op was a create.
  /// Leaving it would show the user a record that exists nowhere else and will
  /// never sync — worse than it disappearing after they chose to drop it.
  Future<void> discard(String opId) async {
    final op = await db.outboxDao.findById(opId);
    if (op == null) return;

    await db.transaction(() async {
      if (op.baseVersion == 0) {
        await _deleteLocalRow(op.targetTable, op.rowId);
      }
      await db.outboxDao.remove(opId);
    });
  }

  Future<void> _deleteLocalRow(String table, String rowId) async {
    switch (table) {
      case SyncTables.patients:
        await (db.delete(db.patients)..where((t) => t.id.equals(rowId))).go();
      case SyncTables.visits:
        await (db.delete(db.visits)..where((t) => t.id.equals(rowId))).go();
      case SyncTables.documents:
        await (db.delete(db.documents)..where((t) => t.id.equals(rowId))).go();
      case SyncTables.pregnancies:
        await (db.delete(db.pregnancies)..where((t) => t.id.equals(rowId))).go();
      case SyncTables.ancContacts:
        await (db.delete(db.ancContacts)..where((t) => t.id.equals(rowId))).go();
      case SyncTables.deliveries:
        await (db.delete(db.deliveries)..where((t) => t.id.equals(rowId))).go();
      default:
        debugPrint('[sync] cannot discard a row in unknown table "$table"');
    }
  }

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  Future<void> _publishStatus() async {
    if (_status.isClosed) return;

    _status.add(
      SyncStatus(
        online: _online,
        running: _running,
        pending: await db.outboxDao.watchPendingCount().first,
        lastSyncAt: await db.syncMetaDao.get(SyncMetaKeys.lastPullAt),
        errors: await db.outboxDao.watchFailed().first,
        stuckUploads: (await db.documentsDao.watchStuckUploads().first).length,
      ),
    );
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}
