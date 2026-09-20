import '../local/app_database.dart';

/// What S17 and the app-bar chip show (spec §9 `syncStatusProvider`, S17).
///
/// A plain value class rather than a freezed model: nothing here crosses the
/// wire, so it has no place in the Part A entity file.
class SyncStatus {
  const SyncStatus({
    this.online = false,
    this.running = false,
    this.pending = 0,
    this.lastSyncAt,
    this.errors = const <OutboxRow>[],
    this.stuckUploads = 0,
  });

  final bool online;

  /// A cycle is in progress — the chip spins rather than changing colour.
  final bool running;

  /// Ops waiting to go out, excluding ones the server rejected.
  final int pending;

  final String? lastSyncAt;

  /// Rejected ops, each with the server's message. S17 offers retry or discard.
  final List<OutboxRow> errors;

  /// Documents whose image ran out of upload retries.
  final int stuckUploads;

  bool get hasErrors => errors.isNotEmpty;

  /// Spec S17: grey = offline, amber = N pending, green = synced.
  SyncChipState get chip {
    if (!online) return SyncChipState.offline;
    if (hasErrors) return SyncChipState.failed;
    if (pending > 0) return SyncChipState.pending;
    return SyncChipState.synced;
  }

  SyncStatus copyWith({
    bool? online,
    bool? running,
    int? pending,
    String? lastSyncAt,
    List<OutboxRow>? errors,
    int? stuckUploads,
  }) {
    return SyncStatus(
      online: online ?? this.online,
      running: running ?? this.running,
      pending: pending ?? this.pending,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      errors: errors ?? this.errors,
      stuckUploads: stuckUploads ?? this.stuckUploads,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.online == online &&
      other.running == running &&
      other.pending == pending &&
      other.lastSyncAt == lastSyncAt &&
      other.stuckUploads == stuckUploads &&
      other.errors.length == errors.length;

  @override
  int get hashCode =>
      Object.hash(online, running, pending, lastSyncAt, stuckUploads,
          errors.length);

  @override
  String toString() =>
      'SyncStatus(${chip.name}, pending: $pending, errors: ${errors.length})';
}

enum SyncChipState { offline, pending, failed, synced }

/// What one [SyncEngine.run] did, so a "Sync now" button can report something
/// more useful than a spinner that stops.
class SyncOutcome {
  const SyncOutcome({
    this.skipped = false,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.uploaded = 0,
    this.failedWithNetworkError = false,
  });

  /// The cycle did not run: offline, or another cycle held the mutex.
  final bool skipped;

  final int pushed;
  final int pulled;

  /// Ops the server answered with `conflict`; the local row was replaced.
  final int conflicts;

  final int rejected;
  final int uploaded;

  /// The request never landed. Everything is still queued.
  final bool failedWithNetworkError;

  bool get didAnything => pushed > 0 || pulled > 0 || uploaded > 0;

  @override
  String toString() => 'SyncOutcome(skipped: $skipped, pushed: $pushed, '
      'pulled: $pulled, conflicts: $conflicts, rejected: $rejected, '
      'uploaded: $uploaded)';
}
