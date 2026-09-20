import '../local/app_database.dart';
import '../local/converters.dart';
import 'sync_kicker.dart';

/// Shared write path for the six client-writable tables (spec §6.2).
///
/// Every local write does exactly two things, in one transaction: it writes the
/// row, and it appends the matching outbox op. If the transaction rolls back,
/// neither happened — the alternative is a row the server never hears about, or
/// an op for a row that does not exist.
///
/// The kick is deliberately outside the transaction and deliberately not
/// awaited: the UI must return the moment the row is durable, whether or not
/// there is a network.
abstract class SyncableRepo {
  const SyncableRepo(this.db, this.sync);

  final AppDatabase db;
  final SyncKicker sync;

  /// [baseVersion] is 0 for a create and the row's current version for an edit;
  /// the server compares it and answers `applied` or `conflict` (spec A.4).
  Future<void> writeAndEnqueue({
    required Future<void> Function() write,
    required String table,
    required String rowId,
    required int baseVersion,
    required Map<String, dynamic> payload,
    OutboxOp op = OutboxOp.upsert,
  }) async {
    await db.transaction(() async {
      await write();
      await db.outboxDao.enqueue(
        table: table,
        op: op,
        rowId: rowId,
        baseVersion: baseVersion,
        payload: payload,
      );
    });
    sync.kick();
  }
}
