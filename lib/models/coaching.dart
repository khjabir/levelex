import 'exercise.dart';
import 'form_status.dart';

/// How loud a cue should be presented.
enum CueSeverity { info, warning }

/// One piece of coaching: what is wrong, how to fix it, what to say.
class CoachingCue {
  const CoachingCue({
    required this.status,
    required this.title,
    required this.instruction,
    required this.spoken,
    this.severity = CueSeverity.warning,
  });

  final FormStatus status;

  /// Two or three words for the HUD.
  final String title;

  /// One sentence that tells the user exactly what to change.
  final String instruction;

  /// Short phrase for the voice coach.
  final String spoken;
  final CueSeverity severity;
}

/// A mistake summarised after the set, with how often it happened.
class CoachingNote {
  const CoachingNote({
    required this.status,
    required this.count,
    required this.title,
    required this.tip,
  });

  final FormStatus status;
  final int count;
  final String title;

  /// Advice for next time.
  final String tip;
}

/// Exercise-aware coaching copy. Pure data; safe to use from tests.
abstract final class CoachingLibrary {
  /// Cue for [status] while doing [exercise]. Null for "nothing to fix"
  /// statuses such as good form or visibility problems.
  static CoachingCue? cue(FormStatus status, ExerciseType exercise) {
    switch (status) {
      case FormStatus.goodForm:
      case FormStatus.moveBack:
      case FormStatus.armNotVisible:
      case FormStatus.bodyNotVisible:
      case FormStatus.lowConfidence:
      case FormStatus.notInPosition:
        return null;
      case FormStatus.hipsTooHigh:
        return CoachingCue(
          status: status,
          title: 'Hips too high',
          instruction: exercise == ExerciseType.plank
              ? 'Lower your hips until your shoulders, hips and ankles form '
                    'one straight line.'
              : 'Drop your hips so your body is one straight line from '
                    'shoulders to heels.',
          spoken: 'Lower your hips',
        );
      case FormStatus.hipsTooLow:
        return CoachingCue(
          status: status,
          title: 'Hips sagging',
          instruction:
              'Squeeze your glutes and brace your core so your hips come up '
              'in line with your shoulders.',
          spoken: 'Lift your hips, brace your core',
        );
      case FormStatus.torsoLeaning:
        return CoachingCue(
          status: status,
          title: 'Chest up',
          instruction: exercise == ExerciseType.lunge
              ? 'Keep your torso upright and look ahead as you lower; '
                    'don\'t fold over the front knee.'
              : 'Keep your chest up and your weight in your heels; '
                    'don\'t fold forward.',
          spoken: 'Chest up',
        );
      case FormStatus.armsNotOverhead:
        return CoachingCue(
          status: status,
          title: 'Arms higher',
          instruction:
              'Swing your arms all the way up until your hands meet above '
              'your head.',
          spoken: 'Arms all the way up',
        );
      case FormStatus.goDeeper:
        return CoachingCue(
          status: status,
          title: _deeperTitle(exercise),
          instruction: _deeperInstruction(exercise),
          spoken: _deeperSpoken(exercise),
        );
      case FormStatus.slowDown:
        return CoachingCue(
          status: status,
          title: 'Slow down',
          instruction:
              'Control the movement: pause briefly at the bottom instead of '
              'bouncing. Fast reps don\'t count.',
          spoken: 'Slow down, control it',
        );
    }
  }

  static String _deeperTitle(ExerciseType e) => switch (e) {
    ExerciseType.pushUp => 'Go lower',
    ExerciseType.squat || ExerciseType.lunge => 'Go deeper',
    ExerciseType.jumpingJack => 'Open up fully',
    ExerciseType.burpee => 'All the way down',
    ExerciseType.sitUp => 'Sit all the way up',
    ExerciseType.plank => 'Hold the line',
  };

  static String _deeperInstruction(ExerciseType e) => switch (e) {
    ExerciseType.pushUp =>
      'That one was too shallow. Lower your chest until your elbows bend to '
          'about 90°, then push back up.',
    ExerciseType.squat =>
      'That one was too shallow. Sit back until your thighs are about '
          'parallel to the floor.',
    ExerciseType.lunge =>
      'That one was too shallow. Lower until both knees are near 90°.',
    ExerciseType.jumpingJack =>
      'That one did not open fully. Jump the feet wide and clap your hands '
          'overhead.',
    ExerciseType.burpee =>
      'Get all the way down: hands on the floor, body flat, then back up.',
    ExerciseType.sitUp =>
      'Curl all the way up until your torso is upright, then lower slowly.',
    ExerciseType.plank =>
      'Keep your body straight and still so the timer keeps running.',
  };

  static String _deeperSpoken(ExerciseType e) => switch (e) {
    ExerciseType.pushUp => 'Go lower, chest to the floor',
    ExerciseType.squat || ExerciseType.lunge => 'Go deeper',
    ExerciseType.jumpingJack => 'Open up, hands overhead',
    ExerciseType.burpee => 'All the way down',
    ExerciseType.sitUp => 'All the way up',
    ExerciseType.plank => 'Hold the line',
  };

  /// Tip for the post-set summary.
  static String tip(FormStatus status, ExerciseType exercise) {
    final c = cue(status, exercise);
    if (c == null) return status.message;
    return switch (status) {
      FormStatus.hipsTooHigh =>
        'Think "long body": push the floor away and keep hips level with '
            'shoulders. Filming from the side makes this easy to see.',
      FormStatus.hipsTooLow =>
        'Brace before each rep: squeeze glutes, tuck the ribs. If it keeps '
            'happening, do fewer reps with perfect form.',
      FormStatus.torsoLeaning =>
        'Keep your weight in your heels and eyes forward. Hold your arms '
            'out in front for balance.',
      FormStatus.armsNotOverhead =>
        'Count "clap" at the top: hands meet above your head every rep.',
      FormStatus.goDeeper => switch (exercise) {
        ExerciseType.pushUp =>
          'Half reps don\'t count. Aim your chest at the floor and touch '
              'an imaginary line each rep. Elevate your hands on a step if '
              'full depth is too hard for now.',
        ExerciseType.squat =>
          'Use a chair or box as a depth target and sit back to it each rep.',
        _ => c.instruction,
      },
      FormStatus.slowDown =>
        'Try a 2-second lower, a brief pause, then drive up. Quality beats '
            'speed.',
      _ => c.instruction,
    };
  }

  /// Notes for a set, most frequent first.
  static List<CoachingNote> notes(
    Map<FormStatus, int> mistakes,
    ExerciseType exercise,
  ) {
    final entries = mistakes.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        CoachingNote(
          status: e.key,
          count: e.value,
          title: cue(e.key, exercise)?.title ?? e.key.message,
          tip: tip(e.key, exercise),
        ),
    ];
  }
}
