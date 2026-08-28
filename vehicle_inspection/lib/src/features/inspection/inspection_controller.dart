import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/failures.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/entities/inspection_template.dart';
import '../../domain/entities/item_status.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/inspection_repository.dart';
import '../../domain/services/grading_service.dart';
import '../../domain/services/photo_service.dart';
import 'inspection_session.dart';

/// Drives one inspection.
///
/// Every mutation writes through the repository (and therefore to SQLite)
/// before the new state is published, so what the screen shows and what the
/// device has stored can never disagree. Nothing here awaits the network.
///
/// Methods rethrow [Failure]s rather than parking them in `state`: a failed
/// photo attach should surface as a snackbar over the intact checklist, not
/// replace the whole screen with an error.
class InspectionController extends FamilyAsyncNotifier<InspectionSession, String> {
  @override
  Future<InspectionSession> build(String arg) async {
    // Reload once a sync run finishes, so the server reference and sync status
    // on the detail and confirmation screens follow the upload as it lands.
    // Keyed on `lastSyncedAt` rather than on every DAO write, so the evaluator's
    // own edits — which already update state directly — do not cause a reload.
    ref.listen(syncStateProvider, (previous, next) {
      final before = previous?.value?.lastSyncedAt;
      final after = next.value?.lastSyncedAt;
      if (after != null && after != before) ref.invalidateSelf();
    });

    final repository = ref.watch(inspectionRepositoryProvider);
    final inspection = await repository.findById(arg);
    if (inspection == null) {
      throw const StorageFailure(
        message: 'That inspection is no longer on this device.',
      );
    }
    return _toSession(inspection);
  }

  InspectionRepository get _repository =>
      ref.read(inspectionRepositoryProvider);

  Future<void> setStatus({
    required String pointId,
    required ItemStatus status,
  }) async {
    final updated = await _repository.setItemStatus(
      inspectionId: arg,
      pointId: pointId,
      status: status,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  Future<void> setComment({
    required String pointId,
    required String? comment,
  }) async {
    final updated = await _repository.setItemComment(
      inspectionId: arg,
      pointId: pointId,
      comment: comment,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  Future<void> addPhoto({
    required String pointId,
    required PhotoSource source,
  }) async {
    final updated = await _repository.attachPhoto(
      inspectionId: arg,
      pointId: pointId,
      source: source,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  Future<void> removePhoto(String photoId) async {
    final updated = await _repository.removePhoto(
      inspectionId: arg,
      photoId: photoId,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  Future<void> replacePhoto({
    required String pointId,
    required String photoId,
    required PhotoSource source,
  }) async {
    final updated = await _repository.replacePhoto(
      inspectionId: arg,
      pointId: pointId,
      photoId: photoId,
      source: source,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final updated = await _repository.updateVehicle(
      inspectionId: arg,
      vehicle: vehicle,
    );
    state = AsyncValue.data(await _toSession(updated));
  }

  /// Finalises the inspection. Throws a [ValidationFailure] when required
  /// points or mandatory photos are outstanding.
  Future<Inspection> submit() async {
    final session = state.value ?? await future;
    final updated = await _repository.submit(
      inspectionId: arg,
      template: session.template,
    );
    state = AsyncValue.data(await _toSession(updated));
    return updated;
  }

  Future<void> retrySync() async {
    await _repository.retrySync(arg);
    ref.invalidateSelf();
  }

  /// Permanently removes a draft and its photo files.
  Future<void> discard() => _repository.delete(arg);

  /// Resolves the template and recomputes the grade.
  Future<InspectionSession> _toSession(Inspection inspection) async {
    final template = await _resolveTemplate(inspection);
    final grading = GradingService(rules: template.gradingRules)
        .evaluateInspection(items: inspection.items, template: template);
    return InspectionSession(
      inspection: inspection,
      template: template,
      grading: grading,
    );
  }

  Future<InspectionTemplate> _resolveTemplate(Inspection inspection) async {
    final templates = ref.read(templateRepositoryProvider);
    // Fall back to the active template only if the captured revision is gone,
    // which should not happen since versions are never deleted.
    return await templates.getTemplate(
          inspection.templateId,
          version: inspection.templateVersion,
        ) ??
        await templates.getActiveTemplate();
  }
}

final inspectionControllerProvider = AsyncNotifierProvider.family<
    InspectionController, InspectionSession, String>(InspectionController.new);
