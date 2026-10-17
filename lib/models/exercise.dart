/// How an exercise is measured.
enum ExerciseUnit { reps, seconds }

/// The exercises the app can track. Each one has its own analyzer; the
/// workout screen, history and reminders are shared.
enum ExerciseType {
  pushUp(
    id: 'pushup',
    label: 'Push-ups',
    singular: 'push-up',
    unit: ExerciseUnit.reps,
    defaultTarget: 10,
    tagline: 'Chest, arms and core.',
    placement:
        'Prop the phone 2–3 m away, at the side or in front and slightly '
        'above the floor. Keep your whole body in frame.',
    cues: [
      'Start in a plank with your hands under your shoulders.',
      'Lower until your elbows bend well past 90°, then push back up.',
      'Keep your body in one straight line.',
    ],
  ),
  squat(
    id: 'squat',
    label: 'Squats',
    singular: 'squat',
    unit: ExerciseUnit.reps,
    defaultTarget: 15,
    tagline: 'Legs and glutes.',
    placement:
        'Prop the phone 2–3 m away, from the side or the front, with your '
        'whole body from head to feet visible.',
    cues: [
      'Stand with feet shoulder-width apart.',
      'Sit back until your thighs are about parallel to the floor.',
      'Drive back up through your heels.',
    ],
  ),
  jumpingJack(
    id: 'jumping_jack',
    label: 'Jumping jacks',
    singular: 'jumping jack',
    unit: ExerciseUnit.reps,
    defaultTarget: 20,
    tagline: 'Full-body cardio.',
    placement:
        'Face the camera from 2–3 m away with room to spread your arms and '
        'legs; keep your hands in frame when they are overhead.',
    cues: [
      'Start with feet together and arms by your sides.',
      'Jump your feet apart while raising your arms overhead.',
      'Jump back to the start. That is one rep.',
    ],
  ),
  burpee(
    id: 'burpee',
    label: 'Burpees',
    singular: 'burpee',
    unit: ExerciseUnit.reps,
    defaultTarget: 8,
    tagline: 'Everything at once.',
    placement:
        'Prop the phone 3 m away from the side so both standing and the '
        'floor position fit in the frame.',
    cues: [
      'From standing, drop into a plank with your hands on the floor.',
      'Return to standing (add the jump if you like).',
      'A rep counts each time you come back up.',
    ],
  ),
  plank(
    id: 'plank',
    label: 'Plank',
    singular: 'plank',
    unit: ExerciseUnit.seconds,
    defaultTarget: 30,
    tagline: 'Core hold.',
    placement:
        'Prop the phone 2–3 m away at the side, low to the floor, with your '
        'whole body in frame.',
    cues: [
      'Rest on your hands or forearms with your body in a straight line.',
      'The timer only runs while you hold the position.',
      'Keep your hips level: not sagging, not piked.',
    ],
  ),
  sitUp(
    id: 'situp',
    label: 'Sit-ups',
    singular: 'sit-up',
    unit: ExerciseUnit.reps,
    defaultTarget: 15,
    tagline: 'Abs.',
    placement:
        'Prop the phone 2–3 m away at the side, low to the floor, so your '
        'torso and knees are visible.',
    cues: [
      'Lie on your back with knees bent and feet on the floor.',
      'Curl up until your torso is upright, then lower back down.',
      'Keep your feet planted.',
    ],
  ),
  lunge(
    id: 'lunge',
    label: 'Lunges',
    singular: 'lunge',
    unit: ExerciseUnit.reps,
    defaultTarget: 10,
    tagline: 'Legs, one at a time.',
    placement:
        'Prop the phone 2–3 m away from the side with your whole body in '
        'frame; alternate legs as you like.',
    cues: [
      'Step forward and lower until both knees are near 90°.',
      'Push back up to standing. Each descent is one rep.',
      'Keep your torso upright.',
    ],
  );

  const ExerciseType({
    required this.id,
    required this.label,
    required this.singular,
    required this.unit,
    required this.defaultTarget,
    required this.tagline,
    required this.placement,
    required this.cues,
  });

  /// Spoken/shown when the body is visible but not in the start posture.
  String get positionHint => switch (this) {
    ExerciseType.pushUp || ExerciseType.plank =>
      'Get into push-up position: hands on the floor, body '
          'straight',
    ExerciseType.squat ||
    ExerciseType.lunge ||
    ExerciseType.jumpingJack ||
    ExerciseType.burpee => 'Stand up straight with your whole body in frame',
    ExerciseType.sitUp => 'Lie on your back with your knees bent',
  };

  /// Call-to-action for the home screen.
  String get startLabel => isTimed
      ? 'START ${label.toUpperCase()}'
      : 'START ${singular.toUpperCase()} SET';

  /// Stable identifier used in storage.
  final String id;
  final String label;
  final String singular;
  final ExerciseUnit unit;
  final int defaultTarget;
  final String tagline;

  /// Where to put the phone.
  final String placement;

  /// Short how-to shown before the camera opens.
  final List<String> cues;

  bool get isTimed => unit == ExerciseUnit.seconds;

  /// "10 push-ups", "30 seconds of plank".
  String describeTarget(int target) => isTimed
      ? '$target seconds of $singular'
      : '$target ${target == 1 ? singular : label.toLowerCase()}';

  /// "push-up" / "push-ups" for counts, "second"/"seconds" when timed.
  String countLabel(int count) {
    if (isTimed) return count == 1 ? 'second' : 'seconds';
    return count == 1 ? singular : label.toLowerCase();
  }

  static ExerciseType fromId(String? id) => ExerciseType.values.firstWhere(
    (e) => e.id == id,
    orElse: () => ExerciseType.pushUp,
  );
}
