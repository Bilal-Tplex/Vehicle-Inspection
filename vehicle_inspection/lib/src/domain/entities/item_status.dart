/// Outcome recorded against a single inspection point.
///
/// [pending] is not one of the four statuses an evaluator picks; it is the
/// initial state that lets the app track "15 of 25 completed" and block
/// finalisation while required points are unanswered.
enum ItemStatus {
  pending('pending', 'Not checked'),
  pass('pass', 'Pass'),
  minorIssue('minor_issue', 'Minor Issue'),
  fail('fail', 'Fail'),
  notApplicable('na', 'N/A');

  const ItemStatus(this.wireValue, this.label);

  /// Stable identifier used in the database and in API payloads. Never derive
  /// persistence values from [Enum.name] so the enum can be renamed safely.
  final String wireValue;

  /// Human-readable label shown in the UI.
  final String label;

  /// Statuses the evaluator can actually choose.
  static const List<ItemStatus> selectable = [
    pass,
    minorIssue,
    fail,
    notApplicable,
  ];

  static ItemStatus fromWire(String? value) {
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return pending;
  }

  /// True once the evaluator has made a choice.
  bool get isAnswered => this != pending;

  /// N/A points are excluded from the score entirely, per the grading rules.
  bool get isScored => isAnswered && this != notApplicable;

  /// Fails and minor issues are what a summary highlights.
  bool get isDefect => this == fail || this == minorIssue;
}
