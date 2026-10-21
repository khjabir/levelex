import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/pt/planner/workout_planner.dart';

void main() {
  const planner = WorkoutPlanner();

  test('a bare interval request has no warm-up or cool-down', () {
    final plan = planner.build(
      const PtRequest(
        duration: Duration(minutes: 4),
        fixed: [
          FixedItem(
            movementId: 'burpee',
            sets: 1,
            reps: 30,
            seconds: 20,
            restSeconds: 10,
            capSeconds: 20,
          ),
          FixedItem(
            movementId: 'plank',
            sets: 1,
            reps: 0,
            seconds: 20,
            restSeconds: 10,
          ),
        ],
        bare: true,
        title: 'Tabata',
      ),
    );
    expect(plan.warmUp, isEmpty);
    expect(plan.coolDown, isEmpty);
    expect(plan.main.length, 2);
    expect(plan.title, 'Tabata');
    final round = plan.main.first;
    expect(round.capSeconds, 20);
    expect(round.rest, const Duration(seconds: 10));
    // The clock, not the rep estimate, sizes the round.
    expect(round.workSecondsPerSet, 20);
    expect(plan.main.last.isTimed, isTrue);
    expect(plan.main.last.seconds, 20);
  });

  test('a routine request keeps its warm-up and cool-down', () {
    final plan = planner.build(
      const PtRequest(
        duration: Duration(minutes: 30),
        fixed: [FixedItem(movementId: 'squat', sets: 3, reps: 12)],
      ),
    );
    expect(plan.warmUp, isNotEmpty);
    expect(plan.coolDown, isNotEmpty);
    expect(plan.main.single.capSeconds, isNull);
  });
}
