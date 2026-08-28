import 'package:sqflite/sqflite.dart';

import '../../../sync/sync_task.dart';
import '../app_database.dart';

/// The durable outbox.
///
/// Queued work lives in SQLite rather than in memory, so pending uploads
/// survive the app being killed, the phone rebooting, or the evaluator
/// finishing a shift and opening the app again the next morning.
class SyncQueueDao {
  const SyncQueueDao(this._appDatabase);

  final AppDatabase _appDatabase;

  /// Adds work to the queue.
  ///
  /// `(entity_type, entity_id, operation)` is unique, so enqueuing the same
  /// work twice updates the existing row instead of creating a duplicate —
  /// tapping "retry" repeatedly cannot flood the queue.
  Future<void> enqueue({
    required SyncEntityType entityType,
    required String entityId,
    required SyncOperation operation,
    String? payload,
    DateTime? runAt,
  }) async {
    final db = await _appDatabase.database;
    final now = DateTime.now();
    await db.insert(
      Tables.syncQueue,
      {
        'entity_type': entityType.wireValue,
        'entity_id': entityId,
        'operation': operation.wireValue,
        'payload': payload,
        'attempts': 0,
        'next_attempt_at': (runAt ?? now).toIso8601String(),
        'last_error': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Tasks whose backoff window has elapsed, oldest first.
  ///
  /// Ordering by creation date means an inspection submitted this morning wins
  /// over one started this afternoon, which is what an evaluator expects.
  Future<List<SyncTask>> findDue({DateTime? now, int limit = 25}) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.syncQueue,
      where: 'next_attempt_at <= ?',
      whereArgs: [(now ?? DateTime.now()).toIso8601String()],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  Future<List<SyncTask>> findAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query(Tables.syncQueue, orderBy: 'created_at ASC');
    return rows.map(_fromRow).toList();
  }

  Future<int> countPending() async {
    final db = await _appDatabase.database;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS c FROM ${Tables.syncQueue}');
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Records a failed attempt and pushes the task into its next backoff window.
  Future<void> recordFailure(SyncTask task, String error) async {
    final db = await _appDatabase.database;
    final attempts = task.attempts + 1;
    final updated = task.copyWith(attempts: attempts);
    final now = DateTime.now();
    await db.update(
      Tables.syncQueue,
      {
        'attempts': attempts,
        'last_error': error,
        'next_attempt_at': now.add(updated.nextBackoff).toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// Clears the retry counter and schedules immediately — used when the
  /// evaluator manually retries a failed inspection.
  Future<void> reschedule(String entityId) async {
    final db = await _appDatabase.database;
    final now = DateTime.now();
    await db.update(
      Tables.syncQueue,
      {
        'attempts': 0,
        'last_error': null,
        'next_attempt_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: 'entity_id = ?',
      whereArgs: [entityId],
    );
  }

  Future<void> remove(int id) async {
    final db = await _appDatabase.database;
    await db.delete(Tables.syncQueue, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> removeForEntity(String entityId) async {
    final db = await _appDatabase.database;
    await db.delete(
      Tables.syncQueue,
      where: 'entity_id = ?',
      whereArgs: [entityId],
    );
  }

  SyncTask _fromRow(Map<String, Object?> row) => SyncTask(
        id: row['id'] as int?,
        entityType: SyncEntityType.fromWire(row['entity_type']! as String),
        entityId: row['entity_id']! as String,
        operation: SyncOperation.fromWire(row['operation']! as String),
        payload: row['payload'] as String?,
        attempts: row['attempts'] as int? ?? 0,
        nextAttemptAt: DateTime.parse(row['next_attempt_at']! as String),
        lastError: row['last_error'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
      );
}
