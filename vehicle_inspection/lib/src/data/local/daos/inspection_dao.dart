import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../domain/entities/inspection.dart';
import '../../../domain/entities/inspection_item.dart';
import '../../../domain/entities/inspection_photo.dart';
import '../../../domain/entities/inspection_summary.dart';
import '../../../domain/entities/item_status.dart';
import '../../../domain/entities/sync_status.dart';
import '../../../domain/entities/vehicle.dart';
import '../app_database.dart';

/// All inspection reads and writes.
///
/// The DAO deals only in rows and entities; it holds no business rules. Grading
/// and sync decisions live in the repository and the sync engine, which keeps
/// this class easy to reason about and to test against an in-memory database.
class InspectionDao {
  InspectionDao(this._appDatabase);

  final AppDatabase _appDatabase;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits after every write, so watchers can re-query.
  ///
  /// Living on the DAO rather than the repository is deliberate: the sync
  /// engine also writes here, so a completed upload refreshes the history list
  /// and the dashboard counters without any extra plumbing. If this lived one
  /// layer up, records would silently stay "Pending sync" on screen after they
  /// had actually landed.
  Stream<void> get changes => _changes.stream;

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  /// Persists a new inspection together with one row per checklist point.
  ///
  /// Wrapped in a transaction so a crash mid-write can never leave a header
  /// without its items.
  Future<void> insert(Inspection inspection) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert(
        Tables.inspections,
        _toRow(inspection),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final batch = txn.batch();
      for (final item in inspection.items) {
        batch.insert(Tables.inspectionItems, _itemToRow(item));
      }
      await batch.commit(noResult: true);
      await _refreshCounters(txn, inspection.id);
    });
    _notify();
  }

  Future<void> updateVehicle({
    required String inspectionId,
    required Vehicle vehicle,
    required DateTime updatedAt,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      Tables.inspections,
      {
        'registration_number': vehicle.registrationNumber,
        'make': vehicle.make,
        'model': vehicle.model,
        'manufacturing_year': vehicle.manufacturingYear,
        'vin': vehicle.vin,
        'mileage_km': vehicle.mileageKm,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [inspectionId],
    );
    _notify();
  }

  /// Writes an answer and refreshes the cached progress counters.
  Future<void> upsertItem(InspectionItem item) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.insert(
        Tables.inspectionItems,
        _itemToRow(item),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _refreshCounters(txn, item.inspectionId);
    });
    _notify();
  }

  /// Stores the grade snapshot so list screens never recompute it.
  Future<void> updateScore({
    required String inspectionId,
    required double? scorePercentage,
    required String? gradeCode,
    required int? obtainedPoints,
    required int? maxPoints,
    required DateTime updatedAt,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      Tables.inspections,
      {
        'score_percentage': scorePercentage,
        'grade_code': gradeCode,
        'obtained_points': obtainedPoints,
        'max_points': maxPoints,
        'updated_at': updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [inspectionId],
    );
    _notify();
  }

  Future<void> markSubmitted({
    required String inspectionId,
    required DateTime submittedAt,
    required SyncStatus syncStatus,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      Tables.inspections,
      {
        'status': InspectionStatus.submitted.wireValue,
        'submitted_at': submittedAt.toIso8601String(),
        'updated_at': submittedAt.toIso8601String(),
        'sync_status': syncStatus.wireValue,
      },
      where: 'id = ?',
      whereArgs: [inspectionId],
    );
    _notify();
  }

  /// Records progress through the sync pipeline.
  ///
  /// [attempts] is passed explicitly rather than incremented here so the sync
  /// engine stays the single owner of retry policy.
  Future<void> updateSyncState({
    required String inspectionId,
    required SyncStatus syncStatus,
    String? remoteId,
    int? attempts,
    String? error,
    bool clearError = false,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      Tables.inspections,
      {
        'sync_status': syncStatus.wireValue,
        'remote_id': ?remoteId,
        'sync_attempts': ?attempts,
        if (clearError) 'last_sync_error': null else 'last_sync_error': ?error,
      },
      where: 'id = ?',
      whereArgs: [inspectionId],
    );
    _notify();
  }

  Future<void> insertPhoto(InspectionPhoto photo) async {
    final db = await _appDatabase.database;
    await db.insert(
      Tables.inspectionPhotos,
      _photoToRow(photo),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  Future<void> updatePhotoSync({
    required String photoId,
    required SyncStatus syncStatus,
    String? remoteUrl,
    String? error,
    bool clearError = false,
  }) async {
    final db = await _appDatabase.database;
    await db.update(
      Tables.inspectionPhotos,
      {
        'sync_status': syncStatus.wireValue,
        'remote_url': ?remoteUrl,
        if (clearError) 'last_error': null else 'last_error': ?error,
      },
      where: 'id = ?',
      whereArgs: [photoId],
    );
    _notify();
  }

  Future<InspectionPhoto?> findPhoto(String photoId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.inspectionPhotos,
      where: 'id = ?',
      whereArgs: [photoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _photoFromRow(rows.first);
  }

  Future<void> deletePhoto(String photoId) async {
    final db = await _appDatabase.database;
    await db.delete(
      Tables.inspectionPhotos,
      where: 'id = ?',
      whereArgs: [photoId],
    );
    _notify();
  }

  /// Cascades to items, photos and queued work via the schema's foreign keys.
  Future<void> delete(String inspectionId) async {
    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      await txn.delete(
        Tables.syncQueue,
        where: 'entity_id = ?',
        whereArgs: [inspectionId],
      );
      await txn.delete(
        Tables.inspections,
        where: 'id = ?',
        whereArgs: [inspectionId],
      );
    });
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Full aggregate: header, every answer, every photo.
  ///
  /// Three flat queries rather than a join, so items without photos are not
  /// duplicated and photo blobs never multiply the row count.
  Future<Inspection?> findById(String inspectionId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.inspections,
      where: 'id = ?',
      whereArgs: [inspectionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final itemRows = await db.query(
      Tables.inspectionItems,
      where: 'inspection_id = ?',
      whereArgs: [inspectionId],
    );
    final photoRows = await db.query(
      Tables.inspectionPhotos,
      where: 'inspection_id = ?',
      whereArgs: [inspectionId],
      orderBy: 'created_at ASC',
    );

    final photosByItem = <String, List<InspectionPhoto>>{};
    for (final photoRow in photoRows) {
      final photo = _photoFromRow(photoRow);
      photosByItem.putIfAbsent(photo.itemId, () => []).add(photo);
    }

    final items = itemRows.map((itemRow) {
      final id = itemRow['id']! as String;
      return InspectionItem(
        id: id,
        inspectionId: itemRow['inspection_id']! as String,
        pointId: itemRow['point_id']! as String,
        status: ItemStatus.fromWire(itemRow['status'] as String?),
        comment: itemRow['comment'] as String?,
        photos: photosByItem[id] ?? const [],
        updatedAt: itemRow['updated_at'] == null
            ? null
            : DateTime.tryParse(itemRow['updated_at']! as String),
      );
    }).toList();

    return _fromRow(rows.first, items);
  }

  /// Row-shaped list projection with the photo count folded in by SQL.
  Future<List<InspectionSummary>> findSummaries({
    InspectionHistoryFilter filter = InspectionHistoryFilter.all,
    String? query,
    int limit = 200,
  }) async {
    final db = await _appDatabase.database;

    final conditions = <String>[];
    final args = <Object?>[];

    switch (filter) {
      case InspectionHistoryFilter.all:
        break;
      case InspectionHistoryFilter.drafts:
        conditions.add('i.status = ?');
        args.add(InspectionStatus.draft.wireValue);
      case InspectionHistoryFilter.submitted:
        conditions.add('i.status = ?');
        args.add(InspectionStatus.submitted.wireValue);
      case InspectionHistoryFilter.pendingSync:
        conditions.add('i.status = ? AND i.sync_status != ?');
        args.addAll([
          InspectionStatus.submitted.wireValue,
          SyncStatus.synced.wireValue,
        ]);
    }

    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      conditions.add(
        '(i.registration_number LIKE ? OR i.make LIKE ? OR i.model LIKE ? '
        'OR i.reference_number LIKE ? OR i.vin LIKE ?)',
      );
      final like = '%${trimmedQuery.toUpperCase()}%';
      args.addAll(List.filled(5, like));
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery(
      '''
      SELECT i.*,
             (SELECT COUNT(*) FROM ${Tables.inspectionPhotos} p
               WHERE p.inspection_id = i.id) AS photo_count
        FROM ${Tables.inspections} i
        $where
       ORDER BY COALESCE(i.submitted_at, i.created_at) DESC
       LIMIT ?
      ''',
      [...args, limit],
    );

    return rows.map(_summaryFromRow).toList();
  }

  /// Dashboard counters in one pass rather than four queries.
  Future<DashboardStats> fetchStats() async {
    final db = await _appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END)  AS completed_count,
        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END)  AS draft_count,
        SUM(CASE WHEN status = ? AND sync_status IN (?, ?) THEN 1 ELSE 0 END)
                                                     AS pending_count,
        SUM(CASE WHEN sync_status = ? THEN 1 ELSE 0 END) AS failed_count
      FROM ${Tables.inspections}
      ''',
      [
        InspectionStatus.submitted.wireValue,
        InspectionStatus.draft.wireValue,
        InspectionStatus.submitted.wireValue,
        SyncStatus.pending.wireValue,
        SyncStatus.syncing.wireValue,
        SyncStatus.failed.wireValue,
      ],
    );

    if (rows.isEmpty) return DashboardStats.empty;
    final row = rows.first;
    int read(String key) => (row[key] as int?) ?? 0;

    return DashboardStats(
      completedCount: read('completed_count'),
      draftCount: read('draft_count'),
      // A failed inspection is still waiting to reach the server, so the
      // dashboard's "pending" tile must include it.
      pendingSyncCount: read('pending_count') + read('failed_count'),
      failedSyncCount: read('failed_count'),
    );
  }

  /// Photos belonging to an inspection that still need uploading.
  Future<List<InspectionPhoto>> findUnsyncedPhotos(String inspectionId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.inspectionPhotos,
      where: 'inspection_id = ? AND sync_status != ?',
      whereArgs: [inspectionId, SyncStatus.synced.wireValue],
      orderBy: 'created_at ASC',
    );
    return rows.map(_photoFromRow).toList();
  }

  /// Every local photo path for an inspection, so files can be cleaned up when
  /// a draft is discarded.
  Future<List<String>> findPhotoPaths(String inspectionId) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      Tables.inspectionPhotos,
      columns: ['local_path'],
      where: 'inspection_id = ?',
      whereArgs: [inspectionId],
    );
    return rows.map((row) => row['local_path']! as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------------

  /// Recomputes the denormalised progress counters from the item rows.
  ///
  /// Cheaper than reading every item into Dart on each keystroke, and it keeps
  /// the list projection correct without a join.
  Future<void> _refreshCounters(
    DatabaseExecutor txn,
    String inspectionId,
  ) async {
    await txn.rawUpdate(
      '''
      UPDATE ${Tables.inspections}
         SET total_items = (
               SELECT COUNT(*) FROM ${Tables.inspectionItems}
                WHERE inspection_id = ?),
             completed_items = (
               SELECT COUNT(*) FROM ${Tables.inspectionItems}
                WHERE inspection_id = ? AND status != ?)
       WHERE id = ?
      ''',
      [
        inspectionId,
        inspectionId,
        ItemStatus.pending.wireValue,
        inspectionId,
      ],
    );
  }

  Map<String, Object?> _toRow(Inspection inspection) => {
        'id': inspection.id,
        'remote_id': inspection.remoteId,
        'reference_number': inspection.referenceNumber,
        'template_id': inspection.templateId,
        'template_version': inspection.templateVersion,
        'evaluator_id': inspection.evaluatorId,
        'evaluator_name': inspection.evaluatorName,
        'registration_number': inspection.vehicle.registrationNumber,
        'make': inspection.vehicle.make,
        'model': inspection.vehicle.model,
        'manufacturing_year': inspection.vehicle.manufacturingYear,
        'vin': inspection.vehicle.vin,
        'mileage_km': inspection.vehicle.mileageKm,
        'status': inspection.status.wireValue,
        'score_percentage': inspection.scorePercentage,
        'grade_code': inspection.gradeCode,
        'obtained_points': inspection.obtainedPoints,
        'max_points': inspection.maxPoints,
        'completed_items': inspection.completedItems,
        'total_items': inspection.totalItems,
        'created_at': inspection.createdAt.toIso8601String(),
        'updated_at': inspection.updatedAt.toIso8601String(),
        'submitted_at': inspection.submittedAt?.toIso8601String(),
        'sync_status': inspection.syncStatus.wireValue,
        'sync_attempts': inspection.syncAttempts,
        'last_sync_error': inspection.lastSyncError,
      };

  Inspection _fromRow(Map<String, Object?> row, List<InspectionItem> items) {
    return Inspection(
      id: row['id']! as String,
      remoteId: row['remote_id'] as String?,
      referenceNumber: row['reference_number']! as String,
      templateId: row['template_id']! as String,
      templateVersion: row['template_version']! as int,
      evaluatorId: row['evaluator_id']! as String,
      evaluatorName: row['evaluator_name']! as String,
      vehicle: Vehicle(
        registrationNumber: row['registration_number']! as String,
        make: row['make']! as String,
        model: row['model']! as String,
        manufacturingYear: row['manufacturing_year']! as int,
        vin: row['vin']! as String,
        mileageKm: row['mileage_km']! as int,
      ),
      status: InspectionStatus.fromWire(row['status'] as String?),
      items: items,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      submittedAt: row['submitted_at'] == null
          ? null
          : DateTime.tryParse(row['submitted_at']! as String),
      syncStatus: SyncStatus.fromWire(row['sync_status'] as String?),
      syncAttempts: row['sync_attempts'] as int? ?? 0,
      lastSyncError: row['last_sync_error'] as String?,
      scorePercentage: (row['score_percentage'] as num?)?.toDouble(),
      gradeCode: row['grade_code'] as String?,
      obtainedPoints: row['obtained_points'] as int?,
      maxPoints: row['max_points'] as int?,
    );
  }

  InspectionSummary _summaryFromRow(Map<String, Object?> row) {
    final make = row['make']! as String;
    final model = row['model']! as String;
    return InspectionSummary(
      id: row['id']! as String,
      remoteId: row['remote_id'] as String?,
      referenceNumber: row['reference_number']! as String,
      registrationNumber: row['registration_number']! as String,
      vehicleName: '$make $model',
      createdAt: DateTime.parse(row['created_at']! as String),
      submittedAt: row['submitted_at'] == null
          ? null
          : DateTime.tryParse(row['submitted_at']! as String),
      status: InspectionStatus.fromWire(row['status'] as String?),
      syncStatus: SyncStatus.fromWire(row['sync_status'] as String?),
      completedItems: row['completed_items'] as int? ?? 0,
      totalItems: row['total_items'] as int? ?? 0,
      scorePercentage: (row['score_percentage'] as num?)?.toDouble(),
      gradeCode: row['grade_code'] as String?,
      photoCount: row['photo_count'] as int? ?? 0,
      lastSyncError: row['last_sync_error'] as String?,
    );
  }

  Map<String, Object?> _itemToRow(InspectionItem item) => {
        'id': item.id,
        'inspection_id': item.inspectionId,
        'point_id': item.pointId,
        'status': item.status.wireValue,
        'comment': item.comment,
        'updated_at': item.updatedAt?.toIso8601String(),
      };

  Map<String, Object?> _photoToRow(InspectionPhoto photo) => {
        'id': photo.id,
        'inspection_id': photo.inspectionId,
        'item_id': photo.itemId,
        'local_path': photo.localPath,
        'remote_url': photo.remoteUrl,
        'byte_size': photo.byteSize,
        'width': photo.width,
        'height': photo.height,
        'created_at': photo.createdAt.toIso8601String(),
        'sync_status': photo.syncStatus.wireValue,
        'last_error': photo.lastError,
      };

  InspectionPhoto _photoFromRow(Map<String, Object?> row) => InspectionPhoto(
        id: row['id']! as String,
        inspectionId: row['inspection_id']! as String,
        itemId: row['item_id']! as String,
        localPath: row['local_path']! as String,
        remoteUrl: row['remote_url'] as String?,
        byteSize: row['byte_size'] as int? ?? 0,
        width: row['width'] as int?,
        height: row['height'] as int?,
        createdAt: DateTime.parse(row['created_at']! as String),
        syncStatus: SyncStatus.fromWire(row['sync_status'] as String?),
        lastError: row['last_error'] as String?,
      );
}
