import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/movement_library.dart';
import 'package:levelex/features/strength/logic/exercise_matcher.dart';

void main() {
  group('ExerciseMatcher.match aliases', () {
    const cases = <String, String>{
      // Strong / Hevy style with a trailing qualifier
      'Bench Press (Barbell)': 'bb_bench_press',
      'Squat (Barbell)': 'bb_back_squat',
      'Deadlift (Barbell)': 'bb_deadlift',
      'Overhead Press (Barbell)': 'bb_overhead_press',
      'Shoulder Press (Dumbbell)': 'db_shoulder_press',
      'Bent Over Row (Barbell)': 'db_bent_row',
      'Romanian Deadlift (Barbell)': 'db_rdl',
      'Lat Pulldown (Cable)': 'pull_up',
      'Lunge (Dumbbell)': 'db_lunge',
      'Lunge (Bodyweight)': 'lunge',
      'Squat (Bodyweight)': 'squat',
      'Hip Thrust (Barbell)': 'glute_bridge',
      'Bicep Curl (Dumbbell)': 'db_curl',
      'Hammer Curl (Dumbbell)': 'db_curl',
      'Lateral Raise (Dumbbell)': 'db_lateral_raise',
      'Front Raise (Dumbbell)': 'db_front_raise',
      'Triceps Pushdown (Cable - Straight Bar)': 'cable_pushdown',
      'Triceps Extension (Dumbbell)': 'db_overhead_ext',
      'Skullcrusher (Barbell)': 'db_overhead_ext',
      'Triceps Kickback (Dumbbell)': 'db_kickback',
      'Floor Press (Dumbbell)': 'db_floor_press',
      'Goblet Squat (Kettlebell)': 'goblet_squat',
      'Standing Calf Raise (Machine)': 'calf_raise',
      'Seated Cable Row - V Grip (Cable)': 'band_row',
      'Face Pull (Cable)': 'band_pull_apart',
      'Arnold Press (Dumbbell)': 'db_shoulder_press',
      'Seated Shoulder Press (Dumbbell)': 'db_shoulder_press',
      'Rowing (Machine)': 'rower',
      // FitNotes style
      'Flat Barbell Bench Press': 'bb_bench_press',
      'Barbell Squat': 'bb_back_squat',
      'Deadlift': 'bb_deadlift',
      'Overhead Press': 'bb_overhead_press',
      'Military Press': 'bb_overhead_press',
      'Strict Press': 'bb_overhead_press',
      'Dumbbell Shoulder Press': 'db_shoulder_press',
      'Seated Dumbbell Press': 'db_shoulder_press',
      'Barbell Row': 'db_bent_row',
      'Dumbbell Row': 'db_bent_row',
      'One Arm Row': 'db_bent_row',
      'Pendlay Row': 'db_bent_row',
      'RDL': 'db_rdl',
      'Stiff Leg Deadlift': 'db_rdl',
      'Walking Lunge': 'db_lunge',
      'Reverse Lunge': 'db_lunge',
      'Lunge': 'lunge',
      'Lunges': 'lunge',
      'Barbell Curl': 'db_curl',
      'Side Raise': 'db_lateral_raise',
      'Cable Pushdown': 'cable_pushdown',
      'Rope Pushdown': 'cable_pushdown',
      'Overhead Tricep Extension': 'db_overhead_ext',
      'Kickback': 'db_kickback',
      'Pull Up': 'pull_up',
      'Chin Up': 'pull_up',
      'Pull-ups': 'pull_up',
      'Push Up': 'push_up',
      'Push-ups': 'push_up',
      'Press Up': 'push_up',
      'Pike Push Up': 'pike_push_up',
      'Pike Pushup': 'pike_push_up',
      'Plank': 'plank',
      'Side Plank': 'side_plank',
      'Sit Up': 'sit_up',
      'Crunch': 'sit_up',
      'Crunches': 'sit_up',
      'Hanging Knee Raise': 'hanging_knee_raise',
      'Hanging Leg Raises': 'hanging_knee_raise',
      'Kettlebell Swing': 'kb_swing',
      'KB Swing': 'kb_swing',
      'Glute Bridge': 'glute_bridge',
      'Hip Thrust': 'glute_bridge',
      'Calf Raise': 'calf_raise',
      'Dip': 'tricep_dip',
      'Tricep Dip': 'tricep_dip',
      'Bench Dip': 'tricep_dip',
      'Burpee': 'burpee',
      'Burpees': 'burpee',
      'Jumping Jack': 'jumping_jack',
      'Mountain Climber': 'mountain_climbers',
      'Mountain Climbers': 'mountain_climbers',
      'High Knees': 'high_knees',
      'Wall Sit': 'wall_sit',
      'Superman': 'superman',
      'Bird Dog': 'bird_dog',
      'Band Pull Apart': 'band_pull_apart',
      'Face Pull': 'band_pull_apart',
      'Band Row': 'band_row',
      'Seated Cable Row': 'band_row',
      'Cable Row': 'band_row',
      'Air Squat': 'squat',
      'Bodyweight Squat': 'squat',
      'Body Weight Squat': 'squat',
      'Jump Squat': 'squat_jump',
      'Treadmill': 'treadmill',
      'Running': 'treadmill',
      'Run': 'treadmill',
      'Cycling': 'bike',
      'Bike': 'bike',
      'Stationary Bike': 'bike',
      'Rowing': 'rower',
      'Rowing Machine': 'rower',
      'Jump Rope': 'jump_rope',
      'Skipping': 'jump_rope',
      'OHP': 'bb_overhead_press',
      'DB Curl': 'db_curl',
      'BB Bench Press': 'bb_bench_press',
    };

    for (final e in cases.entries) {
      test('${e.key} → ${e.value}', () {
        expect(ExerciseMatcher.match(e.key), e.value);
      });
    }
  });

  group('ExerciseMatcher.match similarity fallback', () {
    test('close variants land on the nearest library movement', () {
      expect(
        ExerciseMatcher.match('Incline Bench Press (Barbell)'),
        'bb_bench_press',
      );
      expect(ExerciseMatcher.match('Treadmill Walk'), 'treadmill');
      expect(ExerciseMatcher.match('Single Leg Glute Bridge'), 'glute_bridge');
      expect(ExerciseMatcher.match('Sumo Deadlift (Barbell)'), 'bb_deadlift');
    });

    test('equipment-only variants fold into the library movement', () {
      expect(ExerciseMatcher.match('Dumbbell Bench Press'), 'bb_bench_press');
      expect(ExerciseMatcher.match('Cable Lateral Raise'), 'db_lateral_raise');
    });

    test('unrelated or blocked names return null', () {
      expect(ExerciseMatcher.match('Leg Curl'), isNull);
      expect(ExerciseMatcher.match('Lying Leg Curl (Machine)'), isNull);
      expect(ExerciseMatcher.match('Leg Press'), isNull);
      expect(ExerciseMatcher.match('Cable Woodchop'), isNull);
      expect(ExerciseMatcher.match('Chest Fly (Dumbbell)'), isNull);
      expect(ExerciseMatcher.match('Barbell'), isNull);
      expect(ExerciseMatcher.match(''), isNull);
      expect(ExerciseMatcher.match('   '), isNull);
    });

    test('every library name resolves, main-phase ones to themselves', () {
      for (final m in MovementLibrary.all) {
        final hit = ExerciseMatcher.match(m.name);
        expect(hit, isNotNull, reason: m.name);
        if (m.phases.contains(PlanPhase.main)) {
          expect(hit, m.id, reason: m.name);
        }
      }
    });
  });

  group('ExerciseMatcher.tokens', () {
    test('moves a trailing qualifier to the front and singularises', () {
      expect(ExerciseMatcher.tokens('Bench Press (Barbell)'), [
        'barbell',
        'bench',
        'press',
      ]);
      expect(ExerciseMatcher.tokens('Hanging Leg Raises'), [
        'hanging',
        'leg',
        'raise',
      ]);
      expect(ExerciseMatcher.tokens('Side plank (each side)'), [
        'side',
        'plank',
      ]);
      expect(ExerciseMatcher.tokens('Curls with the EZ-bar'), [
        'curl',
        'ez',
        'bar',
      ]);
    });
  });

  group('ExerciseMatcher.customId / resolve', () {
    test('builds a slug of a-z, 0-9 and single dashes', () {
      expect(
        ExerciseMatcher.customId('Bench Press (Dumbbell)'),
        'custom:bench-press-dumbbell',
      );
      expect(
        ExerciseMatcher.customId('  Cable  Woodchop!! '),
        'custom:cable-woodchop',
      );
      expect(
        ExerciseMatcher.customId('Zercher Squat 2.0'),
        'custom:zercher-squat-2-0',
      );
      expect(ExerciseMatcher.customId('***'), 'custom:exercise');
    });

    test('resolve prefers a library id and falls back to a custom id', () {
      expect(ExerciseMatcher.resolve('Push Up'), 'push_up');
      expect(
        ExerciseMatcher.resolve('Cable Woodchop'),
        'custom:cable-woodchop',
      );
    });
  });
}
