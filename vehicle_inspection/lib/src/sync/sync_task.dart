import '../core/constants/app_constants.dart';

/// What kind of record a queued task refers to.
enum SyncEntityType {
  inspection('inspection'),
  photo('photo');

  const SyncEntityType(this.wireValue);

  final String wireValue;

  static SyncEntityType fromWire(String value) =>
      values.firstWhere((e) => e.wireValue == value, orElse: () => inspection);
}

/// The work to perform.
///
/// Splitting photo uploads from inspection submission is deliberate: a
/// 20-photo inspection on a weak connection makes progress one file at a time
/// instead of restarting from zero on every failure.
enum SyncOperation {
  submitInspection('submit_inspection'),
  uploadPhoto('upload_photo');

  const SyncOperation(this.wireValue);

  final String wireValue;

  static SyncOperation fromWire(String value) => values.firstWhere(
        (e) => e.wireValue == value,
        orElse: () => submitInspection,
      );
}

/// One unit of pending replication work.
class SyncTask {
  const SyncTask({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.nextAttemptAt,
    required this.createdAt,
    required this.updatedAt,
    this.id,
    this.payload,
    this.attempts = 0,
    this.lastError,
  });

  /// Autoincrement rowid; null before the task is persisted.
  final int? id;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperation operation;

  /// Optional JSON captured at enqueue time. Unused today — the engine reads
  /// current state from the database so a retry always sends the latest edit —
  /// but kept for operations that must send a point-in-time snapshot.
  final String? payload;

  final int attempts;

  /// Earliest moment this task may run again; how backoff is expressed.
  final DateTime nextAttemptAt;

  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasAttemptsLeft => attempts < AppConstants.syncMaxAttempts;

  /// Exponential backoff with a ceiling: 4s, 8s, 16s, 32s, ... capped at 30
  /// minutes, so a server outage does not turn into a battery drain.
  Duration get nextBackoff {
    final multiplier = 1 << attempts.clamp(0, 20);
    final delay = AppConstants.syncBaseBackoff * multiplier;
    return delay > AppConstants.syncMaxBackoff
        ? AppConstants.syncMaxBackoff
        : delay;
  }

  SyncTask copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
    bool clearError = false,
    DateTime? updatedAt,
  }) =>
      SyncTask(
        id: id,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
