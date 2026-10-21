import 'dart:math' as math;

import '../../features/pt/models/pt_record.dart';
import '../../models/exercise.dart';
import '../../models/workout_session.dart';
import '../levels/level_system.dart';
import '../utils/date_utils.dart';

/// One exercise of a daily challenge and how much of it to do.
class DailyChallengePart {
  const DailyChallengePart({required this.exercise, required this.target});

  final ExerciseType exercise;

  /// Reps, or seconds for timed exercises.
  final int target;

  /// "25 push-ups", "a 40-second plank".
  String describe() => exercise.isTimed
      ? 'a $target-second ${exercise.singular}'
      : '$target ${exercise.countLabel(target)}';

  @override
  bool operator ==(Object other) =>
      other is DailyChallengePart &&
      other.exercise == exercise &&
      other.target == target;

  @override
  int get hashCode => Object.hash(exercise, target);

  @override
  String toString() => 'DailyChallengePart(${exercise.id} × $target)';
}

/// The challenge of one calendar day. Derived from the date and the user's
/// level, so nothing is stored and every device agrees on it.
class DailyChallenge {
  const DailyChallenge({
    required this.day,
    required this.title,
    required this.tagline,
    required this.parts,
  });

  /// Local midnight of the day.
  final DateTime day;
  final String title;
  final String tagline;
  final List<DailyChallengePart> parts;

  /// XP awarded for finishing every part.
  static const bonusXp = 60;

  /// Sum of all part targets (reps and seconds mixed).
  int get totalTarget => parts.fold(0, (sum, p) => sum + p.target);

  @override
  String toString() => 'DailyChallenge($day, "$title", $parts)';
}

/// How far the user is through a [DailyChallenge].
class DailyChallengeProgress {
  const DailyChallengeProgress({required this.challenge, required this.done});

  final DailyChallenge challenge;

  /// Reps (or seconds) done per part, in the same order as
  /// [DailyChallenge.parts].
  final List<int> done;

  bool get completed {
    final parts = challenge.parts;
    for (var i = 0; i < parts.length; i++) {
      if (_doneAt(i) < parts[i].target) return false;
    }
    return true;
  }

  /// `0..1`: mean of every part's capped completion.
  double get fraction {
    final parts = challenge.parts;
    if (parts.isEmpty) return 1;
    var sum = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final target = parts[i].target;
      sum += target <= 0 ? 1 : math.min(1, _doneAt(i) / target);
    }
    return sum / parts.length;
  }

  /// Parts not yet at their target.
  int get remainingParts {
    final parts = challenge.parts;
    var remaining = 0;
    for (var i = 0; i < parts.length; i++) {
      if (_doneAt(i) < parts[i].target) remaining++;
    }
    return remaining;
  }

  int _doneAt(int i) => i < done.length ? done[i] : 0;

  @override
  String toString() => 'DailyChallengeProgress($done of ${challenge.parts})';
}

/// Generates daily challenges and reads their completion from history.
abstract final class DailyChallenges {
  /// Days with two parts; every other weekday has one.
  static const _doubleDays = {
    DateTime.tuesday,
    DateTime.thursday,
    DateTime.saturday,
  };

  /// How many consecutive days of raw picks can at most chain into each
  /// other before the "never repeat yesterday" rule is anchored. The chance
  /// of a chain this long is (2/13)^60, so this is a loop guard only.
  static const _maxLookback = 60;

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const _closers = [
    'any time today.',
    'before the day is out.',
    'whenever suits you today.',
    'you have all day.',
  ];

