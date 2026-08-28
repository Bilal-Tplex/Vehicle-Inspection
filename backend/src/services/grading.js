/**
 * Server-side grading.
 *
 * A deliberate mirror of the mobile `GradingService`: same status points, same
 * exclusions, same highest-first band matching. It exists for two reasons.
 *
 * 1. **Verification.** The phone computes the score so it can work offline, but
 *    a client-supplied number should never be taken on trust. Every submission
 *    is regraded here against the template it names, and a mismatch is recorded
 *    rather than silently accepted.
 * 2. **Reporting.** Dashboard aggregates regrade from stored answers, so a
 *    corrected grading rule can be replayed over history.
 *
 * If the two implementations ever disagree, this one is authoritative.
 */

export const DEFAULT_GRADING_RULES = {
  id: 'standard',
  version: 1,
  statusPoints: { pass: 2, minor_issue: 1, fail: 0 },
  maxPointsPerItem: 2,
  excludedStatuses: ['na', 'pending'],
  bands: [
    { code: 'A', label: 'Excellent', minPercentage: 90 },
    { code: 'B', label: 'Good', minPercentage: 80 },
    { code: 'C', label: 'Fair', minPercentage: 70 },
    { code: 'D', label: 'Poor', minPercentage: 60 },
    { code: 'F', label: 'Failed', minPercentage: 0 },
  ],
};

/** Highest band whose lower bound the score reaches. Never leaves a gap. */
export function bandFor(percentage, rules = DEFAULT_GRADING_RULES) {
  const sorted = [...(rules.bands ?? [])].sort(
    (a, b) => b.minPercentage - a.minPercentage,
  );
  return (
    sorted.find((band) => percentage >= band.minPercentage) ??
    sorted.at(-1) ?? { code: '-', label: 'Ungraded', minPercentage: 0 }
  );
}

/**
 * Grades a set of answers.
 *
 * @param {Array<{status: string, weight?: number}>} items
 * @param {object} rules
 */
export function grade(items, rules = DEFAULT_GRADING_RULES) {
  const excluded = new Set(rules.excludedStatuses ?? ['na', 'pending']);
  const points = rules.statusPoints ?? {};
  const perItem = rules.maxPointsPerItem ?? 2;

  const counts = {};
  let obtainedPoints = 0;
  let maxPoints = 0;
  let scoredItems = 0;

  for (const item of items) {
    counts[item.status] = (counts[item.status] ?? 0) + 1;
    if (excluded.has(item.status)) continue;

    // A non-positive weight is treated as 1 rather than erasing the point.
    const weight = item.weight > 0 ? item.weight : 1;
    scoredItems += 1;
    obtainedPoints += (points[item.status] ?? 0) * weight;
    maxPoints += perItem * weight;
  }

  const percentage = maxPoints === 0 ? 0 : (obtainedPoints / maxPoints) * 100;
  const band = bandFor(percentage, rules);
  const scorable = maxPoints > 0;

  return {
    totalItems: items.length,
    scoredItems,
    counts,
    passCount: counts.pass ?? 0,
    minorIssueCount: counts.minor_issue ?? 0,
    failCount: counts.fail ?? 0,
    notApplicableCount: counts.na ?? 0,
    pendingCount: counts.pending ?? 0,
    obtainedPoints,
    maxPoints,
    percentage: Number(percentage.toFixed(4)),
    // Nothing scorable is "ungraded", not an F. A blank inspection has not
    // failed; it has not been done.
    gradeCode: scorable ? band.code : '-',
    gradeLabel: scorable ? band.label : 'Ungraded',
  };
}

/**
 * Compares a client-reported score with the authoritative one.
 *
 * Floating point means an exact match is the wrong test; anything inside a
 * hundredth of a percent is the same number arrived at differently.
 */
export function reconcile(reported, computed) {
  const scoreMatches =
    reported.scorePercentage == null ||
    Math.abs(reported.scorePercentage - computed.percentage) < 0.01;
  const gradeMatches =
    reported.gradeCode == null || reported.gradeCode === computed.gradeCode;

  return {
    agrees: scoreMatches && gradeMatches,
    reported: {
      scorePercentage: reported.scorePercentage ?? null,
      gradeCode: reported.gradeCode ?? null,
    },
    computed: {
      scorePercentage: computed.percentage,
      gradeCode: computed.gradeCode,
    },
  };
}
