import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/equipment.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/movement_library.dart';
import 'package:levelex/features/pt/models/muscle_group.dart';
import 'package:levelex/features/strength/logic/starter_plans.dart';
import 'package:levelex/features/strength/models/progression_rule.dart';
import 'package:levelex/features/strength/models/routine.dart';

final everything = Equipment.values.toSet();

String Function() counter(String prefix) {
  var n = 0;
  return () => '$prefix${n++}';
}

void main() {
  test('four plans are registered with unique ids', () {
    expect(StarterPlans.all.length, 4);
    expect({for (final p in StarterPlans.all) p.id}.length, 4);
    expect(StarterPlans.byId('ppl'), same(StarterPlans.ppl));
    expect(StarterPlans.byId('nope'), isNull);
  });

  test('every template id exists in the library', () {
    for (final plan in StarterPlans.all) {
      for (final day in plan.days) {
        for (final slot in day.slots) {
          expect(
            MovementLibrary.byId(slot.movementId),
            isNotNull,
            reason: '${plan.id}/${day.name}: ${slot.movementId}',
          );
        }
      }
    }
  });

  group('with all equipment', () {
    for (final plan in StarterPlans.all) {
      test('${plan.id} builds every day unchanged', () {
        final routine = plan.build(everything, newId: counter('id'));

        expect(routine.starterId, plan.id);
        expect(routine.name, plan.name);
        expect(routine.schedule, plan.schedule);
        expect(routine.days.length, plan.days.length);
        expect(routine.id, 'id0');
        expect(
          {for (final d in routine.days) d.id}.length,
          routine.days.length,
        );

        for (var i = 0; i < plan.days.length; i++) {
          final built = routine.days[i];
          final template = plan.days[i];
          expect(built.exercises, isNotEmpty);
          expect(built.exercises.length, template.slots.length);
          expect(built.mode, template.mode);
          expect(built.minutes, inInclusiveRange(45, 60));
          for (var j = 0; j < built.exercises.length; j++) {
            final ex = built.exercises[j];
            expect(ex.movementId, template.slots[j].movementId);
            final movement = MovementLibrary.byId(ex.movementId);
            expect(movement, isNotNull);
            expect(movement!.canDoWith(everything), isTrue);
            expect(ex.repsMin, lessThanOrEqualTo(ex.repsMax));
            expect(ex.repsMin, greaterThanOrEqualTo(5));
            if (movement.isTimed) expect(ex.seconds, isNotNull);
          }
        }
      });
    }
  });

  group('bodyweight only', () {
    for (final plan in StarterPlans.all) {
      test('${plan.id} still has at least one doable day', () {
        final routine = plan.build(const {}, newId: counter('bw'));
        expect(routine.days, isNotEmpty);
        for (final day in routine.days) {
          expect(day.exercises, isNotEmpty);
          final ids = <String>{};
          for (final ex in day.exercises) {
            final movement = MovementLibrary.byId(ex.movementId);
            expect(movement, isNotNull, reason: ex.movementId);
            expect(
              movement!.canDoWith(const {}),
              isTrue,
              reason: ex.movementId,
            );
            expect(movement.phases, contains(PlanPhase.main));
            expect(ids.add(ex.movementId), isTrue, reason: 'duplicate on day');
          }
        }
      });
    }
  });

  test('weekday keys are 1–7 and point at built days', () {
    for (final plan in StarterPlans.all) {
      for (final equipment in [everything, <Equipment>{}]) {
        final routine = plan.build(equipment, newId: counter('w'));
        final dayIds = {for (final d in routine.days) d.id};
        for (final e in routine.weekdays.entries) {
          expect(e.key, inInclusiveRange(DateTime.monday, DateTime.sunday));
          expect(dayIds, contains(e.value));
        }
        if (plan.schedule == RoutineSchedule.weekdays) {
          expect(routine.weekdays.length, routine.days.length);
        } else {
          expect(routine.weekdays, isEmpty);
        }
      }
    }
  });

  test('push/pull/legs lands on Mon/Wed/Fri with matching modes', () {
    final routine = StarterPlans.ppl.build(everything, newId: counter('p'));
    expect(routine.trainingWeekdays, [
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]);
    expect(routine.day(routine.weekdays[DateTime.monday])!.name, 'Push');
    expect(routine.day(routine.weekdays[DateTime.friday])!.name, 'Legs');
    final push = routine.days.first;
    expect(push.exercises.first.movementId, 'bb_bench_press');
    expect(push.exercises.first.sets, 4);
    expect(push.exercises.first.repsMin, 6);
    expect(push.exercises.first.repsMax, 8);
    expect(push.exercises.first.prescription, '4 × 6–8');
  });

  test('upper/lower uses four weekdays', () {
    final routine = StarterPlans.upperLower.build(
      everything,
      newId: counter('u'),
    );
    expect(routine.trainingWeekdays, [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.thursday,
      DateTime.friday,
    ]);
  });

  test('5×5 rotates two days of 5 × 5 with linear progression', () {
    final routine = StarterPlans.fiveByFive.build(
      everything,
      newId: counter('f'),
    );
    expect(routine.schedule, RoutineSchedule.rotation);
    expect(routine.days.length, 2);
    expect(StarterPlans.fiveByFive.daysPerWeek, 3);
    for (final day in routine.days) {
      for (final ex in day.exercises) {
        expect(ex.sets, 5);
        expect(ex.repsMin, 5);
        expect(ex.repsMax, 5);
        expect(ex.policy, ProgressionPolicy.linear);
        expect(ex.prescription, '5 × 5');
      }
    }
    expect(routine.days[1].exercises.map((e) => e.movementId), [
      'bb_back_squat',
      'bb_overhead_press',
      'bb_deadlift',
    ]);
  });

  test('a missing movement is swapped for the closest doable one', () {
    // Dumbbells only: the cable pushdown becomes a dumbbell triceps move;
    // the barbell bench has no free chest stand-in (floor press and push-up
    // are reserved by later slots; burpees are conditioning) and is dropped.
    final routine = StarterPlans.ppl.build({
      Equipment.dumbbells,
    }, newId: counter('d'));
    final push = routine.days.first;
    final ids = push.exercises.map((e) => e.movementId).toList();
    expect(ids, [
      'db_shoulder_press',
      'db_floor_press',
      'db_lateral_raise',
      'db_kickback',
      'push_up',
    ]);
    // The substitute keeps the slot's prescription.
    final kickback = push.exercises[3];
    expect(kickback.sets, 3);
    expect(kickback.repsMax, 12);

    final bench = MovementLibrary.byId('bb_bench_press')!;
    expect(
      StarterPlan.substituteFor(
        bench,
        {Equipment.dumbbells},
        exclude: const {'db_floor_press', 'push_up'},
      ),
      isNull,
    );
    final sub = StarterPlan.substituteFor(bench, {Equipment.dumbbells});
    expect(sub!.id, 'db_floor_press');
    expect(sub.primary, contains(MuscleGroup.chest));
    expect(sub.primary, isNot(contains(MuscleGroup.cardio)));
  });

  test('substitution prefers loaded and compound stand-ins and is stable', () {
    final squat = MovementLibrary.byId('bb_back_squat')!;
    final withDumbbells = StarterPlan.substituteFor(squat, {
      Equipment.dumbbells,
    });
    expect(withDumbbells, isNotNull);
    expect(withDumbbells!.bodyweight, isFalse);
    expect(withDumbbells.compound, isTrue);
    expect(
      withDumbbells.primary.intersection(squat.primary).length,
      squat.primary.length,
    );

    final a = StarterPlan.substituteFor(squat, const {});
    final b = StarterPlan.substituteFor(squat, const {});
    expect(a!.id, b!.id);
    expect(a.bodyweight, isTrue);
    expect(a.compound, isTrue);

    // Nothing fits: null, and the slot is dropped from the day.
    final curl = MovementLibrary.byId('db_curl')!;
    expect(StarterPlan.substituteFor(curl, const {}), isNull);
    final pull = StarterPlans.ppl.days[1];
    final fitted = StarterPlan.fitDay(pull, const {});
    expect(fitted.map((e) => e.movementId), isNot(contains('db_curl')));
    expect(fitted, isNotEmpty);
  });

  test('a timed substitute carries seconds', () {
    final plank = StarterPlans.fullBody.days.first.slots.last;
    expect(plank.movementId, 'plank');
    final ex = plank.toExercise(MovementLibrary.byId('plank')!);
    expect(ex.seconds, 30);
    expect(ex.prescription, '3 × 30s');
    final wallSit = plank.toExercise(MovementLibrary.byId('wall_sit')!);
    expect(wallSit.seconds, 30);
    final sitUp = plank.toExercise(MovementLibrary.byId('sit_up')!);
    expect(sitUp.seconds, isNull);
  });

  test('ids come from the clock when no generator is given', () {
    final routine = StarterPlans.fullBody.build(everything);
    final ids = {routine.id, for (final d in routine.days) d.id};
    expect(ids.length, routine.days.length + 1);
    expect(routine.id, startsWith('fullBody_'));
  });
}
