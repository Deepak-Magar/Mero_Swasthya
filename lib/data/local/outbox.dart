import 'package:drift/drift.dart';

import '../../core/ids/ids.dart';
import 'app_database.dart';
import 'converters.dart';

part 'outbox.g.dart';

/// The outbox (spec §6, §7) — every local write on a syncable table appends one
/// row here, and the sync engine drains it oldest-first.
@DriftAccessor(tables: [Outbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  /// Spec §7: the engine pushes in batches of 50, `createdAt` ascending.
  static const int batchSize = 50;

  /// Appends one operation.
  ///
  /// `createdAt` is forced to be strictly greater than every timestamp already
  /// queued. Ordering is the whole contract here — registering a pregnancy
  /// enqueues the pregnancy and its eight ANC contacts inside one transaction,
  /// within the same millisecond, and the server has to see the parent first.
  /// A plain `DateTime.now()` would tie and let `ORDER BY created_at` return
  /// them in any order.
  Future<String> enqueue({
    required String table,
    required OutboxOp op,
    required String rowId,
    required int baseVersion,
    required Map<String, dynamic> payload,
  }) async {
    assert(
      SyncTables.pushable.contains(table),
      '$table is server-owned and must never be pushed',
    );

    final opId = newOpId();
    final latest = await _latestCreatedAt();
    // Millisecond precision, deliberately. `created_at` is a TEXT column and
    // both the batch query and the `max()` above compare it as text, while
    // `toIso8601String()` prints three fractional digits when the microseconds
    // happen to be zero and six when they are not — so "…12.123Z" sorts
    // *after* "…12.123456Z" and two ops queued inside the same millisecond can
    // come back swapped. Truncating makes every stamp the same width.
    var now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
    if (latest != null && !now.isAfter(latest)) {
      now = latest.add(const Duration(milliseconds: 1));
    }

    await into(outbox).insert(
      OutboxCompanion.insert(
        opId: opId,
        targetTable: table,
        op: op,
        rowId: rowId,
        baseVersion: baseVersion,
        payload: payload,
        createdAt: now.toIso8601String(),
      ),
    );
    return opId;
  }

  Future<DateTime?> _latestCreatedAt() async {
    final max = outbox.createdAt.max();
    final row = await (selectOnly(outbox)..addColumns([max])).getSingleOrNull();
    final value = row?.read(max);
    return value == null ? null : DateTime.tryParse(value)?.toUtc();
  }

  /// The next batch to push.
  ///
  /// Ops the server rejected are skipped: spec §7 keeps them visible in S17
  /// with the server's message until the user retries or discards, so retrying
  /// them automatically would spin the queue on a permanent error.
  Future<List<OutboxRow>> take([int limit = batchSize]) {
    return (select(outbox)
          ..where((t) => t.lastError.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<OutboxRow?> findById(String opId) =>
      (select(outbox)..where((t) => t.opId.equals(opId))).getSingleOrNull();

  /// Applied, duplicated or conflict-resolved — the op is settled either way.
  Future<void> remove(String opId) =>
      (delete(outbox)..where((t) => t.opId.equals(opId))).go();

  /// Rejected by the server. The row stays so S17 can show [message].
  Future<void> markError(String opId, String message) {
    return (update(outbox)..where((t) => t.opId.equals(opId))).write(
      OutboxCompanion(
        lastError: Value(message),
        attempts: const Value.absent(),
      ),
    );
  }

  /// A transport failure, as opposed to a rejection: count it and leave the op
  /// queued so the next cycle retries it.
  Future<void> markAttempt(String opId) async {
    await customUpdate(
      'UPDATE outbox SET attempts = attempts + 1 WHERE op_id = ?',
      variables: [Variable<String>(opId)],
      updates: {outbox},
      updateKind: UpdateKind.update,
    );
  }

  /// S17 "retry": clears the server message so [take] picks the op up again.
  Future<void> retry(String opId) {
    return (update(outbox)..where((t) => t.opId.equals(opId)))
        .write(const OutboxCompanion(lastError: Value(null)));
  }

  /// Ops the server rejected, newest first — the S17 error list.
  Stream<List<OutboxRow>> watchFailed() {
    return (select(outbox)
          ..where((t) => t.lastError.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Stream<int> watchPendingCount() {
    final count = outbox.opId.count();
    return (selectOnly(outbox)
          ..addColumns([count])
          ..where(outbox.lastError.isNull()))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Every op that has not reached the server, rejected ones included.
  ///
  /// The provider Home tab's "pending sync" tile. It differs from
  /// [watchPendingCount] on purpose: a rejected op is still a change that is
  /// only on this phone, and a tile reading 0 beside a sync pill reading "Not
  /// synced" would be the two of them disagreeing about the same queue.
  Stream<int> watchUnsettledCount() {
    final count = outbox.opId.count();
    return (selectOnly(outbox)..addColumns([count]))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }

  /// Row ids with an unsettled op, for the "pending" cloud icon (spec §7) and
  /// for the pull step, which must not overwrite a row that is still queued.
  Stream<Set<String>> watchPendingRowIds() {
    return (selectOnly(outbox, distinct: true)..addColumns([outbox.rowId]))
        .map((row) => row.read(outbox.rowId)!)
        .watch()
        .map((ids) => ids.toSet());
  }

  Future<Set<String>> pendingRowIds() async {
    final rows = await (selectOnly(outbox, distinct: true)
          ..addColumns([outbox.rowId]))
        .map((row) => row.read(outbox.rowId)!)
        .get();
    return rows.toSet();
  }

  /// True while [rowId] has an unsettled op, so a pull must leave it alone.
  Future<bool> hasPendingOp(String rowId) async {
    final count = outbox.opId.count();
    final row = await (selectOnly(outbox)
          ..addColumns([count])
          ..where(outbox.rowId.equals(rowId)))
        .getSingle();
    return (row.read(count) ?? 0) > 0;
  }

  Future<void> clear() => delete(outbox).go();
}
