import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../pt/models/workout_plan.dart';
import '../../pt/pt_providers.dart';
import '../models/routine.dart';

/// Builds the MY PT plan for a routine day (its exercises as the main
/// phase, wrapped in a warm-up and cool-down) and opens the plan preview.
void startRoutineDay(
  BuildContext context,
  WidgetRef ref,
  Routine routine,
  RoutineDay day, {
  bool straightToSession = false,
}) {
  final profile = ref.read(gymProfileProvider);
  final level = ref.read(ptRequestProvider).level;
  final request = PtRequest(
    duration: Duration(minutes: day.minutes),
    mode: day.mode,
    level: level,
    equipment: profile.available,
    seed: DateTime.now().millisecondsSinceEpoch % 100000,
    fixed: [
      for (final e in day.exercises)
        FixedItem(
          movementId: e.movementId,
          sets: e.sets,
          reps: e.repsMax,
          repsMin: e.repsMin == e.repsMax ? null : e.repsMin,
          seconds: e.seconds,
          policy: e.policy?.name,
        ),
    ],
    routineId: routine.id,
    routineDayId: day.id,
    title: '${routine.name} · ${day.name}',
  );
  ref.read(ptPlanProvider.notifier).generate(request);
  context.push(straightToSession ? Routes.ptSession : Routes.ptPlan);
}
