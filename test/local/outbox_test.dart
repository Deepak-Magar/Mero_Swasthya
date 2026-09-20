import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/local/converters.dart';
import 'package:mero_swasthya/data/local/outbox.dart';

/// Spec §7: the engine pushes `created_at` ascending, in batches of 50, and
/// leaves rejected ops alone until the user acts on them in S17.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> enqueue(String rowId, {String table = SyncTables.visits}) {
    return db.outboxDao.enqueue(
      table: table,
      op: OutboxOp.upsert,
      rowId: rowId,
      baseVersion: 0,
      payload: {'id': rowId},
    );
  }

  group('ordering', () {
    test('ops queued in the same millisecond keep their insertion order',
        () async {
      // A pregnancy registration enqueues a parent and its children inside one
      // transaction: if these tie on created_at the server can see a child
      // first and reject it.
      final ids = <String>[];
      for (var i = 0; i < 25; i++) {
        ids.add(await enqueue('row_$i'));
      }

      final queued = await db.outboxDao.take();
      expect(queued.map((op) => op.opId), ids);

      final timestamps = queued.map((op) => op.createdAt).toList();
      expect(
        timestamps,
        List.of(timestamps)..sort(),
        reason: 'created_at must be non-decreasing',
      );
      expect(
        timestamps.toSet(),
        hasLength(timestamps.length),
        reason: 'and strictly increasing, so ORDER BY cannot tie',
      );
    });

    test('ordering survives a restart of the process', () async {
      await enqueue('row_a');

      // A second DAO over the same database stands in for a fresh launch: the
      // next timestamp still has to beat what is already queued.
      final reopened = OutboxDao(db);
      await reopened.enqueue(
        table: SyncTables.visits,
        op: OutboxOp.upsert,
        rowId: 'row_b',
        baseVersion: 0,
        payload: const {},
      );

      final queued = await db.outboxDao.take();
      expect(queued.map((op) => op.rowId), ['row_a', 'row_b']);
    });

    test('take returns at most one batch', () async {
      for (var i = 0; i < OutboxDao.batchSize + 10; i++) {
        await enqueue('row_$i');
      }
      expect(await db.outboxDao.take(), hasLength(OutboxDao.batchSize));
    });
  });

  group('failure handling', () {
    test('a rejected op is skipped by take but still visible to S17', () async {
      final rejected = await enqueue('row_a');
      await enqueue('row_b');

      await db.outboxDao.markError(rejected, 'RULE_VIOLATION: EDD in the past');

      expect((await db.outboxDao.take()).map((op) => op.rowId), ['row_b']);
      expect(
        (await db.outboxDao.watchFailed().first).single.lastError,
        'RULE_VIOLATION: EDD in the past',
      );
    });

    test('retry clears the message and requeues the op', () async {
      final opId = await enqueue('row_a');
      await db.outboxDao.markError(opId, 'RATE_LIMITED');
      expect(await db.outboxDao.take(), isEmpty);

      await db.outboxDao.retry(opId);

      final queued = await db.outboxDao.take();
      expect(queued.single.opId, opId);
      expect(queued.single.lastError, isNull);
    });

    test('markAttempt counts transport failures without dequeuing', () async {
      final opId = await enqueue('row_a');

      await db.outboxDao.markAttempt(opId);
      await db.outboxDao.markAttempt(opId);

      final op = await db.outboxDao.findById(opId);
      expect(op!.attempts, 2);
      expect(await db.outboxDao.take(), hasLength(1));
    });
  });

  group('pending rows', () {
    test('hasPendingOp reports rows the pull must not overwrite', () async {
      final opId = await enqueue('row_a');

      expect(await db.outboxDao.hasPendingOp('row_a'), isTrue);
      expect(await db.outboxDao.hasPendingOp('row_b'), isFalse);

      await db.outboxDao.remove(opId);
      expect(await db.outboxDao.hasPendingOp('row_a'), isFalse);
    });

    test('a rejected op still counts as pending for its row', () async {
      // The local row is ahead of the server and the user has not discarded it,
      // so a pull must not quietly replace what they typed.
      final opId = await enqueue('row_a');
      await db.outboxDao.markError(opId, 'VALIDATION_ERROR');

      expect(await db.outboxDao.hasPendingOp('row_a'), isTrue);
    });

    test('pendingRowIds deduplicates repeated edits of one row', () async {
      await enqueue('row_a');
      await enqueue('row_a');
      await enqueue('row_b');

      expect(await db.outboxDao.pendingRowIds(), {'row_a', 'row_b'});
    });

    test('watchPendingCount ignores rejected ops', () async {
      final opId = await enqueue('row_a');
      await enqueue('row_b');
      await db.outboxDao.markError(opId, 'RULE_VIOLATION');

      expect(await db.outboxDao.watchPendingCount().first, 1);
    });
  });

  test('server-owned tables cannot be enqueued', () {
    expect(
      () => enqueue('r1', table: 'reminders'),
      throwsA(isA<AssertionError>()),
    );
  });
}
