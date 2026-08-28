import 'inspection.dart';
import 'sync_status.dart';

/// Lightweight projection of an inspection for list screens.
///
/// The history and dashboard lists must stay fast when a device holds hundreds
/// of inspections, each with dozens of items and photos. Those screens read
/// this row-shaped view instead of hydrating the full aggregate.
class InspectionSummary {
  const InspectionSummary({
    required this.id,
    required this.referenceNumber,
    required this.registrationNumber,
    required this.vehicleName,
    required this.createdAt,
    required this.status,
    required this.syncStatus,
    required this.completedItems,
    required this.totalItems,
    this.remoteId,
    this.submittedAt,
    this.scorePercentage,
    this.gradeCode,
    this.photoCount = 0,
    this.lastSyncError,
  });

  final String id;
  final String? remoteId;
  final String referenceNumber;
  final String registrationNumber;
  final String vehicleName;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final InspectionStatus status;
  final SyncStatus syncStatus;
  final int completedItems;
  final int totalItems;
  final double? scorePercentage;
  final String? gradeCode;
  final int photoCount;
  final String? lastSyncError;

  /// The date a user would consider "the inspection date".
  DateTime get displayDate => submittedAt ?? createdAt;

  bool get isSubmitted => status == InspectionStatus.submitted;

  String get progressLabel => '$completedItems/$totalItems completed';

  String get scoreLabel => scorePercentage == null
      ? '--'
      : '${scorePercentage!.toStringAsFixed(1)}%';
}

/// Counters backing the dashboard tiles.
class DashboardStats {
  const DashboardStats({
    this.completedCount = 0,
    this.pendingSyncCount = 0,
    this.draftCount = 0,
    this.failedSyncCount = 0,
  });

  /// Inspections the evaluator has submitted, synced or not.
  final int completedCount;

  /// Submitted but still waiting to reach the backend.
  final int pendingSyncCount;

  /// Started but not yet submitted.
  final int draftCount;

  /// Exhausted their retry budget and need attention.
  final int failedSyncCount;

  static const DashboardStats empty = DashboardStats();
}

/// Filters offered by the history screen.
enum InspectionHistoryFilter {
  all('All'),
  drafts('Drafts'),
  submitted('Submitted'),
  pendingSync('Pending sync');

  const InspectionHistoryFilter(this.label);

  final String label;

  bool matches(InspectionSummary summary) => switch (this) {
        InspectionHistoryFilter.all => true,
        InspectionHistoryFilter.drafts =>
          summary.status == InspectionStatus.draft,
        InspectionHistoryFilter.submitted =>
          summary.status == InspectionStatus.submitted,
        InspectionHistoryFilter.pendingSync =>
          summary.status == InspectionStatus.submitted &&
              summary.syncStatus.isUnsynced,
      };
}