  /// The challenge for the calendar day of [day] at [level].
  ///
  /// Deterministic: the same date and level always give the same challenge,
  /// and the first exercise never repeats the previous day's first exercise.
  static DailyChallenge forDay(DateTime day, {required int level}) {
    final date = AppDateUtils.dateOnly(day);
    final rng = math.Random(_seed(date));
    rng.nextInt(ExerciseType.values.length); // the raw first pick
    final first = _firstExercise(date);
    final parts = [
      DailyChallengePart(
        exercise: first,
        target: targetFor(first, level: level),
      ),
    ];
    if (_doubleDays.contains(date.weekday)) {
      final second = _secondExercise(rng, first, date.weekday);
      parts.add(
        DailyChallengePart(
          exercise: second,
          target: targetFor(second, level: level),
        ),
      );
    }
    final closer = _closers[rng.nextInt(_closers.length)];
    return DailyChallenge(
      day: date,
      title: _title(parts, date.weekday),
      tagline: _tagline(parts, closer),
      parts: parts,
    );
  }

  /// The target of [exercise] at [level]: the default target grown by 12%
  /// per level, capped at four times the default. Timed targets are whole
  /// multiples of 5 s; rep targets of 20 or more are multiples of 5.
  static int targetFor(ExerciseType exercise, {required int level}) {
    final base = exercise.defaultTarget;
    final factor = 1 + 0.12 * (math.max(1, level) - 1);
    final scaled = math.min((base * factor).round(), base * 4);
    if (exercise.isTimed || scaled >= 20) {
      return math.max(5, (scaled / 5).round() * 5);
    }
    return math.max(1, scaled);
  }

  /// Progress on [challenge] from [sessions]: every non-skipped session of
  /// the part's exercise on the challenge day counts, verified or not, like
  /// the app's daily totals.
  static DailyChallengeProgress progress(
    DailyChallenge challenge,
    Iterable<WorkoutSession> sessions,
  ) {
    final done = List<int>.filled(challenge.parts.length, 0);
    for (final s in sessions) {
      if (s.skipped || !AppDateUtils.isSameDay(s.startTime, challenge.day)) {
        continue;
      }
      for (var i = 0; i < challenge.parts.length; i++) {
        if (challenge.parts[i].exercise == s.exercise) {
          done[i] += s.completedReps;
        }
      }
    }
    return DailyChallengeProgress(challenge: challenge, done: done);
  }

  /// Every day (local midnight) from the first session up to [through] on
  /// which that day's challenge was completed.
  ///
  /// The level a day's challenge is generated at is the level at the start
  /// of that day: XP of the sessions and PT records before it plus the bonus
  /// of the challenge days before it. Empty when there are no sessions.
  static Set<DateTime> completedDays({
    required Iterable<WorkoutSession> sessions,
    required Iterable<PtRecord> ptRecords,
    required DateTime through,
  }) {
    final byDay = <DateTime, List<WorkoutSession>>{};
    DateTime? first;
    for (final s in sessions) {
      final day = AppDateUtils.dateOnly(s.startTime);
      byDay.putIfAbsent(day, () => []).add(s);
      if (first == null || day.isBefore(first)) first = day;
    }
    if (first == null) return {};
    final last = AppDateUtils.dateOnly(through);

    var xpBefore = 0;
    final ptByDay = <DateTime, int>{};
    for (final r in ptRecords) {
      final day = AppDateUtils.dateOnly(r.startTime);
      final xp = LevelSystem.xpForPtRecord(r);
      if (day.isBefore(first)) {
        xpBefore += xp;
      } else {
        ptByDay[day] = (ptByDay[day] ?? 0) + xp;
      }
    }

    final completed = <DateTime>{};
    var day = first;
    while (!day.isAfter(last)) {
      final level = LevelSystem.levelFor(
        xpBefore + completed.length * DailyChallenge.bonusXp,
      ).level;
      final todays = byDay[day] ?? const <WorkoutSession>[];
      if (todays.isNotEmpty &&
          progress(forDay(day, level: level), todays).completed) {
        completed.add(day);
      }
      for (final s in todays) {
        xpBefore += LevelSystem.xpForSession(s);
      }
      xpBefore += ptByDay[day] ?? 0;
      day = AppDateUtils.addDays(day, 1);
    }
    return completed;
  }

