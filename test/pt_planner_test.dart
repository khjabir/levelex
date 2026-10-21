import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/equipment.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/movement_library.dart';
import 'package:levelex/features/pt/models/muscle_group.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/pt/planner/workout_planner.dart';

void main() {
  const planner = WorkoutPlanner();

  group('MovementLibrary', () {
    test('ids are unique and every movement has cues', () {
      final ids = MovementLibrary.all.map((m) => m.id).toSet();
      expect(ids.length, MovementLibrary.all.length);
      for (final m in MovementLibrary.all) {
        expect(m.cues, isNotEmpty, reason: m.id);
        expect(m.primary, isNotEmpty, reason: m.id);
      }
    });

    test('equipment options resolve against what is available', () {
      final bench = MovementLibrary.byId('bb_bench_press')!;
      expect(bench.canDoWith({Equipment.barbell}), isFalse);
      expect(bench.equipmentFor({Equipment.barbell, Equipment.bench}), {
        Equipment.barbell,
        Equipment.bench,
      });
      final dip = MovementLibrary.byId('tricep_dip')!;
      expect(dip.equipmentFor({Equipment.box}), {Equipment.box});
      expect(MovementLibrary.byId('push_up')!.equipmentFor({}), isEmpty);
    });
  });

  group('WorkoutPlanner', () {
    test(
      'a bodyweight push session uses no equipment and hits push muscles',
      () {
        final plan = planner.build(
          const PtRequest(
            duration: Duration(minutes: 30),
            mode: WorkoutMode.push,
            level: PtLevel.intermediate,
          ),
        );
        expect(plan.warmUp, isNotEmpty);
        expect(plan.main, isNotEmpty);
        expect(plan.coolDown, isNotEmpty);
        expect(plan.equipmentNeeded, isEmpty);
        for (final item in plan.main) {
          expect(
            item.movement.primary.intersection(MuscleGroup.push),
            isNotEmpty,
            reason: item.movement.id,
          );
          expect(item.sets, 3);
        }
        expect(plan.rationale, contains('Push'));
      },
    );

    test('respects the time budget within a tolerance', () {
      for (final minutes in [10, 20, 45, 60]) {
        final plan = planner.build(
          PtRequest(duration: Duration(minutes: minutes)),
        );
        final est = plan.estimatedTotal.inMinutes;
        expect(est, lessThanOrEqualTo(minutes + 4), reason: '$minutes');
        expect(
          est,
          greaterThanOrEqualTo((minutes * 0.5).floor()),
          reason: '$minutes',
        );
      }
    });

    test('uses the user\'s equipment when they have some', () {
      final plan = planner.build(
        const PtRequest(
          duration: Duration(minutes: 40),
          mode: WorkoutMode.pull,
          equipment: {Equipment.dumbbells, Equipment.pullUpBar},
        ),
      );
      expect(plan.main.any((i) => i.equipment.isNotEmpty), isTrue);
      for (final item in plan.all) {
        expect(
          item.equipment.every(
            {Equipment.dumbbells, Equipment.pullUpBar}.contains,
          ),
          isTrue,
        );
      }
    });

    test('is deterministic for a seed and changes when shuffled', () {
      const r = PtRequest(duration: Duration(minutes: 30), seed: 3);
      final a = planner.build(r).all.map((i) => i.movement.id).toList();
      final b = planner.build(r).all.map((i) => i.movement.id).toList();
      expect(a, b);
      final c = planner
          .build(r.copyWith(seed: 4))
          .all
          .map((i) => i.movement.id)
          .toList();
      expect(c, isNot(a));
    });

    test('custom focus plans only the chosen muscles', () {
      final plan = planner.build(
        const PtRequest(
          mode: WorkoutMode.custom,
          focus: {MuscleGroup.core},
          duration: Duration(minutes: 20),
        ),
      );
      for (final item in plan.main) {
        expect(item.movement.primary, contains(MuscleGroup.core));
      }
    });

    test('a mobility-only custom focus builds a stretch block', () {
      final plan = planner.build(
        const PtRequest(
          mode: WorkoutMode.custom,
          focus: {MuscleGroup.mobility},
          duration: Duration(minutes: 20),
        ),
      );
      expect(plan.main, isNotEmpty);
    });

    test('custom focus covers every chosen muscle', () {
      const focus = {MuscleGroup.chest, MuscleGroup.back, MuscleGroup.quads};
      final plan = planner.build(
        const PtRequest(
          mode: WorkoutMode.custom,
          focus: focus,
          duration: Duration(minutes: 45),
        ),
      );
      expect(plan.musclesCovered.containsAll(focus), isTrue);
    });

    test('HIIT builds timed rounds', () {
      final plan = planner.build(
        const PtRequest(
          mode: WorkoutMode.hiit,
          duration: Duration(minutes: 20),
        ),
      );
      expect(plan.main, isNotEmpty);
      expect(plan.main.every((i) => i.seconds == 40), isTrue);
      expect(plan.main.first.sets, greaterThanOrEqualTo(1));
    });

    test('beginner gets fewer sets and reps than advanced', () {
      final b = planner.build(const PtRequest(level: PtLevel.beginner));
      final a = planner.build(const PtRequest(level: PtLevel.advanced));
      expect(b.main.first.sets, 2);
      expect(a.main.first.sets, 4);
    });

    test('alternative keeps the muscle focus and equipment', () {
      final plan = planner.build(
        const PtRequest(
          mode: WorkoutMode.legs,
          duration: Duration(minutes: 15),
        ),
      );
      final item = plan.main.first;
      final alt = planner.alternative(plan, item);
      expect(alt, isNotNull);
      expect(alt!.movement.id, isNot(item.movement.id));
      expect(
        alt.movement.primary.intersection(item.movement.primary),
        isNotEmpty,
      );
      expect(alt.equipment, isEmpty);
      expect(plan.replace(item, alt).main.first.movement.id, alt.movement.id);
    });

    test('plan items estimate time including rest between sets', () {
      final item = PlanItem(
        movement: MovementLibrary.byId('push_up')!,
        phase: PlanPhase.main,
        sets: 3,
        reps: 10,
        seconds: 0,
        rest: const Duration(seconds: 45),
        equipment: const {},
      );
      expect(item.estimated.inSeconds, 3 * 30 + 2 * 45);
      expect(item.prescription, '3 × 10');
    });
  });
}
