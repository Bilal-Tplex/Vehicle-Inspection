import '../entities/evaluator.dart';
import '../entities/inspection.dart';
import '../entities/inspection_summary.dart';
import '../entities/inspection_template.dart';
import '../entities/item_status.dart';
import '../entities/vehicle.dart';
import '../services/photo_service.dart';

/// The single entry point for creating, editing and reading inspections.
///
/// Every method is offline-first: writes land in the local database and return
/// the updated aggregate immediately, without waiting for — or requiring — the
/// network. Anything that needs to reach the backend is enqueued for the sync
/// engine instead of being awaited here.
abstract interface class InspectionRepository {
  /// Emits the full list whenever anything changes, so the dashboard and
  /// history stay live without manual refreshes.
  Stream<List<InspectionSummary>> watchSummaries();

  Future<List<InspectionSummary>> fetchSummaries({
    InspectionHistoryFilter filter = InspectionHistoryFilter.all,
    String? query,
  });

  Future<DashboardStats> fetchDashboardStats();

  /// Full aggregate, including items and photos.
  Future<Inspection?> findById(String inspectionId);

  /// Creates a draft with one pending item per point in [template].
  ///
  /// Pre-creating every item keeps progress arithmetic trivial and means the
  /// checklist screen never has to distinguish "missing row" from "unanswered".
  Future<Inspection> createDraft({
    required Vehicle vehicle,
    required Evaluator evaluator,
    required InspectionTemplate template,
  });

  /// Corrects vehicle details, e.g. from the summary screen before submitting.
  Future<Inspection> updateVehicle({
    required String inspectionId,
    required Vehicle vehicle,
  });

  Future<Inspection> setItemStatus({
    required String inspectionId,
    required String pointId,
    required ItemStatus status,
  });

  /// Passing `null` or an empty string clears the comment.
  Future<Inspection> setItemComment({
    required String inspectionId,
    required String pointId,
    required String? comment,
  });

  /// Captures, compresses and attaches a photo.
  ///
  /// Returns the inspection unchanged when the evaluator cancels the picker.
  Future<Inspection> attachPhoto({
    required String inspectionId,
    required String pointId,
    required PhotoSource source,
  });

  Future<Inspection> removePhoto({
    required String inspectionId,
    required String photoId,
  });

  /// Deletes [photoId] and captures a new image in its place.
  Future<Inspection> replacePhoto({
    required String inspectionId,
    required String pointId,
    required String photoId,
    required PhotoSource source,
  });

  /// Finalises the inspection: grades it, marks it submitted and queues it.
  ///
  /// Throws a [ValidationFailure] if required points are unanswered or a
  /// defective point is missing its mandatory photo.
  Future<Inspection> submit({
    required String inspectionId,
    required InspectionTemplate template,
  });

  /// Removes a draft and its photo files.
  Future<void> delete(String inspectionId);

  /// Re-queues an inspection whose retry budget was exhausted.
  Future<void> retrySync(String inspectionId);
}