  /// Consecutive challenge days ending today or yesterday (today still has
  /// time left).
  static int streak(Set<DateTime> completedDays, DateTime today) {
    var cursor = AppDateUtils.dateOnly(today);
    if (!completedDays.contains(cursor)) {
      cursor = AppDateUtils.addDays(cursor, -1);
    }
    var streak = 0;
    while (completedDays.contains(cursor)) {
      streak++;
      cursor = AppDateUtils.addDays(cursor, -1);
    }
    return streak;
  }

  /// Total XP earned from challenges.
  static int bonusXp(Set<DateTime> completedDays) =>
      completedDays.length * DailyChallenge.bonusXp;

  static int _seed(DateTime day) =>
      day.year * 10000 + day.month * 100 + day.day;

  static ExerciseType _rawFirst(DateTime day) {
    final rng = math.Random(_seed(day));
    return ExerciseType.values[rng.nextInt(ExerciseType.values.length)];
  }

  static ExerciseType _next(ExerciseType e) =>
      ExerciseType.values[(e.index + 1) % ExerciseType.values.length];

  /// The first exercise of [day]: its raw pick, or the next exercise when
  /// the raw pick equals the previous day's first exercise.
  ///
  /// The previous day's first exercise can itself have been shifted, so the
  /// rule is replayed forward from the nearest earlier day whose raw pick
  /// cannot be affected by its own predecessor (it differs from both the
  /// predecessor's raw pick and that pick's successor).
  static ExerciseType _firstExercise(DateTime day) {
    var anchor = day;
    for (var i = 0; i < _maxLookback; i++) {
      final previous = AppDateUtils.addDays(anchor, -1);
      final rawPrevious = _rawFirst(previous);
      final raw = _rawFirst(anchor);
      if (raw != rawPrevious && raw != _next(rawPrevious)) break;
      anchor = previous;
    }
    var actual = _rawFirst(anchor);
    var cursor = anchor;
    while (cursor.isBefore(day)) {
      cursor = AppDateUtils.addDays(cursor, 1);
      final raw = _rawFirst(cursor);
      actual = raw == actual ? _next(raw) : raw;
    }
    return actual;
  }

  /// A second exercise that differs from [first]; on Saturdays it has the
  /// other unit, so the day pairs a rep part with a timed part.
  static ExerciseType _secondExercise(
    math.Random rng,
    ExerciseType first,
    int weekday,
  ) {
    final candidates = [
      for (final e in ExerciseType.values)
        if (e != first &&
            (weekday != DateTime.saturday || e.isTimed != first.isTimed))
          e,
    ];
    return candidates[rng.nextInt(candidates.length)];
  }

  static String _title(List<DailyChallengePart> parts, int weekday) {
    if (parts.length == 1) {
      final name = parts.single.exercise.singular;
      return '${_capitalize(name)} ${_weekdayNames[weekday - 1]}';
    }
    final a = _category(parts[0].exercise);
    final b = _category(parts[1].exercise);
    return a == b ? '$a combo' : '$a & ${b.toLowerCase()}';
  }

  static String _tagline(List<DailyChallengePart> parts, String closer) {
    final what = parts.map((p) => p.describe()).join(' and ');
    return '${_capitalize(what)}, $closer';
  }

  static String _category(ExerciseType e) => switch (e) {
    ExerciseType.pushUp || ExerciseType.tricepDip => 'Upper body',
    ExerciseType.squat ||
    ExerciseType.lunge ||
    ExerciseType.wallSit ||
    ExerciseType.squatJump => 'Legs',
    ExerciseType.gluteBridge => 'Glutes',
    ExerciseType.plank || ExerciseType.sitUp => 'Core',
    ExerciseType.jumpingJack ||
    ExerciseType.highKnees ||
    ExerciseType.mountainClimber => 'Cardio',
    ExerciseType.burpee => 'Full body',
  };

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
