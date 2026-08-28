import '../../domain/entities/grading.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/entities/inspection_template.dart';

/// Everything a checklist screen needs, resolved once.
///
/// The inspection alone is not enough to render: titles, categories, ordering
/// and photo limits all live on the template it was captured against, and the
/// live score is derived from both. Bundling them means the UI never has to
/// juggle three separate async values that can arrive out of step.
class InspectionSession {
  const InspectionSession({
    required this.inspection,
    required this.template,
    required this.grading,
  });

  final Inspection inspection;

  /// The exact template revision this inspection was created with.
  final InspectionTemplate template;

  /// Recomputed on every change, so the score shown while inspecting is the
  /// same number that will be submitted.
  final GradingResult grading;

  /// Required points still unanswered. Empty means submission is allowed.
  List<InspectionPoint> get blockingPoints =>
      inspection.unansweredRequiredPoints(template);

  /// Failed points that still owe a mandatory photo.
  List<InspectionPoint> get pointsNeedingPhotos =>
      inspection.pointsMissingRequiredPhotos(template);

  bool get canSubmit =>
      blockingPoints.isEmpty && pointsNeedingPhotos.isEmpty;

  /// One line explaining why the submit button is disabled, or `null` when it
  /// is not.
  String? get submitBlockedReason {
    if (blockingPoints.isNotEmpty) {
      final count = blockingPoints.length;
      return count == 1
          ? '1 required point still needs an answer'
          : '$count required points still need an answer';
    }
    if (pointsNeedingPhotos.isNotEmpty) {
      final count = pointsNeedingPhotos.length;
      return count == 1
          ? '1 failed point needs a photo'
          : '$count failed points need photos';
    }
    return null;
  }

  /// Completed and total counts for one category, used by the section headers.
  (int completed, int total) progressFor(InspectionCategory category) {
    var completed = 0;
    for (final point in category.points) {
      final item = inspection.itemForPoint(point.id);
      if (item != null && item.isAnswered) completed++;
    }
    return (completed, category.points.length);
  }

  InspectionSession copyWith({
    Inspection? inspection,
    InspectionTemplate? template,
    GradingResult? grading,
  }) =>
      InspectionSession(
        inspection: inspection ?? this.inspection,
        template: template ?? this.template,
        grading: grading ?? this.grading,
      );
}
