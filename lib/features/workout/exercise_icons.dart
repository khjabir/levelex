import 'package:flutter/material.dart';

import '../../models/exercise.dart';

/// Icons for the exercise catalogue (UI concern, kept out of the model).
extension ExerciseIcon on ExerciseType {
  IconData get icon => switch (this) {
    ExerciseType.pushUp => Icons.fitness_center,
    ExerciseType.squat => Icons.airline_seat_legroom_extra,
    ExerciseType.jumpingJack => Icons.accessibility_new,
    ExerciseType.burpee => Icons.bolt,
    ExerciseType.plank => Icons.horizontal_rule,
    ExerciseType.sitUp => Icons.airline_seat_flat_angled,
    ExerciseType.lunge => Icons.directions_walk,
  };
}
