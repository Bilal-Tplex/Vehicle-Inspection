import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_inspection/src/domain/entities/grading.dart';
import 'package:vehicle_inspection/src/domain/entities/item_status.dart';
import 'package:vehicle_inspection/src/domain/services/grading_service.dart';

/// Builds [count] answers with the given status.
List<ScorableItem> items(ItemStatus status, int count, {int weight = 1}) =>
    List.generate(count, (_) => ScorableItem(status: status, weight: weight));

void main() {
  const service = GradingService();

  group('the worked example from the specification', () {
    test('20 applicable points scoring 34 of 40 is 85% and a B', () {
      // 14 passes (28) + 6 minor issues (6) = 34 of a possible 40.
      final result = service.evaluate([
        ...items(ItemStatus.pass, 14),
        ...items(ItemStatus.minorIssue, 6),
      ]);

      expect(result.scoredItems, 20);
      expect(result.maxPoints, 40);
      expect(result.obtainedPoints, 34);
      expect(result.percentage, 85);
      expect(result.gradeCode, 'B');
    });
  });

  group('status points', () {
    test('pass is worth 2, minor issue 1, fail 0', () {
      expect(
        service.evaluate(items(ItemStatus.pass, 1)).obtainedPoints,
        2,
      );
      expect(
        service.evaluate(items(ItemStatus.minorIssue, 1)).obtainedPoints,
        1,
      );
      expect(
        service.evaluate(items(ItemStatus.fail, 1)).obtainedPoints,
        0,
      );
    });

    test('a failed point still raises the maximum, so it lowers the score', () {
      final result = service.evaluate([
        ...items(ItemStatus.pass, 1),
        ...items(ItemStatus.fail, 1),
      ]);

      expect(result.maxPoints, 4);
      expect(result.obtainedPoints, 2);
      expect(result.percentage, 50);
    });
  });

  group('exclusions', () {
    test('N/A is removed from both the score and the maximum', () {
      final withoutNa = service.evaluate(items(ItemStatus.pass, 10));
      final withNa = service.evaluate([
        ...items(ItemStatus.pass, 10),
        ...items(ItemStatus.notApplicable, 5),
      ]);

      expect(withNa.maxPoints, withoutNa.maxPoints);
      expect(withNa.percentage, withoutNa.percentage);
      // The N/A answers are still counted for the summary breakdown.
      expect(withNa.notApplicableCount, 5);
      expect(withNa.totalItems, 15);
      expect(withNa.scoredItems, 10);
    });

    test('unanswered points do not drag the score down mid-inspection', () {
      final result = service.evaluate([
        ...items(ItemStatus.pass, 5),
        ...items(ItemStatus.pending, 20),
      ]);

      expect(result.maxPoints, 10);
      expect(result.percentage, 100);
      expect(result.pendingCount, 20);
      expect(result.completedItems, 5);
    });

    test('an inspection with nothing scorable is ungraded, not an F', () {
      final result = service.evaluate(items(ItemStatus.notApplicable, 5));

      expect(result.hasScore, isFalse);
      expect(result.maxPoints, 0);
      expect(result.gradeCode, '-');
      expect(result.gradeLabel, 'Ungraded');
    });

    test('an empty checklist does not divide by zero', () {
      final result = service.evaluate(const []);

      expect(result.percentage, 0);
      expect(result.gradeCode, '-');
    });
  });

  group('grade bands', () {
    test('boundaries are inclusive at the lower bound', () {
      // 45 of 50 points = 90%, the first score that earns an A.
      final a = service.evaluate([
        ...items(ItemStatus.pass, 20),
        ...items(ItemStatus.minorIssue, 5),
      ]);
      expect(a.percentage, 90);
      expect(a.gradeCode, 'A');
    });

    test('a score between two bands falls to the lower one', () {
      // 8 of 9 passes = 16/18 = 88.9%.
      final result = service.evaluate([
        ...items(ItemStatus.pass, 8),
        ...items(ItemStatus.fail, 1),
      ]);

      expect(result.percentage, closeTo(88.9, 0.1));
      expect(result.gradeCode, 'B');
    });

    test('every band is reachable', () {
      String gradeFor(int passes, int fails) => service
          .evaluate([
            ...items(ItemStatus.pass, passes),
            ...items(ItemStatus.fail, fails),
          ])
          .gradeCode;

      expect(gradeFor(10, 0), 'A'); // 100%
      expect(gradeFor(17, 3), 'B'); // 85%
      expect(gradeFor(15, 5), 'C'); // 75%
      expect(gradeFor(13, 7), 'D'); // 65%
      expect(gradeFor(5, 15), 'F'); // 25%
    });
  });

  group('weighting', () {
    test('a weighted point counts more toward both score and maximum', () {
      final result = service.evaluate([
        const ScorableItem(status: ItemStatus.pass, weight: 3),
        const ScorableItem(status: ItemStatus.fail, weight: 1),
      ]);

      // 3x2 obtained out of (3 + 1) x 2 possible.
      expect(result.obtainedPoints, 6);
      expect(result.maxPoints, 8);
      expect(result.percentage, 75);
    });

    test('a non-positive weight is treated as 1 rather than erasing a point',
        () {
      final result = service.evaluate([
        const ScorableItem(status: ItemStatus.pass, weight: 0),
      ]);

      expect(result.maxPoints, 2);
      expect(result.obtainedPoints, 2);
    });
  });

  group('configurable rules', () {
    test('a stricter scale regrades the same answers', () {
      // The scenario the admin dashboard enables: same answers, new policy.
      const strict = GradingRules(
        id: 'strict',
        version: 1,
        statusPoints: {
          ItemStatus.pass: 2,
          ItemStatus.minorIssue: 0,
          ItemStatus.fail: 0,
        },
        maxPointsPerItem: 2,
        bands: [
          GradeBand(code: 'PASS', label: 'Roadworthy', minPercentage: 95),
          GradeBand(code: 'FAIL', label: 'Not roadworthy', minPercentage: 0),
        ],
      );

      final answers = [
        ...items(ItemStatus.pass, 14),
        ...items(ItemStatus.minorIssue, 6),
      ];

      expect(service.evaluate(answers).gradeCode, 'B');

      final strictResult = service.withRules(strict).evaluate(answers);
      expect(strictResult.obtainedPoints, 28);
      expect(strictResult.percentage, 70);
      expect(strictResult.gradeCode, 'FAIL');
    });

    test('rules survive a JSON round trip', () {
      final restored = GradingRules.fromJson(GradingRules.standard.toJson());

      expect(restored.id, GradingRules.standard.id);
      expect(restored.pointsFor(ItemStatus.pass), 2);
      expect(restored.pointsFor(ItemStatus.minorIssue), 1);
      expect(restored.isScored(ItemStatus.notApplicable), isFalse);
      expect(restored.bandFor(85).code, 'B');
    });

    test('display ranges read as inclusive spans', () {
      const rules = GradingRules.standard;
      expect(rules.displayRange(rules.bandFor(95)), '90 - 100');
      expect(rules.displayRange(rules.bandFor(85)), '80 - 89');
      expect(rules.displayRange(rules.bandFor(10)), '0 - 59');
    });
  });
}
