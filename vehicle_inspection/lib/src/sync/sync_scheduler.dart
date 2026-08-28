/// Ability to ask for a sync run.
///
/// Exists so the repository can nudge the engine after enqueuing work without
/// depending on it — the engine depends on the DAOs, and a direct reference the
/// other way would close the loop.
abstract interface class SyncScheduler {
  /// Requests a drain of the queue. Safe to call repeatedly: calls are
  /// debounced and a run already in flight is not duplicated.
  ///
  /// [reason] is for logs only.
  void requestSync({String reason});
}
