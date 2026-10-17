/// Muscle groups the planner balances a session across.
enum MuscleGroup {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  core('Core'),
  quads('Quads'),
  hamstrings('Hamstrings'),
  glutes('Glutes'),
  calves('Calves'),
  cardio('Cardio'),
  mobility('Mobility');

  const MuscleGroup(this.label);

  final String label;

  static const push = {chest, shoulders, triceps};
  static const pull = {back, biceps};
  static const legs = {quads, hamstrings, glutes, calves};
  static const upper = {chest, back, shoulders, biceps, triceps};
  static const lower = {quads, hamstrings, glutes, calves, core};
  static const full = {chest, back, shoulders, quads, glutes, core};

  static MuscleGroup? fromName(String? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}
