import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../core/error/failure_mapper.dart';
import '../../core/error/failures.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/evaluator.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/entities/inspection_item.dart';
import '../../domain/entities/inspection_photo.dart';
import '../../domain/entities/inspection_summary.dart';
import '../../domain/entities/inspection_template.dart';
import '../../domain/entities/item_status.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/inspection_repository.dart';
import '../../domain/repositories/template_repository.dart';
import '../../domain/services/grading_service.dart';
import '../../domain/services/photo_service.dart';
import '../../sync/sync_scheduler.dart';
import '../../sync/sync_task.dart';
import '../local/daos/inspection_dao.dart';
import '../local/daos/sync_queue_dao.dart';

/// Offline-first inspection storage.
///
/// Everything here completes against SQLite. Nothing awaits the network, and
/// no method fails because the device is offline — submission enqueues work and
/// returns, and the [SyncScheduler] drains the queue whenever it can. That is
/// the whole offline story: the UI never has a "wait for the server" state
/// because there is nothing to wait for.
class InspectionRepositoryImpl implements InspectionRepository {
  InspectionRepositoryImpl({
    required InspectionDao inspectionDao,
    required SyncQueueDao syncQueueDao,
    required TemplateRepository templateRepository,
    required PhotoService photoService,
    required SyncScheduler syncScheduler,
    GradingService gradingService = const GradingService(),
    Uuid uuid = const Uuid(),
  })  : _dao = inspectionDao,
        _queue = syncQueueDao,
        _templates = templateRepository,
        _photos = photoService,
        _scheduler = syncScheduler,
        _grading = gradingService,
        _uuid = uuid;

  final InspectionDao _dao;
  final SyncQueueDao _queue;
  final TemplateRepository _templates;
  final PhotoService _photos;
  final SyncScheduler _scheduler;
  final GradingService _grading;
  final Uuid _uuid;

  /// Emits the current list on subscribe, then again after every write.
  ///
  /// The change signal comes from the DAO rather than a controller owned here,
  /// so writes made by the sync engine — which also goes through the DAO —
  /// refresh the history list and dashboard counters too. Without that, a
  /// record would keep showing "Pending sync" after it had actually landed.
  ///
  /// `yield*` rather than `await for`: a generator parked on `await for` cannot
  /// observe a cancellation until the inner stream ticks again, so disposing a
  /// watcher on a quiet device would hang until something else happened to
  /// change. Delegating forwards the cancel immediately.
  @override
  Stream<List<InspectionSummary>> watchSummaries() async* {
    yield await _dao.findSummaries();
    yield* _dao.changes.asyncMap((_) => _dao.findSummaries());
  }

  @override
  Future<List<InspectionSummary>> fetchSummaries({
    InspectionHistoryFilter filter = InspectionHistoryFilter.all,
    String? query,
  }) =>
      _guard(() => _dao.findSummaries(filter: filter, query: query));

  @override
  Future<DashboardStats> fetchDashboardStats() => _guard(_dao.fetchStats);

  @override
  Future<Inspection?> findById(String inspectionId) =>
      _guard(() => _dao.findById(inspectionId));

  // ---------------------------------------------------------------------------
  // Creation and editing
  // ---------------------------------------------------------------------------

  @override
  Future<Inspection> createDraft({
    required Vehicle vehicle,
    required Evaluator evaluator,
    required InspectionTemplate template,
  }) async {
    return _guard(() async {
      final now = DateTime.now();
      final inspectionId = _uuid.v4();

      // One item per point, created up front. The checklist screen then only
      // ever updates rows, never has to decide whether one exists.
      final items = [
        for (final point in template.allPoints)
          InspectionItem(
            id: _uuid.v4(),
            inspectionId: inspectionId,
            pointId: point.id,
          ),
      ];

      final inspection = Inspection(
        id: inspectionId,
        referenceNumber: _referenceNumber(now),
        templateId: template.id,
        templateVersion: template.version,
        evaluatorId: evaluator.id,
        evaluatorName: evaluator.name,
        vehicle: _normalise(vehicle),
        items: items,
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.draftLocal,
      );

      await _dao.insert(inspection);
      AppLogger.info(
        'Created ${inspection.referenceNumber} with ${items.length} points',
        scope: 'inspection',
      );
      return inspection;
    });
  }

