import 'inspection_item.dart';
import 'inspection_photo.dart';
import 'inspection_template.dart';
import 'item_status.dart';
import 'sync_status.dart';
import 'vehicle.dart';

/// Where an inspection sits in the evaluator workflow, independent of where it
/// sits in the sync pipeline.
enum InspectionStatus {
  draft('draft', 'In progress'),
  submitted('submitted', 'Submitted');

  const InspectionStatus(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static InspectionStatus fromWire(String? value) {
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return draft;
  }
}

/// A vehicle inspection: the vehicle, every answer, and its sync state.
///
/// The id is generated on the device, so an inspection is a complete, valid
/// record before the backend has ever seen it. [remoteId] is filled in on a
/// successful sync and never replaces the local id, which keeps foreign keys
/// and photo paths stable.
class Inspection {
  const Inspection({
    required this.id,
    required this.referenceNumber,
    required this.templateId,
    required this.templateVersion,
    required this.evaluatorId,
    required this.evaluatorName,
    required this.vehicle,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.remoteId,
    this.status = InspectionStatus.draft,
    this.submittedAt,
    this.syncStatus = SyncStatus.draftLocal,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.scorePercentage,
    this.gradeCode,
    this.obtainedPoints,
    this.maxPoints,
  });

  final String id;

  /// Set by the backend once accepted.
  final String? remoteId;

  /// Human-facing identifier generated on the device, so the evaluator has an
  /// inspection ID to hand over even while offline.
  final String referenceNumber;

  final String templateId;

  /// Version of the template this inspection was captured against, so an
  /// updated template never rewrites history.
  final int templateVersion;

  final String evaluatorId;
  final String evaluatorName;
  final Vehicle vehicle;
  final InspectionStatus status;
  final List<InspectionItem> items;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? submittedAt;

  final SyncStatus syncStatus;
  final int syncAttempts;
  final String? lastSyncError;

  /// Grade snapshot, denormalised so the history list can render without
  /// loading every item and photo.
  final double? scorePercentage;
  final String? gradeCode;
  final int? obtainedPoints;
  final int? maxPoints;

  bool get isSubmitted => status == InspectionStatus.submitted;
  bool get isDraft => status == InspectionStatus.draft;

  int get totalItems => items.length;
  int get completedItems => items.where((item) => item.isAnswered).length;

  /// Fraction between 0 and 1, for the progress indicator.
  double get progress => totalItems == 0 ? 0 : completedItems / totalItems;

  String get progressLabel => '$completedItems/$totalItems completed';

  List<InspectionPhoto> get allPhotos => [
        for (final item in items) ...item.photos,
      ];

  int get photoCount => allPhotos.length;

  InspectionItem? itemForPoint(String pointId) {
    for (final item in items) {
      if (item.pointId == pointId) return item;
    }
    return null;
  }

  /// Required points the evaluator still has to answer. Finalisation is
  /// blocked while this is non-empty.
  List<InspectionPoint> unansweredRequiredPoints(InspectionTemplate template) {
    final answered = {
      for (final item in items)
        if (item.isAnswered) item.pointId,
    };
    return template.allPoints
        .where((point) => point.isRequired && !answered.contains(point.id))
        .toList();
  }

  /// Defective points that owe a photo under the template evidence policy.
  List<InspectionPoint> pointsMissingRequiredPhotos(
    InspectionTemplate template,
  ) {
    final missing = <InspectionPoint>[];
    for (final item in items) {
      final point = template.pointById(item.pointId);
      if (point == null) continue;
      if (point.requiresPhotoOnFail &&
          item.status == ItemStatus.fail &&
          item.photos.isEmpty) {
        missing.add(point);
      }
    }
    return missing;
  }

  bool canSubmit(InspectionTemplate template) =>
      unansweredRequiredPoints(template).isEmpty &&
      pointsMissingRequiredPhotos(template).isEmpty;

  Inspection copyWith({
    String? remoteId,
    Vehicle? vehicle,
    InspectionStatus? status,
    List<InspectionItem>? items,
    DateTime? updatedAt,
    DateTime? submittedAt,
    SyncStatus? syncStatus,
    int? syncAttempts,
    String? lastSyncError,
    bool clearSyncError = false,
    double? scorePercentage,
    String? gradeCode,
    int? obtainedPoints,
    int? maxPoints,
  }) =>
      Inspection(
        id: id,
        referenceNumber: referenceNumber,
        templateId: templateId,
        templateVersion: templateVersion,
        evaluatorId: evaluatorId,
        evaluatorName: evaluatorName,
        createdAt: createdAt,
        remoteId: remoteId ?? this.remoteId,
        vehicle: vehicle ?? this.vehicle,
        status: status ?? this.status,
        items: items ?? this.items,
        updatedAt: updatedAt ?? this.updatedAt,
        submittedAt: submittedAt ?? this.submittedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        syncAttempts: syncAttempts ?? this.syncAttempts,
        lastSyncError:
            clearSyncError ? null : (lastSyncError ?? this.lastSyncError),
        scorePercentage: scorePercentage ?? this.scorePercentage,
        gradeCode: gradeCode ?? this.gradeCode,
        obtainedPoints: obtainedPoints ?? this.obtainedPoints,
        maxPoints: maxPoints ?? this.maxPoints,
      );

  /// Payload sent to the backend. Photo binaries are uploaded separately and
  /// referenced by id, so this stays small enough to retry cheaply.
  Map<String, dynamic> toJson() => {
        'id': id,
        'remoteId': remoteId,
        'referenceNumber': referenceNumber,
        'templateId': templateId,
        'templateVersion': templateVersion,
        'evaluatorId': evaluatorId,
        'evaluatorName': evaluatorName,
        'vehicle': vehicle.toJson(),
        'status': status.wireValue,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'submittedAt': submittedAt?.toIso8601String(),
        'scorePercentage': scorePercentage,
        'gradeCode': gradeCode,
        'obtainedPoints': obtainedPoints,
        'maxPoints': maxPoints,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory Inspection.fromJson(Map<String, dynamic> json) => Inspection(
        id: json['id'] as String,
        remoteId: json['remoteId'] as String?,
        referenceNumber: json['referenceNumber'] as String,
        templateId: json['templateId'] as String,
        templateVersion: (json['templateVersion'] as num).toInt(),
        evaluatorId: json['evaluatorId'] as String,
        evaluatorName: json['evaluatorName'] as String,
        vehicle: Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
        status: InspectionStatus.fromWire(json['status'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        submittedAt: json['submittedAt'] == null
            ? null
            : DateTime.parse(json['submittedAt'] as String),
        scorePercentage: (json['scorePercentage'] as num?)?.toDouble(),
        gradeCode: json['gradeCode'] as String?,
        obtainedPoints: (json['obtainedPoints'] as num?)?.toInt(),
        maxPoints: (json['maxPoints'] as num?)?.toInt(),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => InspectionItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
