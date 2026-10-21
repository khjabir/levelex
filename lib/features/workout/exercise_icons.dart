import 'package:flutter/material.dart';

import '../../models/exercise.dart';

/// Icons and 3D guide clips for the exercise catalogue (UI concern, kept
/// out of the model).
extension ExerciseIcon on ExerciseType {
  IconData get icon => switch (this) {
    ExerciseType.pushUp => Icons.fitness_center,
    ExerciseType.squat => Icons.airline_seat_legroom_extra,
    ExerciseType.jumpingJack => Icons.accessibility_new,
    ExerciseType.burpee => Icons.bolt,
    ExerciseType.plank => Icons.horizontal_rule,
    ExerciseType.sitUp => Icons.airline_seat_flat_angled,
    ExerciseType.lunge => Icons.directions_walk,
    ExerciseType.gluteBridge => Icons.airline_seat_flat,
    ExerciseType.wallSit => Icons.event_seat,
    ExerciseType.highKnees => Icons.directions_run,
    ExerciseType.mountainClimber => Icons.terrain,
    ExerciseType.tricepDip => Icons.chair_alt,
    ExerciseType.squatJump => Icons.moving,
  };

  /// Mannequin clip demonstrating the correct movement.
  String get clipId => switch (this) {
    ExerciseType.pushUp => 'push_up',
    ExerciseType.squat => 'squat',
    ExerciseType.jumpingJack => 'jumping_jack',
    ExerciseType.burpee => 'burpee',
    ExerciseType.plank => 'plank',
    ExerciseType.sitUp => 'sit_up',
    ExerciseType.lunge => 'lunge',
    ExerciseType.gluteBridge => 'glute_bridge',
    ExerciseType.wallSit => 'wall_sit',
    ExerciseType.highKnees => 'high_knees',
    ExerciseType.mountainClimber => 'mountain_climbers',
    ExerciseType.tricepDip => 'dip',
    ExerciseType.squatJump => 'squat_jump',
  };
}
