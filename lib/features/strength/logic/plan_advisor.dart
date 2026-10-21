import '../../pt/models/movement.dart';
import '../../pt/models/workout_plan.dart';
import '../models/lift_log.dart';
import '../models/progression_rule.dart';
import 'progression.dart';

/// Reads the lift log through each item's progression rule and writes the
/// suggested load (with its reason) and rep target onto the plan.
abstract final class PlanAdvisor {
  static WorkoutPlan annotate(
    WorkoutPlan plan, {
    required List<LiftEntry> lifts,
    required Map<String, ProgressionRule> rules,
  }) {
    final main = [
      for (final item in plan.main)
        annotateItem(item, plan.request, lifts, rules),
    ];
    return plan.withMain(main);
  }

  /// The rule that governs [item]: the saved one, or defaults for the
  /// movement, with the plan's own sets and reps as the targets.
  static ProgressionRule ruleFor(
    PlanItem item,
    PtRequest request,
    Map<String, ProgressionRule> rules,
  ) {
    final m = item.movement;
    var rule =
        rules[m.id] ??
        ProgressionRule.defaultsFor(
          m,
          equipment: item.equipment,
          sets: item.sets,
        );
    String? policyName;
    for (final f in request.fixed) {
      if (f.movementId == m.id) policyName = f.policy;
    }
    if (policyName != null) {
      rule = rule.copyWith(policy: ProgressionPolicy.fromName(policyName));
    }
    final repsMin =
        item.repsMin ??
        (rule.policy == ProgressionPolicy.double_ ||
                rule.policy == ProgressionPolicy.triple
            ? (item.reps - 4).clamp(1, item.reps)
            : item.reps);
    return rule.copyWith(
      sets: item.sets,
      repsMax: item.isTimed ? rule.repsMax : item.reps,
      repsMin: item.isTimed ? rule.repsMin : repsMin,
      seconds: item.isTimed ? item.seconds : rule.seconds,
    );
  }

  static PlanItem annotateItem(
    PlanItem item,
    PtRequest request,
    List<LiftEntry> lifts,
    Map<String, ProgressionRule> rules,
  ) {
    if (item.phase != PlanPhase.main) return item;
    final m = item.movement;
    final history = [
      for (final e in lifts)
        if (e.movementId == m.id) e,
    ];
    if (history.isEmpty && !item.loaded) return item;
    final rule = ruleFor(item, request, rules);
    final p = ProgressionEngine.next(rule: rule, history: history);
    if (p.kind == PrescriptionKind.first) {
      return item.loaded
          ? item.copyWith(suggestionWhy: p.why, repsMin: p.repsMin)
          : item;
    }
    if (p.kind == PrescriptionKind.off) {
      return item.loaded && p.weightKg != null
          ? item.copyWith(suggestedKg: p.weightKg, suggestionWhy: p.why)
          : item;
    }
    return item.copyWith(
      sets: p.sets,
      reps: item.isTimed ? item.reps : p.reps,
      repsMin: item.isTimed ? item.repsMin : p.repsMin,
      seconds: item.isTimed ? (p.seconds ?? item.seconds) : item.seconds,
      suggestedKg: item.loaded ? p.weightKg : null,
      suggestionWhy: p.why,
    );
  }
}
