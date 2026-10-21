import 'dart:math' as math;

import '../models/equipment.dart';
import '../models/movement.dart';
import '../models/movement_library.dart';
import '../models/muscle_group.dart';
import '../models/workout_plan.dart';

/// Builds a session from a [PtRequest]. Deterministic for a given seed, so
/// "shuffle" is just seed + 1. Pure Dart.
class WorkoutPlanner {
  const WorkoutPlanner({this.library = MovementLibrary.all});

  final List<Movement> library;

  WorkoutPlan build(PtRequest request) {
    final rng = math.Random(request.seed * 7919 + request.duration.inMinutes);
    final total = request.duration.inSeconds;
    final warmBudget = (total * 0.13).clamp(120, 360).round();
    final coolBudget = (total * 0.10).clamp(90, 300).round();
    final mainBudget = math.max(180, total - warmBudget - coolBudget);
    final targets = request.targetMuscles.isEmpty
        ? MuscleGroup.full
        : request.targetMuscles;

    final warmUp = _fillTimed(
      request,
      rng,
      phase: PlanPhase.warmUp,
      budget: warmBudget,
      targets: targets,
      maxItems: 5,
    );
    List<PlanItem> stretches() => _fillTimed(
      request,
      rng,
      phase: PlanPhase.coolDown,
      budget: mainBudget,
      targets: targets,
      maxItems: 8,
      seconds: 45,
    );
    var main = request.mode == WorkoutMode.hiit
        ? _hiit(request, rng, mainBudget)
        : request.mode == WorkoutMode.mobility
        ? stretches()
        : _mainWork(request, rng, mainBudget, targets);
    // A custom focus such as mobility alone has no main-phase movements, so
    // the session becomes a stretch block rather than an empty one.
    if (main.isEmpty) main = stretches();
    final worked = {
      for (final i in main) ...i.movement.primary,
      for (final i in main) ...i.movement.secondary,
    };
    final coolDown = _fillTimed(
      request,
      rng,
      phase: PlanPhase.coolDown,
      budget: coolBudget,
      targets: worked.isEmpty ? targets : worked,
      maxItems: 5,
    );
    return WorkoutPlan(
      request: request,
      warmUp: warmUp,
      main: main,
      coolDown: coolDown,
      rationale: _rationale(request, main, targets),
    );
  }

  /// A different movement for the same slot: overlapping primary muscles,
  /// doable with the available equipment, not already in the plan.
  PlanItem? alternative(WorkoutPlan plan, PlanItem item, {int seed = 0}) {
    final used = {for (final i in plan.all) i.movement.id};
    final rng = math.Random(seed + item.movement.id.hashCode);
    Iterable<Movement> matching({required bool allowUsed}) => library
        .where((m) => m.phases.contains(item.phase))
        .where((m) => m.id != item.movement.id)
        .where((m) => allowUsed || !used.contains(m.id))
        .where((m) => m.canDoWith(plan.request.equipment))
        .where((m) => m.primary.intersection(item.movement.primary).isNotEmpty);
    var candidates = matching(allowUsed: false).toList()..shuffle(rng);
    if (candidates.isEmpty) {
      candidates = matching(allowUsed: true).toList()..shuffle(rng);
    }
    if (candidates.isEmpty) return null;
    final m = candidates.first;
    return _prescribe(
      m,
      item.phase,
      plan.request,
      equipment: m.equipmentFor(plan.request.equipment) ?? const {},
    );
  }

  // ---------------------------------------------------------------------------

