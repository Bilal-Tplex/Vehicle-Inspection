import '../entities/grading.dart';
import '../entities/inspection_item.dart';
import '../entities/inspection_template.dart';
import '../entities/item_status.dart';

/// Turns checklist answers into a score and a letter grade.
///
/// Deliberately free of Flutter, persistence and network imports: it is a pure
/// function of (answers, rules). That is what lets the same calculation run in
/// the checklist screen for a live preview, on the summary screen, and on the
/// server later — and what makes it cheap to unit test.
///
/// The rules themselves are data ([GradingRules]), so when the admin dashboard
/// starts publishing custom scales, only the rules change, not this class.
class GradingService {
  const GradingService({this.rules = GradingRules.standard});

  final GradingRules rules;

  /// Returns a copy of this service bound to different rules, e.g. those that
  /// arrived with a template from the backend.
  GradingService withRules(GradingRules newRules) =>
      GradingService(rules: newRules);

  /// Core calculation.
  ///
  /// Excluded statuses (N/A, and points not yet answered) are removed from
  /// both the obtained score and the maximum, so they neither help nor hurt.
  GradingResult evaluate(Iterable<ScorableItem> items) {
    var obtainedPoints = 0;
    var maxPoints = 0;
    var scoredItems = 0;
    var totalItems = 0;
    final statusCounts = <ItemStatus, int>{};

    for (final item in items) {
      totalItems++;
      statusCounts.update(
        item.status,
        (count) => count + 1,
        ifAbsent: () => 1,
      );

      if (!rules.isScored(item.status)) continue;

      final weight = item.weight <= 0 ? 1 : item.weight;
      scoredItems++;
      obtainedPoints += rules.pointsFor(item.status) * weight;
      maxPoints += rules.maxPointsPerItem * weight;
    }

    final percentage =
        maxPoints == 0 ? 0.0 : (obtainedPoints / maxPoints) * 100;
    final band = rules.bandFor(percentage);

    return GradingResult(
      totalItems: totalItems,
      scoredItems: scoredItems,
      statusCounts: Map.unmodifiable(statusCounts),
      obtainedPoints: obtainedPoints,
      maxPoints: maxPoints,
      percentage: percentage,
      // An inspection with nothing scorable yet is ungraded rather than an F.
      gradeCode: maxPoints == 0 ? '-' : band.code,
      gradeLabel: maxPoints == 0 ? 'Ungraded' : band.label,
    );
  }

  /// Convenience overload that resolves each answer's weight from the
  /// template it was captured against.
  ///
  /// Answers whose point is missing from the template (because the template
  /// was revised) are skipped rather than silently scored at weight 1.
  GradingResult evaluateInspection({
    required List<InspectionItem> items,
    required InspectionTemplate template,
  }) {
    final scorable = <ScorableItem>[];
    for (final item in items) {
      final point = template.pointById(item.pointId);
      if (point == null) continue;
      scorable.add(ScorableItem(status: item.status, weight: point.weight));
    }
    return evaluate(scorable);
  }
}
