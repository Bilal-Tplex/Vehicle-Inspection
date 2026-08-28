import 'item_status.dart';

/// One letter grade and the score at which it starts.
///
/// Bands are defined by their lower bound only and matched highest-first, so a
/// set of bands can never leave a gap (89.4% still grades as B).
class GradeBand {
  const GradeBand({
    required this.code,
    required this.label,
    required this.minPercentage,
  });

  final String code;
  final String label;
  final double minPercentage;

  Map<String, dynamic> toJson() => {
        'code': code,
        'label': label,
        'minPercentage': minPercentage,
      };

  factory GradeBand.fromJson(Map<String, dynamic> json) => GradeBand(
        code: json['code'] as String,
        label: json['label'] as String,
        minPercentage: (json['minPercentage'] as num).toDouble(),
      );
}

/// The complete, serialisable definition of how a score is produced.
///
/// This is data, not code: the admin dashboard will eventually ship these from
/// the backend, and [GradingService] applies whichever set it is handed.
class GradingRules {
  const GradingRules({
    required this.id,
    required this.version,
    required this.statusPoints,
    required this.maxPointsPerItem,
    required this.bands,
    this.excludedStatuses = const {ItemStatus.notApplicable, ItemStatus.pending},
  });

  final String id;
  final int version;

  /// Points awarded for each status.
  final Map<ItemStatus, int> statusPoints;

  /// Best achievable score for a single unweighted point; drives the maximum.
  final int maxPointsPerItem;

  /// Statuses removed from the calculation entirely — they lower neither the
  /// obtained score nor the maximum.
  final Set<ItemStatus> excludedStatuses;

  /// Ordered highest-first when applied; [bandFor] sorts defensively.
  final List<GradeBand> bands;

  /// The rules described in the specification: Pass 2, Minor Issue 1, Fail 0,
  /// N/A excluded, with a 90/80/70/60 letter scale.
  static const GradingRules standard = GradingRules(
    id: 'standard',
    version: 1,
    statusPoints: {
      ItemStatus.pass: 2,
      ItemStatus.minorIssue: 1,
      ItemStatus.fail: 0,
    },
    maxPointsPerItem: 2,
    bands: [
      GradeBand(code: 'A', label: 'Excellent', minPercentage: 90),
      GradeBand(code: 'B', label: 'Good', minPercentage: 80),
      GradeBand(code: 'C', label: 'Fair', minPercentage: 70),
      GradeBand(code: 'D', label: 'Poor', minPercentage: 60),
      GradeBand(code: 'F', label: 'Failed', minPercentage: 0),
    ],
  );

  int pointsFor(ItemStatus status) => statusPoints[status] ?? 0;

  bool isScored(ItemStatus status) => !excludedStatuses.contains(status);

  /// Highest band whose lower bound the score reaches.
  GradeBand bandFor(double percentage) {
    final sorted = [...bands]
      ..sort((a, b) => b.minPercentage.compareTo(a.minPercentage));
    for (final band in sorted) {
      if (percentage >= band.minPercentage) return band;
    }
    return sorted.isNotEmpty
        ? sorted.last
        : const GradeBand(code: '-', label: 'Ungraded', minPercentage: 0);
  }

  /// Inclusive display range for a band, e.g. `80 - 89` for B.
  String displayRange(GradeBand band) {
    final sorted = [...bands]
      ..sort((a, b) => b.minPercentage.compareTo(a.minPercentage));
    final index = sorted.indexWhere((b) => b.code == band.code);
    final lower = band.minPercentage.round();
    if (index <= 0) return '$lower - 100';
    final upper = (sorted[index - 1].minPercentage - 1).round();
    return '$lower - $upper';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'statusPoints': {
          for (final entry in statusPoints.entries)
            entry.key.wireValue: entry.value,
        },
        'maxPointsPerItem': maxPointsPerItem,
        'excludedStatuses': excludedStatuses.map((s) => s.wireValue).toList(),
        'bands': bands.map((b) => b.toJson()).toList(),
      };

  factory GradingRules.fromJson(Map<String, dynamic> json) => GradingRules(
        id: json['id'] as String,
        version: (json['version'] as num).toInt(),
        statusPoints: {
          for (final entry
              in (json['statusPoints'] as Map<String, dynamic>).entries)
            ItemStatus.fromWire(entry.key): (entry.value as num).toInt(),
        },
        maxPointsPerItem: (json['maxPointsPerItem'] as num).toInt(),
        excludedStatuses: (json['excludedStatuses'] as List<dynamic>? ??
                const ['na', 'pending'])
            .map((e) => ItemStatus.fromWire(e as String))
            .toSet(),
        bands: (json['bands'] as List<dynamic>)
            .map((e) => GradeBand.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// The minimum a checklist answer must expose to be graded.
///
/// Grading depends on this tiny shape rather than on [InspectionItem], which
/// keeps the calculation testable without building persistence objects.
class ScorableItem {
  const ScorableItem({required this.status, this.weight = 1});

  final ItemStatus status;
  final int weight;
}

/// Outcome of applying [GradingRules] to a set of answers.
class GradingResult {
  const GradingResult({
    required this.totalItems,
    required this.scoredItems,
    required this.statusCounts,
    required this.obtainedPoints,
    required this.maxPoints,
    required this.percentage,
    required this.gradeCode,
    required this.gradeLabel,
  });

  /// Every item considered, including excluded ones.
  final int totalItems;

  /// Items that actually contributed to the score.
  final int scoredItems;
  final Map<ItemStatus, int> statusCounts;
  final int obtainedPoints;
  final int maxPoints;
  final double percentage;
  final String gradeCode;
  final String gradeLabel;

  static const GradingResult empty = GradingResult(
    totalItems: 0,
    scoredItems: 0,
    statusCounts: {},
    obtainedPoints: 0,
    maxPoints: 0,
    percentage: 0,
    gradeCode: '-',
    gradeLabel: 'Ungraded',
  );

  int countOf(ItemStatus status) => statusCounts[status] ?? 0;

  int get passCount => countOf(ItemStatus.pass);
  int get minorIssueCount => countOf(ItemStatus.minorIssue);
  int get failCount => countOf(ItemStatus.fail);
  int get notApplicableCount => countOf(ItemStatus.notApplicable);
  int get pendingCount => countOf(ItemStatus.pending);

  /// Items the evaluator has answered, in any way.
  int get completedItems => totalItems - pendingCount;

  bool get hasScore => maxPoints > 0;

  /// Percentage rounded for display, e.g. `85.0`.
  String get displayPercentage => '${percentage.toStringAsFixed(1)}%';
}