  List<PlanItem> _fillTimed(
    PtRequest request,
    math.Random rng, {
    required PlanPhase phase,
    required int budget,
    required Set<MuscleGroup> targets,
    required int maxItems,
    int? seconds,
  }) {
    final candidates = library
        .where((m) => m.phases.contains(phase))
        .where((m) => m.canDoWith(request.equipment));
    // Score once per movement so the comparator is consistent.
    final scores = {
      for (final m in candidates)
        m.id: _affinity(m, targets) + rng.nextDouble() * 1.5,
    };
    final pool = candidates.toList()
      ..sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));
    final items = <PlanItem>[];
    var used = 0;
    for (final m in pool) {
      if (items.length >= maxItems) break;
      final item = _prescribe(
        m,
        phase,
        request,
        equipment: m.equipmentFor(request.equipment) ?? const {},
        forceSingleSet: true,
        secondsOverride: seconds,
      );
      final cost = item.estimated.inSeconds + 15;
      if (used + cost > budget && items.length >= 2) continue;
      items.add(item);
      used += cost;
      if (used >= budget) break;
    }
    return items;
  }

  List<PlanItem> _mainWork(
    PtRequest request,
    math.Random rng,
    int budget,
    Set<MuscleGroup> targets,
  ) {
    final pool = library
        .where((m) => m.phases.contains(PlanPhase.main))
        .where((m) => m.canDoWith(request.equipment))
        .where((m) => m.primary.intersection(targets).isNotEmpty)
        .toList();
    if (pool.isEmpty) return const [];
    // Compound movements first, then isolation; equipment-based work is
    // favoured when the user has equipment (that is why they told us).
    double score(Movement m) {
      var s = _affinity(m, targets) * 2;
      if (m.compound) s += 1.5;
      if (!m.bodyweight && request.equipment.isNotEmpty) s += 1.2;
      if (m.tracking.usesCamera) s += 0.4;
      return s + rng.nextDouble() * 1.2;
    }

    final scores = {for (final m in pool) m.id: score(m)};
    pool.sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));

    final items = <PlanItem>[];
    final covered = <MuscleGroup>{};
    var used = 0;
    final targetList = targets.toList();
    // Round-robin over target muscles so every one gets attention.
    var guard = 0;
    while (used < budget && guard++ < 40) {
      Movement? pick;
      for (final muscle in targetList) {
        if (covered.contains(muscle) && !covered.containsAll(targets)) {
          continue;
        }
        pick = pool.firstWhere(
          (m) =>
              m.primary.contains(muscle) &&
              !items.any((i) => i.movement.id == m.id),
          orElse: () => pool.firstWhere(
            (m) => !items.any((i) => i.movement.id == m.id),
            orElse: () => pool.first,
          ),
        );
        if (items.any((i) => i.movement.id == pick!.id)) {
          pick = null;
          continue;
        }
        break;
      }
      if (pick == null) {
        // Everything covered once: allow a second pass through the pool.
        pick = pool.cast<Movement?>().firstWhere(
          (m) => !items.any((i) => i.movement.id == m!.id),
          orElse: () => null,
        );
        if (pick == null) break;
      }
      final item = _prescribe(
        pick,
        PlanPhase.main,
        request,
        equipment: pick.equipmentFor(request.equipment) ?? const {},
      );
      final cost = item.estimated.inSeconds + 30;
      if (used + cost > budget) {
        if (items.length >= 3) break;
        // Trim sets to fit when the session is short.
        final trimmed = item.copyWith(sets: math.max(1, item.sets - 1));
        if (used + trimmed.estimated.inSeconds + 30 > budget) break;
        items.add(trimmed);
        used += trimmed.estimated.inSeconds + 30;
      } else {
        items.add(item);
        used += cost;
      }
      covered.addAll(pick.primary);
    }
    return items;
  }

  List<PlanItem> _hiit(PtRequest request, math.Random rng, int budget) {
    const work = 40;
    const restSeconds = 20;
    final pool =
        library
            .where((m) => m.phases.contains(PlanPhase.main))
            .where((m) => m.canDoWith(request.equipment))
            .where(
              (m) =>
                  m.primary.contains(MuscleGroup.cardio) ||
                  m.id == 'squat' ||
                  m.id == 'push_up' ||
                  m.id == 'mountain_climbers' ||
                  m.id == 'lunge' ||
                  m.id == 'plank',
            )
            .toList()
          ..shuffle(rng);
    final perRound = pool.take(5).toList();
    if (perRound.isEmpty) return const [];
    final roundSeconds = perRound.length * (work + restSeconds);
    final rounds = (budget / roundSeconds).floor().clamp(1, 4);
    return [
      for (final m in perRound)
        PlanItem(
          movement: m,
          phase: PlanPhase.main,
          sets: rounds,
          reps: m.isTimed ? 0 : (work / m.secondsPerRep).round(),
          seconds: work,
          rest: const Duration(seconds: restSeconds),
          equipment: m.equipmentFor(request.equipment) ?? const {},
        ),
    ];
  }

  PlanItem _prescribe(
    Movement m,
    PlanPhase phase,
    PtRequest request, {
    required Set<Equipment> equipment,
    bool forceSingleSet = false,
    int? secondsOverride,
  }) {
    final level = request.level;
    final sets = forceSingleSet || phase != PlanPhase.main ? 1 : level.sets;
    final reps = (m.baseReps * level.repFactor).round().clamp(5, 30);
    final seconds =
        secondsOverride ?? (m.baseSeconds * level.repFactor).round();
    return PlanItem(
      movement: m,
      phase: phase,
      sets: sets,
      reps: reps,
      seconds: seconds,
      rest: phase == PlanPhase.main ? level.rest : const Duration(seconds: 10),
      equipment: equipment,
    );
  }

  double _affinity(Movement m, Set<MuscleGroup> targets) =>
      m.primary.intersection(targets).length * 2.0 +
      m.secondary.intersection(targets).length * 0.7;

  String _rationale(
    PtRequest request,
    List<PlanItem> main,
    Set<MuscleGroup> targets,
  ) {
    final muscles = targets.map((m) => m.label.toLowerCase()).toList();
    final musclesText = muscles.length <= 1
        ? muscles.join()
        : '${muscles.sublist(0, muscles.length - 1).join(', ')} and ${muscles.last}';
    final gear = request.equipment.isEmpty
        ? 'bodyweight only'
        : request.equipment.map((e) => e.label.toLowerCase()).join(', ');
    final picks = main.take(3).map((i) => i.movement.name.toLowerCase());
    final picksText = picks.isEmpty
        ? 'a short circuit'
        : picks.length == 1
        ? picks.first
        : '${picks.take(picks.length - 1).join(', ')} and ${picks.last}';
    return '${request.mode == WorkoutMode.custom ? 'Custom focus' : request.mode.label} '
        'for ${request.duration.inMinutes} minutes at ${request.level.label.toLowerCase()} '
        'level: $musclesText. With $gear I opened with $picksText, '
        'warm-up and cool-down included.';
  }
}
