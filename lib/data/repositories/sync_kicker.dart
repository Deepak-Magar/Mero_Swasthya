/// Lets a repository nudge the sync engine without depending on it.
///
/// Spec §6.2 ends every write with a non-blocking `syncEngine.kick()`. The
/// engine itself arrives with the sync step; until then repositories take
/// [NoopSyncKicker] and behave exactly as they will later — the write is
/// already durable in the outbox, and the kick only decides how soon it leaves.
abstract interface class SyncKicker {
  /// Ask for a push/pull cycle. Must return immediately; the engine holds a
  /// mutex and ignores the call if a cycle is already running.
  void kick();
}

/// Used in tests, in mock mode, and before the engine is wired up.
class NoopSyncKicker implements SyncKicker {
  const NoopSyncKicker();

  @override
  void kick() {}
}
