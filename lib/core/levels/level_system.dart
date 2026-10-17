import 'dart:math' as math;

import '../../features/pt/models/pt_record.dart';
import '../../models/exercise.dart';
import '../../models/workout_session.dart';

/// Where the user stands: level, title and progress to the next level.
class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.title,
    required this.totalXp,
    required this.xpIntoLevel,
    required this.xpForLevel,
  });

  final int level;
  final String title;
  final int totalXp;

  /// XP earned since this level started.
  final int xpIntoLevel;

  /// XP needed to finish this level.
  final int xpForLevel;

  double get progress => xpForLevel == 0 ? 1 : xpIntoLevel / xpForLevel;
  int get xpToNext => math.max(0, xpForLevel - xpIntoLevel);

  @override
  bool operator ==(Object other) =>
      other is LevelInfo &&
      other.level == level &&
      other.totalXp == totalXp &&
      other.xpIntoLevel == xpIntoLevel &&
      other.xpForLevel == xpForLevel;

  @override
  int get hashCode => Object.hash(level, totalXp, xpIntoLevel, xpForLevel);
}

/// Experience points and levels. Pure functions of the session history, so
/// nothing extra is stored and the numbers can never drift.
abstract final class LevelSystem {
  /// XP per rep (or per second for timed holds), scaled by effort.
  static int xpPerUnit(ExerciseType type) => switch (type) {
    ExerciseType.pushUp => 10,
    ExerciseType.burpee => 16,
    ExerciseType.lunge => 7,
    ExerciseType.squat => 6,
    ExerciseType.sitUp => 6,
    ExerciseType.jumpingJack => 3,
    ExerciseType.plank => 2,
  };

  /// Bonus for finishing the whole set.
  static const completionBonus = 25;

  static const titles = [
    'Rookie',
    'Starter',
    'Mover',
    'Grinder',
    'Athlete',
    'Pro',
    'Elite',
    'Beast',
    'Titan',
    'Legend',
  ];

  /// XP a session is worth.
  static int xpForSession(WorkoutSession s) {
    if (s.skipped || s.completedReps <= 0) return 0;
    var xp = s.completedReps * xpPerUnit(s.exercise);
    if (s.isCompleted) xp += completionBonus;
    return xp;
  }

  static int totalXp(
    Iterable<WorkoutSession> sessions, {
    Iterable<PtRecord> ptRecords = const [],
  }) =>
      sessions.fold(0, (sum, s) => sum + xpForSession(s)) +
      ptRecords.fold(0, (sum, r) => sum + xpForPtRecord(r));

  /// XP for a guided MY PT session: active minutes, tracked reps and a
  /// bonus for finishing most of the plan. Unverified sessions earn nothing.
  static int xpForPtRecord(PtRecord r) {
    if (!r.verified) return 0;
    var xp = r.duration.inMinutes.clamp(0, 180) * 8 + r.totalReps * 2;
    if (r.completion >= 0.8) xp += 40;
    return xp;
  }

  /// XP needed to get from [level] to the next one. Grows steadily so early
  /// levels come quickly and later ones take real work.
  static int xpToFinishLevel(int level) => 200 + (level - 1) * 150;

  static String titleFor(int level) =>
      titles[math.min(level, titles.length) - 1];

  static LevelInfo levelFor(int totalXp) {
    var level = 1;
    var remaining = math.max(0, totalXp);
    while (remaining >= xpToFinishLevel(level)) {
      remaining -= xpToFinishLevel(level);
      level++;
    }
    return LevelInfo(
      level: level,
      title: titleFor(level),
      totalXp: totalXp,
      xpIntoLevel: remaining,
      xpForLevel: xpToFinishLevel(level),
    );
  }
}