  @override
  Future<Inspection> updateVehicle({
    required String inspectionId,
    required Vehicle vehicle,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      _assertEditable(current);

      await _dao.updateVehicle(
        inspectionId: inspectionId,
        vehicle: _normalise(vehicle),
        updatedAt: DateTime.now(),
      );
      return _require(inspectionId);
    });
  }

  @override
  Future<Inspection> setItemStatus({
    required String inspectionId,
    required String pointId,
    required ItemStatus status,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      _assertEditable(current);

      final item = current.itemForPoint(pointId);
      if (item == null) {
        throw ValidationFailure(
          message: 'This checklist point is not part of the inspection.',
        );
      }

      await _dao.upsertItem(
        item.copyWith(status: status, updatedAt: DateTime.now()),
      );
      return _rescoreAndReload(inspectionId);
    });
  }

  @override
  Future<Inspection> setItemComment({
    required String inspectionId,
    required String pointId,
    required String? comment,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      _assertEditable(current);

      final item = current.itemForPoint(pointId);
      if (item == null) {
        throw ValidationFailure(
          message: 'This checklist point is not part of the inspection.',
        );
      }

      final trimmed = comment?.trim();
      await _dao.upsertItem(
        item.copyWith(
          comment: trimmed,
          clearComment: trimmed == null || trimmed.isEmpty,
          updatedAt: DateTime.now(),
        ),
      );
      return _require(inspectionId);
    });
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  @override
  Future<Inspection> attachPhoto({
    required String inspectionId,
    required String pointId,
    required PhotoSource source,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      _assertEditable(current);

      final item = current.itemForPoint(pointId);
      if (item == null) {
        throw ValidationFailure(
          message: 'This checklist point is not part of the inspection.',
        );
      }

      final template = await _templateFor(current);
      final point = template.pointById(pointId);
      final maxPhotos = point?.maxPhotos ?? 3;
      if (item.photos.length >= maxPhotos) {
        throw ValidationFailure(
          message: 'You can attach up to $maxPhotos photos to this point.',
        );
      }

      final captured = await _photos.capture(
        source: source,
        inspectionId: inspectionId,
      );
      // Cancelling the picker leaves the inspection untouched.
      if (captured == null) return current;

      await _dao.insertPhoto(
        InspectionPhoto(
          id: _uuid.v4(),
          inspectionId: inspectionId,
          itemId: item.id,
          localPath: captured.path,
          byteSize: captured.byteSize,
          width: captured.width,
          height: captured.height,
          createdAt: DateTime.now(),
          // Photos on a draft are not queued yet; submission is what promotes
          // them to pending.
          syncStatus: SyncStatus.draftLocal,
        ),
      );
      return _require(inspectionId);
    });
  }

  @override
  Future<Inspection> removePhoto({
    required String inspectionId,
    required String photoId,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      _assertEditable(current);

      final photo = await _dao.findPhoto(photoId);
      if (photo == null) return current;

      await _dao.deletePhoto(photoId);
      // Delete the row first: an orphaned file wastes space, but an orphaned
      // row would render as a broken thumbnail.
      await _photos.deleteFile(photo.localPath);
      return _require(inspectionId);
    });
  }

  @override
  Future<Inspection> replacePhoto({
    required String inspectionId,
    required String pointId,
    required String photoId,
    required PhotoSource source,
  }) async {
    return _guard(() async {
      // Capture first. If the evaluator cancels, the original must survive.
      final captured = await _photos.capture(
        source: source,
        inspectionId: inspectionId,
      );
      if (captured == null) return _require(inspectionId);

      final existing = await _dao.findPhoto(photoId);
      final item = (await _require(inspectionId)).itemForPoint(pointId);
      if (item == null) {
        await _photos.deleteFile(captured.path);
        throw ValidationFailure(
          message: 'This checklist point is not part of the inspection.',
        );
      }

      await _dao.insertPhoto(
        InspectionPhoto(
          id: _uuid.v4(),
          inspectionId: inspectionId,
          itemId: item.id,
          localPath: captured.path,
          byteSize: captured.byteSize,
          width: captured.width,
          height: captured.height,
          createdAt: DateTime.now(),
          syncStatus: SyncStatus.draftLocal,
        ),
      );

      if (existing != null) {
        await _dao.deletePhoto(photoId);
        await _photos.deleteFile(existing.localPath);
      }
      return _require(inspectionId);
    });
  }

  // ---------------------------------------------------------------------------
  // Submission
  // ---------------------------------------------------------------------------

  @override
  Future<Inspection> submit({
    required String inspectionId,
    required InspectionTemplate template,
  }) async {
    return _guard(() async {
      final current = await _require(inspectionId);
      if (current.isSubmitted) return current;

      final missing = current.unansweredRequiredPoints(template);
      if (missing.isNotEmpty) {
        throw ValidationFailure(
          message: missing.length == 1
              ? '1 required point is still unanswered.'
              : '${missing.length} required points are still unanswered.',
          fieldErrors: {
            for (final point in missing) point.id: 'Not checked',
          },
        );
      }

      final missingPhotos = current.pointsMissingRequiredPhotos(template);
      if (missingPhotos.isNotEmpty) {
        throw ValidationFailure(
          message: 'Failed points need a photo before you can submit.',
          fieldErrors: {
            for (final point in missingPhotos) point.id: 'Photo required',
          },
        );
      }

      final result = _grading.withRules(template.gradingRules).evaluateInspection(
            items: current.items,
            template: template,
          );
      final now = DateTime.now();

      await _dao.updateScore(
        inspectionId: inspectionId,
        scorePercentage: result.percentage,
        gradeCode: result.gradeCode,
        obtainedPoints: result.obtainedPoints,
        maxPoints: result.maxPoints,
        updatedAt: now,
      );
      await _dao.markSubmitted(
        inspectionId: inspectionId,
        submittedAt: now,
        syncStatus: SyncStatus.pending,
      );

      await _enqueueSync(current);

      AppLogger.info(
        'Submitted ${current.referenceNumber}: '
        '${result.displayPercentage} grade ${result.gradeCode}',
        scope: 'inspection',
      );

      // Fire-and-forget: submission must return instantly whether or not the
      // device has signal.
      _scheduler.requestSync(reason: 'inspection submitted');
      return _require(inspectionId);
    });
  }

  /// Queues the inspection and one task per photo.
  ///
  /// Photos get their own tasks so a 20-photo inspection makes progress one
  /// file at a time instead of restarting the whole upload on every failure.
  Future<void> _enqueueSync(Inspection inspection) async {
    await _queue.enqueue(
      entityType: SyncEntityType.inspection,
      entityId: inspection.id,
      operation: SyncOperation.submitInspection,
    );

    for (final photo in inspection.allPhotos) {
      await _dao.updatePhotoSync(
        photoId: photo.id,
        syncStatus: SyncStatus.pending,
      );
      await _queue.enqueue(
        entityType: SyncEntityType.photo,
        entityId: photo.id,
        operation: SyncOperation.uploadPhoto,
      );
    }
  }

  @override
  Future<void> delete(String inspectionId) async {
    return _guard(() async {
      await _dao.delete(inspectionId);
      await _photos.deleteInspectionFiles(inspectionId);
    });
  }

  @override
  Future<void> retrySync(String inspectionId) async {
    return _guard(() async {
      final inspection = await _require(inspectionId);

      await _dao.updateSyncState(
        inspectionId: inspectionId,
        syncStatus: SyncStatus.pending,
        attempts: 0,
        clearError: true,
      );

      // Anything already accepted by the server stays accepted; only the
      // outstanding work is re-armed.
      if (inspection.remoteId == null) {
        await _queue.enqueue(
          entityType: SyncEntityType.inspection,
          entityId: inspectionId,
          operation: SyncOperation.submitInspection,
        );
      }
      for (final photo in await _dao.findUnsyncedPhotos(inspectionId)) {
        await _queue.enqueue(
          entityType: SyncEntityType.photo,
          entityId: photo.id,
          operation: SyncOperation.uploadPhoto,
        );
      }
      await _queue.reschedule(inspectionId);

      _scheduler.requestSync(reason: 'manual retry');
    });
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Recomputes the cached grade after an answer changes.
  ///
  /// Doing this on every edit — not only at submission — is what lets the
  /// checklist screen show a live score without the UI knowing the rules.
  Future<Inspection> _rescoreAndReload(String inspectionId) async {
    final inspection = await _require(inspectionId);
    final template = await _templateFor(inspection);
    final result = _grading
        .withRules(template.gradingRules)
        .evaluateInspection(items: inspection.items, template: template);

    await _dao.updateScore(
      inspectionId: inspectionId,
      scorePercentage: result.hasScore ? result.percentage : null,
      gradeCode: result.hasScore ? result.gradeCode : null,
      obtainedPoints: result.obtainedPoints,
      maxPoints: result.maxPoints,
      updatedAt: DateTime.now(),
    );
    return _require(inspectionId);
  }

  Future<InspectionTemplate> _templateFor(Inspection inspection) async {
    // Grade against the exact revision the inspection was captured with, so a
    // newly published template cannot silently change an old score.
    final template = await _templates.getTemplate(
      inspection.templateId,
      version: inspection.templateVersion,
    );
    return template ?? await _templates.getActiveTemplate();
  }

  Future<Inspection> _require(String inspectionId) async {
    final inspection = await _dao.findById(inspectionId);
    if (inspection == null) {
      throw const StorageFailure(
        message: 'That inspection is no longer on this device.',
      );
    }
    return inspection;
  }

  void _assertEditable(Inspection inspection) {
    if (inspection.isSubmitted) {
      throw const ValidationFailure(
        message: 'This inspection has been submitted and can no longer '
            'be edited.',
      );
    }
  }

  /// Trims and upper-cases the fields that are compared or searched, so
  /// `abc-123` and `ABC-123` are one vehicle rather than two.
  Vehicle _normalise(Vehicle vehicle) => vehicle.copyWith(
        registrationNumber: vehicle.registrationNumber.trim().toUpperCase(),
        vin: vehicle.vin.trim().toUpperCase(),
        make: vehicle.make.trim(),
        model: vehicle.model.trim(),
      );

  /// Device-generated, human-quotable identifier.
  ///
  /// Uniqueness is enforced by a UNIQUE constraint; the random suffix makes a
  /// same-day collision across devices vanishingly unlikely without needing a
  /// server round trip the evaluator may not be able to make.
  String _referenceNumber(DateTime now) {
    final date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 4).toUpperCase();
    return 'INS-$date-$suffix';
  }

  /// Single translation point from infrastructure errors to [Failure]s.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      final failure = mapToFailure(error);
      AppLogger.error(
        failure.message,
        scope: 'inspection',
        error: error,
        stackTrace: stackTrace,
      );
      throw failure;
    }
  }
}
