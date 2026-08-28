import 'dart:async';

import '../core/constants/app_constants.dart';
import '../core/error/failure_mapper.dart';
import '../core/error/failures.dart';
import '../core/utils/app_logger.dart';
import '../data/local/daos/inspection_dao.dart';
import '../data/local/daos/sync_queue_dao.dart';
import '../data/remote/inspection_api.dart';
import '../domain/entities/sync_status.dart';
import '../domain/services/connectivity_monitor.dart';
import 'sync_scheduler.dart';
import 'sync_state.dart';
import 'sync_task.dart';

/// Drains the outbox whenever the device can reach the backend.
///
/// Design notes:
/// * **The queue is in SQLite, not memory.** Pending uploads survive the app
///   being killed or the phone rebooting mid-shift.
/// * **One task per photo.** A weak connection makes progress file by file
///   instead of restarting a 20-photo inspection on every failure.
/// * **Backoff is per task**, exponential and capped, so a server outage costs
///   battery once rather than continuously.
/// * **Retryable is a property of the failure**, not of the call site. A 500
///   retries; a 422 does not, because resending the same payload cannot help.
/// * **Runs are serialised.** A connectivity flap while a run is in flight sets
///   a rerun flag rather than starting a second, overlapping drain.
class SyncEngine implements SyncScheduler {
  SyncEngine({
    required SyncQueueDao queueDao,
    required InspectionDao inspectionDao,
    required InspectionApi api,
    required ConnectivityMonitor connectivity,
    Duration debounce = AppConstants.syncDebounce,
  })  : _queue = queueDao,
        _dao = inspectionDao,
        _api = api,
        _connectivity = connectivity,
        _debounce = debounce;

  final SyncQueueDao _queue;
  final InspectionDao _dao;
  final InspectionApi _api;
  final ConnectivityMonitor _connectivity;
  final Duration _debounce;

  final StreamController<SyncState> _states =
      StreamController<SyncState>.broadcast();

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _debounceTimer;

  SyncState _state = const SyncState();
  bool _running = false;
  bool _rerunRequested = false;
  bool _disposed = false;

  SyncState get state => _state;

  /// Current state first, then every update — a late subscriber is never blank.
  Stream<SyncState> get states async* {
    yield _state;
    yield* _states.stream;
  }

  /// Starts watching connectivity and drains anything left over from the last
  /// session.
  Future<void> start() async {
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    final online = await _connectivity.isOnline();
    _setState(_state.copyWith(isOnline: online));
    await _refreshPendingCount();
    requestSync(reason: 'startup');
  }

