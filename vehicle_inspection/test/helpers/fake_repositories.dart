import 'dart:async';

import 'package:vehicle_inspection/src/core/error/failures.dart';
import 'package:vehicle_inspection/src/domain/entities/auth_session.dart';
import 'package:vehicle_inspection/src/domain/entities/evaluator.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_item.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_photo.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_summary.dart';
import 'package:vehicle_inspection/src/domain/entities/inspection_template.dart';
import 'package:vehicle_inspection/src/domain/entities/item_status.dart';
import 'package:vehicle_inspection/src/domain/entities/sync_status.dart';
import 'package:vehicle_inspection/src/domain/entities/vehicle.dart';
import 'package:vehicle_inspection/src/domain/repositories/auth_repository.dart';
import 'package:vehicle_inspection/src/domain/repositories/inspection_repository.dart';
import 'package:vehicle_inspection/src/domain/services/grading_service.dart';
import 'package:vehicle_inspection/src/domain/services/photo_service.dart';

/// In-memory repositories for widget tests.
///
/// The SQLite-backed implementations are covered thoroughly by the repository
/// and sync tests, which run against a real in-memory database. They cannot be
/// reused here: `sqflite_common_ffi` does its work off the Dart event loop, and
/// `testWidgets` runs under a fake clock, so a query started inside a widget
/// test never completes. These fakes keep the widget tests focused on what they
/// are actually for — that every screen builds, navigates and validates.

/// Accepts the documented test credentials and nothing else.
class FakeAuthRepository implements AuthRepository {
  AuthSession? _session;

  static const Evaluator evaluator = Evaluator(
    id: 'ev-1001',
    name: 'Ahmed Tariq',
    email: 'evaluator@test.com',
    branch: 'Lahore Central',
  );

  @override
  Future<AuthSession?> restoreSession() async => _session;

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().toLowerCase() != 'evaluator@test.com' ||
        password != 'password123') {
      throw const AuthFailure();
    }
    return _session = AuthSession(
      evaluator: evaluator,
      accessToken: 'fake-token',
      issuedAt: DateTime(2026, 8, 25),
    );
  }

  @override
  Future<void> signOut() async => _session = null;
}

/// Mirrors the real repository's offline-first behaviour without a database.
class FakeInspectionRepository implements InspectionRepository {
  FakeInspectionRepository(this.template);

  final InspectionTemplate template;
  final Map<String, Inspection> store = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  static const GradingService _grading = GradingService();
  int _sequence = 0;

  Future<void> dispose() => _changes.close();

  InspectionSummary _summarise(Inspection inspection) => InspectionSummary(
        id: inspection.id,
        remoteId: inspection.remoteId,
        referenceNumber: inspection.referenceNumber,
        registrationNumber: inspection.vehicle.registrationNumber,
        vehicleName: inspection.vehicle.displayName,
        createdAt: inspection.createdAt,
        submittedAt: inspection.submittedAt,
        status: inspection.status,
        syncStatus: inspection.syncStatus,
        completedItems: inspection.completedItems,
        totalItems: inspection.totalItems,
        scorePercentage: inspection.scorePercentage,
        gradeCode: inspection.gradeCode,
        photoCount: inspection.photoCount,
      );

  List<InspectionSummary> _snapshot() =>
      store.values.map(_summarise).toList()
        ..sort((a, b) => b.displayDate.compareTo(a.displayDate));

  void _put(Inspection inspection) {
    store[inspection.id] = inspection;
    if (!_changes.isClosed) _changes.add(null);
  }

  Inspection _require(String id) {
    final inspection = store[id];
    if (inspection == null) {
      throw const StorageFailure(message: 'Not found');
    }
    return inspection;
  }

  /// Re-grades and stores, mirroring the real repository's write path.
  Inspection _rescore(Inspection inspection) {
    final result = _grading
        .withRules(template.gradingRules)
        .evaluateInspection(items: inspection.items, template: template);
    final updated = inspection.copyWith(
      updatedAt: DateTime(2026, 8, 25),
      scorePercentage: result.hasScore ? result.percentage : null,
      gradeCode: result.hasScore ? result.gradeCode : null,
      obtainedPoints: result.obtainedPoints,
      maxPoints: result.maxPoints,
    );
    _put(updated);
    return updated;
  }

  Inspection _replaceItem(Inspection inspection, InspectionItem item) =>
      inspection.copyWith(
        items: [
          for (final existing in inspection.items)
            if (existing.id == item.id) item else existing,
        ],
      );

  @override
  Stream<List<InspectionSummary>> watchSummaries() async* {
    yield _snapshot();
    yield* _changes.stream.map((_) => _snapshot());
  }

  @override
  Future<List<InspectionSummary>> fetchSummaries({
    InspectionHistoryFilter filter = InspectionHistoryFilter.all,
    String? query,
  }) async {
    final text = query?.trim().toUpperCase() ?? '';
    return _snapshot()
        .where(filter.matches)
        .where(
          (s) =>
              text.isEmpty ||
              s.registrationNumber.toUpperCase().contains(text) ||
              s.vehicleName.toUpperCase().contains(text) ||
              s.referenceNumber.toUpperCase().contains(text),
        )
        .toList();
  }

