/// What the sync engine is doing right now.
enum SyncPhase {
  /// Nothing queued.
  idle,

  /// Work is queued but the device has no connection.
  waitingForConnection,

  /// Actively uploading.
  syncing,

  /// The last run finished with work still outstanding.
  retryScheduled,

  /// Work has exhausted its retry budget and needs the evaluator.
  failed,
}

/// Snapshot the UI renders as the sync banner and per-row status chips.
class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.isOnline = true,
    this.pendingTasks = 0,
    this.completedInRun = 0,
    this.totalInRun = 0,
    this.lastError,
    this.lastSyncedAt,
  });

  final SyncPhase phase;
  final bool isOnline;

  /// Tasks still in the queue, including those waiting out a backoff.
  final int pendingTasks;

  /// Progress within the current run, so a 20-photo upload shows movement.
  final int completedInRun;
  final int totalInRun;

  final String? lastError;
  final DateTime? lastSyncedAt;

  bool get isBusy => phase == SyncPhase.syncing;
  bool get hasPendingWork => pendingTasks > 0;

  double? get progress =>
      totalInRun == 0 ? null : (completedInRun / totalInRun).clamp(0.0, 1.0);

  /// One line describing the current state, used by the banner.
  String get message => switch (phase) {
        SyncPhase.idle =>
          pendingTasks == 0 ? 'All inspections synced' : 'Waiting to sync',
        SyncPhase.waitingForConnection =>
          '$pendingTasks pending - will sync when back online',
        SyncPhase.syncing => totalInRun == 0
            ? 'Syncing...'
            : 'Syncing $completedInRun of $totalInRun',
        SyncPhase.retryScheduled =>
          '$pendingTasks pending - retrying shortly',
        SyncPhase.failed => lastError ?? 'Sync failed',
      };

  SyncState copyWith({
    SyncPhase? phase,
    bool? isOnline,
    int? pendingTasks,
    int? completedInRun,
    int? totalInRun,
    String? lastError,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) =>
      SyncState(
        phase: phase ?? this.phase,
        isOnline: isOnline ?? this.isOnline,
        pendingTasks: pendingTasks ?? this.pendingTasks,
        completedInRun: completedInRun ?? this.completedInRun,
        totalInRun: totalInRun ?? this.totalInRun,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}
