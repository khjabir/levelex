import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/equipment.dart';
import 'package:levelex/features/pt/models/movement_library.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/pt/planner/workout_planner.dart';
import 'package:levelex/features/strength/logic/plan_advisor.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/features/strength/models/progression_rule.dart';

LiftEntry _entry(String id, DateTime at, double kg, List<int> reps) =>
    LiftEntry(
      id: '$id-${at.millisecondsSinceEpoch}',
      movementId: id,
      startTime: at,
      sets: [for (final r in reps) LiftSet(weightKg: kg, reps: r)],
      source: LiftSource.pt,
    );

void main() {
  const planner = WorkoutPlanner();
  final gym = {Equipment.barbell, Equipment.bench, Equipment.dumbbells};

  group('PlanAdvisor', () {
    test('a routine day becomes the main phase in order', () {
      final request = PtRequest(
        equipment: gym,
        fixed: const [
          FixedItem(movementId: 'bb_bench_press', sets: 3, reps: 5),
          FixedItem(movementId: 'db_curl', sets: 3, reps: 12, repsMin: 8),
          FixedItem(movementId: 'does_not_exist', sets: 3, reps: 10),
        ],
        title: 'Push A',
      );
      final plan = planner.build(request);
      expect(plan.main.map((i) => i.movement.id), [
        'bb_bench_press',
        'db_curl',
      ]);
      expect(plan.main.first.sets, 3);
      expect(plan.main.first.reps, 5);
      expect(plan.main.last.repsMin, 8);
      expect(plan.title, 'Push A');
      expect(plan.warmUp, isNotEmpty);
      expect(plan.coolDown, isNotEmpty);
      expect(plan.main.first.loaded, isTrue);
    });

    test('suggests a heavier load after a clean session', () {
      final request = PtRequest(
        equipment: gym,
        fixed: const [
          FixedItem(movementId: 'bb_bench_press', sets: 3, reps: 5),
        ],
      );
      final plan = planner.build(request);
      final at = DateTime(2026, 10, 1, 18);
      final annotated = PlanAdvisor.annotate(
        plan,
        lifts: [
          _entry('bb_bench_press', at, 60, [5, 5, 5]),
        ],
        rules: const {},
      );
      final item = annotated.main.single;
      expect(item.suggestedKg, 62.5);
      expect(item.suggestionWhy, contains('60 kg'));
      expect(item.reps, 5);
    });

    test('a custom rule and a routine policy override the defaults', () {
      final request = PtRequest(
        equipment: gym,
        fixed: const [
          FixedItem(
            movementId: 'db_curl',
            sets: 3,
            reps: 12,
            repsMin: 8,
            policy: 'linear',
          ),
        ],
      );
      final plan = planner.build(request);
      final rule = PlanAdvisor.ruleFor(plan.main.single, request, {
        'db_curl': const ProgressionRule(incrementKg: 1),
      });
      expect(rule.policy, ProgressionPolicy.linear);
      expect(rule.incrementKg, 1);
      expect(rule.sets, 3);
      expect(rule.repsMax, 12);
    });

    test('leaves bodyweight items without history untouched', () {
      final plan = planner.build(const PtRequest(mode: WorkoutMode.push));
      final annotated = PlanAdvisor.annotate(
        plan,
        lifts: const [],
        rules: const {},
      );
      for (var i = 0; i < plan.main.length; i++) {
        expect(annotated.main[i].suggestedKg, isNull);
        expect(annotated.main[i].reps, plan.main[i].reps);
      }
      expect(MovementLibrary.byId('push_up')!.canBeLoaded, isFalse);
    });

    test('first loaded session asks for a baseline, no load', () {
      final request = PtRequest(
        equipment: gym,
        fixed: const [
          FixedItem(movementId: 'bb_bench_press', sets: 3, reps: 5),
        ],
      );
      final plan = planner.build(request);
      final annotated = PlanAdvisor.annotate(
        plan,
        lifts: const [],
        rules: const {},
      );
      expect(annotated.main.single.suggestedKg, isNull);
      expect(annotated.main.single.suggestionWhy, contains('baseline'));
    });
  });
}