  @override
  Future<DashboardStats> fetchDashboardStats() async {
    final all = store.values;
    return DashboardStats(
      completedCount: all.where((i) => i.isSubmitted).length,
      draftCount: all.where((i) => i.isDraft).length,
      pendingSyncCount:
          all.where((i) => i.isSubmitted && i.syncStatus.isUnsynced).length,
    );
  }

  @override
  Future<Inspection?> findById(String inspectionId) async => store[inspectionId];

  @override
  Future<Inspection> createDraft({
    required Vehicle vehicle,
    required Evaluator evaluator,
    required InspectionTemplate template,
  }) async {
    _sequence++;
    final id = 'insp-$_sequence';
    final now = DateTime(2026, 8, 25, 10, _sequence);
    final inspection = Inspection(
      id: id,
      referenceNumber: 'INS-20260825-000$_sequence',
      templateId: template.id,
      templateVersion: template.version,
      evaluatorId: evaluator.id,
      evaluatorName: evaluator.name,
      vehicle: vehicle.copyWith(
        registrationNumber: vehicle.registrationNumber.trim().toUpperCase(),
        vin: vehicle.vin.trim().toUpperCase(),
      ),
      items: [
        for (final point in template.allPoints)
          InspectionItem(
            id: '$id-${point.id}',
            inspectionId: id,
            pointId: point.id,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    _put(inspection);
    return inspection;
  }

  @override
  Future<Inspection> updateVehicle({
    required String inspectionId,
    required Vehicle vehicle,
  }) async {
    final updated = _require(inspectionId).copyWith(vehicle: vehicle);
    _put(updated);
    return updated;
  }

  @override
  Future<Inspection> setItemStatus({
    required String inspectionId,
    required String pointId,
    required ItemStatus status,
  }) async {
    final inspection = _require(inspectionId);
    final item = inspection.itemForPoint(pointId);
    if (item == null) {
      throw const ValidationFailure(message: 'Unknown point');
    }
    return _rescore(_replaceItem(inspection, item.copyWith(status: status)));
  }

  @override
  Future<Inspection> setItemComment({
    required String inspectionId,
    required String pointId,
    required String? comment,
  }) async {
    final inspection = _require(inspectionId);
    final item = inspection.itemForPoint(pointId);
    if (item == null) {
      throw const ValidationFailure(message: 'Unknown point');
    }
    final trimmed = comment?.trim();
    final updated = _replaceItem(
      inspection,
      item.copyWith(
        comment: trimmed,
        clearComment: trimmed == null || trimmed.isEmpty,
      ),
    );
    _put(updated);
    return updated;
  }

  @override
  Future<Inspection> attachPhoto({
    required String inspectionId,
    required String pointId,
    required PhotoSource source,
  }) async {
    final inspection = _require(inspectionId);
    final item = inspection.itemForPoint(pointId);
    if (item == null) {
      throw const ValidationFailure(message: 'Unknown point');
    }
    final photo = InspectionPhoto(
      id: '${item.id}-photo-${item.photos.length}',
      inspectionId: inspectionId,
      itemId: item.id,
      localPath: 'memory://${item.id}-${item.photos.length}',
      createdAt: DateTime(2026, 8, 25),
      byteSize: 2048,
    );
    final updated = _replaceItem(
      inspection,
      item.copyWith(photos: [...item.photos, photo]),
    );
    _put(updated);
    return updated;
  }

  @override
  Future<Inspection> removePhoto({
    required String inspectionId,
    required String photoId,
  }) async {
    final inspection = _require(inspectionId);
    final updated = inspection.copyWith(
      items: [
        for (final item in inspection.items)
          item.copyWith(
            photos: item.photos.where((p) => p.id != photoId).toList(),
          ),
      ],
    );
    _put(updated);
    return updated;
  }

  @override
  Future<Inspection> replacePhoto({
    required String inspectionId,
    required String pointId,
    required String photoId,
    required PhotoSource source,
  }) async {
    await removePhoto(inspectionId: inspectionId, photoId: photoId);
    return attachPhoto(
      inspectionId: inspectionId,
      pointId: pointId,
      source: source,
    );
  }

  @override
  Future<Inspection> submit({
    required String inspectionId,
    required InspectionTemplate template,
  }) async {
    final inspection = _require(inspectionId);
    final missing = inspection.unansweredRequiredPoints(template);
    if (missing.isNotEmpty) {
      throw ValidationFailure(
        message: '${missing.length} required points are still unanswered.',
      );
    }
    final graded = _rescore(inspection);
    final submitted = graded.copyWith(
      status: InspectionStatus.submitted,
      submittedAt: DateTime(2026, 8, 25, 11),
      syncStatus: SyncStatus.pending,
    );
    _put(submitted);
    return submitted;
  }

  @override
  Future<void> delete(String inspectionId) async {
    store.remove(inspectionId);
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> retrySync(String inspectionId) async {
    _put(_require(inspectionId).copyWith(syncStatus: SyncStatus.pending));
  }
}
