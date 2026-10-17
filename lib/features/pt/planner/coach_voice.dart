import '../../../models/form_status.dart';
import '../models/pt_record.dart';
import '../models/workout_plan.dart';

/// What the trainer says. Rule based and on-device: no network, no account.
abstract final class CoachVoice {
  static String greeting(DateTime now, {String? title}) {
    final h = now.hour;
    final part = h < 5
        ? 'Burning the midnight oil'
        : h < 12
        ? 'Good morning'
        : h < 17
        ? 'Good afternoon'
        : h < 22
        ? 'Good evening'
        : 'Late session';
    return title == null ? '$part.' : '$part, $title.';
  }

  static String planIntro(WorkoutPlan plan) => plan.rationale;

  static String beforeItem(PlanItem item, {required bool first}) {
    final m = item.movement;
    final lead = first ? 'First up' : 'Next up';
    final gear = item.equipment.isEmpty
        ? ''
        : ' Grab the ${item.equipment.map((e) => e.label.toLowerCase()).join(' and ')}.';
    return '$lead: ${m.name}, ${item.prescription}.$gear';
  }

  static String afterSet({
    required PlanItem item,
    required int setIndex,
    required int repsDone,
    required int mistakes,
  }) {
    final last = setIndex + 1 >= item.sets;
    if (item.isTimed) {
      return last ? 'Done. Shake it out.' : 'Nice hold. Rest, then again.';
    }
    if (repsDone >= item.reps && mistakes == 0) {
      return last
          ? 'Clean set. That is how it is done.'
          : 'Clean set. Rest up; same again next.';
    }
    if (repsDone >= item.reps) {
      return 'Reps are in. Tidy the form next set and it is perfect.';
    }
    final short = item.reps - repsDone;
    return 'That is $repsDone. $short short of the target; '
        '${last ? 'no problem, we build from here.' : 'make the next set count.'}';
  }

  static String restCue(PlanItem next) =>
      'Breathe. Coming up: ${next.movement.name}.';

  static String summary(PtRecord record) {
    final pct = (record.completion * 100).round();
    final verified = record.verified
        ? ''
        : ' I could not confirm it was you at the camera, so this one is not '
              'scored.';
    if (pct >= 100) {
      return 'Full session done: ${record.itemsDone} movements, '
          '${record.duration.inMinutes} minutes. Recovery starts now.$verified';
    }
    if (pct >= 60) {
      return 'Solid work: $pct% of the plan in ${record.duration.inMinutes} '
          'minutes. Finish the rest next time.$verified';
    }
    return 'Short one today, and that still counts. Come back tomorrow and '
        'we go again.$verified';
  }

  /// Advice for the next session based on this one.
  static String nextTimeTip(PtRecord record) {
    final skipped = record.items.where((i) => i.skipped).length;
    if (skipped >= 2) {
      return 'You skipped $skipped movements. Next time pick a shorter session '
          'or tell me what equipment you really have.';
    }
    final mistakes = record.totalMistakes;
    if (mistakes >= 5) {
      final worst = <FormStatus, int>{};
      for (final i in record.items) {
        for (final e in i.mistakes.entries) {
          worst[e.key] = (worst[e.key] ?? 0) + e.value;
        }
      }
      final top = worst.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return 'Form note: "${top.first.key.message}" came up ${top.first.value} '
          'times. Drop the weight or reps a little and nail it.';
    }
    if (record.completion >= 1 && mistakes == 0) {
      return 'Everything clean. Next session I will add a set or a few reps.';
    }
    return 'Consistency beats intensity. Same time tomorrow?';
  }

  static String encouragement(int setIndex, int sets) => setIndex == 0
      ? 'Set one. Settle in.'
      : setIndex + 1 == sets
      ? 'Last set. Give it everything.'
      : 'Set ${setIndex + 1} of $sets.';
}