  @override
  void requestSync({String reason = 'unspecified'}) {
    if (_disposed) return;
    AppLogger.debug('Sync requested ($reason)', scope: 'sync');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => unawaited(_drain()));
  }

  /// Awaitable form of [requestSync].
  ///
  /// [requestSync] is deliberately fire-and-forget so callers on the UI thread
  /// never block; this is for the few places that need to know the run is over.
  Future<void> syncNow() => _drain();

  void _onConnectivityChanged(bool online) {
    _setState(_state.copyWith(isOnline: online));
    if (online) {
      requestSync(reason: 'connectivity restored');
    } else if (_state.hasPendingWork) {
      _setState(_state.copyWith(phase: SyncPhase.waitingForConnection));
    }
  }

  // ---------------------------------------------------------------------------
  // The drain loop
  // ---------------------------------------------------------------------------

  Future<void> _drain() async {
    if (_disposed) return;
    if (_running) {
      // Coalesce instead of overlapping: a second pass runs once this finishes.
      _rerunRequested = true;
      return;
    }

    _running = true;
    try {
      do {
        _rerunRequested = false;
        await _runOnce();
      } while (_rerunRequested && !_disposed);
    } finally {
      _running = false;
    }
  }

  Future<void> _runOnce() async {
    if (!await _connectivity.isOnline()) {
      await _refreshPendingCount();
      _setState(
        _state.copyWith(
          isOnline: false,
          phase: _state.hasPendingWork
              ? SyncPhase.waitingForConnection
              : SyncPhase.idle,
          completedInRun: 0,
          totalInRun: 0,
        ),
      );
      return;
    }

    final due = await _queue.findDue();
    if (due.isEmpty) {
      await _refreshPendingCount();
      _setState(
        _state.copyWith(
          isOnline: true,
          phase: _state.hasPendingWork
              ? SyncPhase.retryScheduled
              : SyncPhase.idle,
          completedInRun: 0,
          totalInRun: 0,
        ),
      );
      return;
    }

    AppLogger.info('Draining ${due.length} sync task(s)', scope: 'sync');
    _setState(
      _state.copyWith(
        phase: SyncPhase.syncing,
        isOnline: true,
        totalInRun: due.length,
        completedInRun: 0,
        clearError: true,
      ),
    );

    var completed = 0;
    var sawFailure = false;
    var sawDeferral = false;

    for (final task in due) {
      if (_disposed) return;

      // Re-check between tasks: signal can drop halfway through a batch, and
      // there is no point burning the retry budget on tasks that cannot run.
      if (!await _connectivity.isOnline()) {
        _setState(
          _state.copyWith(
            isOnline: false,
            phase: SyncPhase.waitingForConnection,
          ),
        );
        break;
      }

      switch (await _process(task)) {
        case _TaskOutcome.completed:
          completed++;
        case _TaskOutcome.deferred:
          sawDeferral = true;
        case _TaskOutcome.failed:
          sawFailure = true;
      }
      _setState(_state.copyWith(completedInRun: completed));
    }

    // A task that was only waiting on one of its siblings deserves another
    // pass now rather than sitting until the next connectivity change. Gated on
    // progress having been made, so this always converges.
    if (sawDeferral && completed > 0) _rerunRequested = true;

    await _refreshPendingCount();
    _setState(
      _state.copyWith(
        phase: _resolvePhase(sawFailure),
        lastSyncedAt: completed > 0 ? DateTime.now() : _state.lastSyncedAt,
        completedInRun: completed,
      ),
    );
  }

  SyncPhase _resolvePhase(bool sawFailure) {
    if (!_state.isOnline) return SyncPhase.waitingForConnection;
    // An empty queue after failures means tasks were dropped for exhausting
    // their retry budget — that needs the evaluator, not another wait.
    if (!_state.hasPendingWork) {
      return sawFailure ? SyncPhase.failed : SyncPhase.idle;
    }
    return SyncPhase.retryScheduled;
  }

  /// Runs one task.
  Future<_TaskOutcome> _process(SyncTask task) async {
    try {
      switch (task.operation) {
        case SyncOperation.submitInspection:
          await _submitInspection(task);
        case SyncOperation.uploadPhoto:
          final handled = await _uploadPhoto(task);
          // A photo whose inspection has not been accepted yet is deferred,
          // not failed: it stays queued without consuming a retry.
          if (!handled) return _TaskOutcome.deferred;
      }
      if (task.id != null) await _queue.remove(task.id!);
      return _TaskOutcome.completed;
    } catch (error) {
      await _handleTaskFailure(task, mapToFailure(error));
      return _TaskOutcome.failed;
    }
  }

  Future<void> _submitInspection(SyncTask task) async {
    final inspection = await _dao.findById(task.entityId);
    if (inspection == null) {
      // The evaluator deleted it while it was queued. Nothing to do.
      AppLogger.warn('Queued inspection ${task.entityId} is gone',
          scope: 'sync');
      return;
    }

    // Already accepted by a previous run whose response we lost.
    if (inspection.remoteId != null) {
      await _maybeMarkInspectionSynced(inspection.id);
      return;
    }

    await _dao.updateSyncState(
      inspectionId: inspection.id,
      syncStatus: SyncStatus.syncing,
    );

    final remoteId = await _api.submit(inspection);

    await _dao.updateSyncState(
      inspectionId: inspection.id,
      syncStatus: SyncStatus.pending,
      remoteId: remoteId,
      clearError: true,
    );
    await _maybeMarkInspectionSynced(inspection.id);
    AppLogger.info(
      'Inspection ${inspection.referenceNumber} accepted as $remoteId',
      scope: 'sync',
    );
  }

  /// Returns `false` when the task should stay queued without being counted as
  /// a failure.
  Future<bool> _uploadPhoto(SyncTask task) async {
    final photo = await _dao.findPhoto(task.entityId);
    if (photo == null) {
      // Deleted before it ever uploaded; drop the task.
      return true;
    }

    final inspection = await _dao.findById(photo.inspectionId);
    if (inspection == null) return true;

    final remoteId = inspection.remoteId;
    if (remoteId == null) {
      // The parent has not been accepted yet. The inspection task is ahead of
      // this one in the queue, so simply wait for the next pass.
      AppLogger.debug(
        'Deferring photo ${photo.id}: inspection not yet accepted',
        scope: 'sync',
      );
      return false;
    }

    await _dao.updatePhotoSync(
      photoId: photo.id,
      syncStatus: SyncStatus.syncing,
    );

    final url = await _api.uploadPhoto(photo, inspectionRemoteId: remoteId);

    await _dao.updatePhotoSync(
      photoId: photo.id,
      syncStatus: SyncStatus.synced,
      remoteUrl: url,
      clearError: true,
    );
    await _maybeMarkInspectionSynced(photo.inspectionId);
    return true;
  }

  /// An inspection is fully synced only once its record and every photo have
  /// landed. Until then it stays pending, which is what the evaluator sees.
  Future<void> _maybeMarkInspectionSynced(String inspectionId) async {
    final inspection = await _dao.findById(inspectionId);
    if (inspection == null || inspection.remoteId == null) return;

    final outstanding = await _dao.findUnsyncedPhotos(inspectionId);
    if (outstanding.isNotEmpty) return;

    await _dao.updateSyncState(
      inspectionId: inspectionId,
      syncStatus: SyncStatus.synced,
      clearError: true,
    );
  }

  Future<void> _handleTaskFailure(SyncTask task, Failure failure) async {
    final attempts = task.attempts + 1;
    final exhausted =
        !failure.isRetryable || attempts >= AppConstants.syncMaxAttempts;

    AppLogger.warn(
      'Task ${task.operation.wireValue}/${task.entityId} failed '
      '(attempt $attempts): ${failure.message}',
      scope: 'sync',
    );

    if (exhausted) {
      // Stop retrying and surface it. The work stays in the database; the
      // evaluator can retry manually from the history screen.
      if (task.id != null) await _queue.remove(task.id!);
      await _markEntityFailed(task, failure.message);
    } else {
      await _queue.recordFailure(task, failure.message);
      if (task.entityType == SyncEntityType.inspection) {
        await _dao.updateSyncState(
          inspectionId: task.entityId,
          syncStatus: SyncStatus.pending,
          attempts: attempts,
          error: failure.message,
        );
      }
    }

    _setState(_state.copyWith(lastError: failure.message));
  }

  Future<void> _markEntityFailed(SyncTask task, String error) async {
    switch (task.entityType) {
      case SyncEntityType.inspection:
        await _dao.updateSyncState(
          inspectionId: task.entityId,
          syncStatus: SyncStatus.failed,
          attempts: AppConstants.syncMaxAttempts,
          error: error,
        );
      case SyncEntityType.photo:
        await _dao.updatePhotoSync(
          photoId: task.entityId,
          syncStatus: SyncStatus.failed,
          error: error,
        );
        final photo = await _dao.findPhoto(task.entityId);
        if (photo != null) {
          await _dao.updateSyncState(
            inspectionId: photo.inspectionId,
            syncStatus: SyncStatus.failed,
            error: error,
          );
        }
    }
  }

  Future<void> _refreshPendingCount() async {
    final pending = await _queue.countPending();
    _setState(_state.copyWith(pendingTasks: pending));
  }

  void _setState(SyncState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _states.close();
  }
}

/// Result of attempting one queued task.
enum _TaskOutcome {
  /// Done and removed from the queue.
  completed,

  /// Still queued, waiting on a sibling task, and no retry was consumed.
  deferred,

  /// Errored; either backed off or marked failed.
  failed,
}
