import '../../features/challenge/models/challenge.dart';
import '../../features/pt/models/pt_record.dart';
import '../../features/strength/logic/records.dart';
import '../../features/strength/models/lift_log.dart';
import '../../models/exercise.dart';
import '../../models/workout_session.dart';
import '../levels/level_system.dart';
import '../utils/date_utils.dart';
import '../utils/stats_calculator.dart';
import 'daily_challenge.dart';

/// How hard a badge is to earn.
enum AchievementTier {
  bronze('Bronze'),
  silver('Silver'),
  gold('Gold');

  const AchievementTier(this.label);

  final String label;
}

/// The part of the app a badge rewards.
enum AchievementCategory {
  consistency('Consistency'),
  volume('Volume'),
  strength('Strength'),
  coaching('Coaching'),
  pt('My PT'),
  challenge('Challenges'),
  body('Body'),
  daily('Daily challenge');

  const AchievementCategory(this.label);

  final String label;
}

/// A badge the user can earn. Plain data with no Flutter types, so the
/// engine runs in plain Dart tests: [icon] is a key from
/// [Achievements.iconKeys] that the UI maps to an icon.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    required this.tier,
    required this.target,
  });

  /// Stable identifier, used to remember which badges were already shown.
  final String id;
  final String title;
  final String description;

  /// Icon key, one of [Achievements.iconKeys].
  final String icon;
  final AchievementCategory category;
  final AchievementTier tier;

  /// The count, streak length, level or kilograms that earns the badge.
  final int target;

  @override
  String toString() => 'Achievement($id)';
}

/// Where the user stands on one badge.
class AchievementStatus {
  const AchievementStatus({
    required this.achievement,
    required this.current,
    this.earnedAt,
  });

  final Achievement achievement;

  /// Progress in the badge's own unit (reps, days, sessions, kg, level).
  /// May exceed the target once earned.
  final int current;

  /// When the badge was earned: never null when [earned], never later than
  /// the evaluation time, null while locked.
  final DateTime? earnedAt;

  bool get earned => current >= achievement.target;

  /// Fraction of the target reached, `0..1`.
  double get progress {
    if (achievement.target <= 0) return 1;
    final ratio = current / achievement.target;
    return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
  }

  @override
  String toString() =>
      'AchievementStatus(${achievement.id}, $current/${achievement.target}'
      '${earnedAt == null ? '' : ', earned $earnedAt'})';
}

/// Everything the engine reads. Pure data in, so the same history always
/// yields the same badges and nothing extra has to be stored.
class AchievementInput {
  const AchievementInput({
    required this.now,
    this.sessions = const [],
    this.ptRecords = const [],
    this.lifts = const [],
    this.bodyWeights = const [],
    this.challenges = const [],
    this.dailyChallengeDays = const {},
    this.weeklyGoal = 3,
    this.restWeekdays = const {},
  });

  final Iterable<WorkoutSession> sessions;
  final Iterable<PtRecord> ptRecords;
  final Iterable<LiftEntry> lifts;
  final Iterable<BodyWeightEntry> bodyWeights;
  final Iterable<ChallengeRecord> challenges;

  /// Local-midnight days on which the daily challenge was completed.
  final Set<DateTime> dailyChallengeDays;

  /// Active days per week the user aims for (`weeks_4`). Values below 1
  /// are treated as 1.
  final int weeklyGoal;

  /// Planned rest days (`DateTime.monday`..`DateTime.sunday`). Carried for
  /// parity with the streak settings; no badge currently depends on it.
  final Set<int> restWeekdays;

  /// The evaluation time. No badge is ever dated after it.
  final DateTime now;
}

/// The badge catalogue and the pure functions that evaluate it.
abstract final class Achievements {
  /// Icon keys an [Achievement.icon] may use; the UI maps them to icons.
  static const Set<String> iconKeys = {
    'flame',
    'bolt',
    'trophy',
    'medal',
    'sunrise',
    'moon',
    'star',
    'heart',
    'timer',
    'dumbbell',
    'target',
    'camera',
    'calendar',
    'crown',
    'scale',
    'group',
    'sparkle',
  };

  /// Every badge, in catalogue (display) order.
  static const List<Achievement> all = [
    // Consistency.
    Achievement(
      id: 'first_set',
      title: 'First Set',
      description: 'Complete your first verified set.',
      icon: 'star',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'streak_3',
      title: 'On a Roll',
      description: 'Train three days in a row.',
      icon: 'flame',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 3,
    ),
    Achievement(
      id: 'streak_7',
      title: 'Week Warrior',
      description: 'Train seven days in a row.',
      icon: 'flame',
      category: AchievementCategory.consistency,
      tier: AchievementTier.silver,
      target: 7,
    ),
    Achievement(
      id: 'streak_30',
      title: 'Monthly Machine',
      description: 'Train 30 days in a row.',
      icon: 'flame',
      category: AchievementCategory.consistency,
      tier: AchievementTier.gold,
      target: 30,
    ),
    Achievement(
      id: 'streak_100',
      title: 'Centurion',
      description: 'Train 100 days in a row.',
      icon: 'crown',
      category: AchievementCategory.consistency,
      tier: AchievementTier.gold,
      target: 100,
    ),
    Achievement(
      id: 'weeks_4',
      title: 'Goal Getter',
      description: 'Hit your weekly goal four weeks running.',
      icon: 'calendar',
      category: AchievementCategory.consistency,
      tier: AchievementTier.silver,
      target: 4,
    ),
    Achievement(
      id: 'early_bird',
      title: 'Early Bird',
      description: 'Complete a set before 7 am.',
      icon: 'sunrise',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'night_owl',
      title: 'Night Owl',
      description: 'Complete a set after 10 pm.',
      icon: 'moon',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    // Volume.
    Achievement(
      id: 'reps_100',
      title: 'Century',
      description: 'Log 100 reps in total.',
      icon: 'bolt',
      category: AchievementCategory.volume,
      tier: AchievementTier.bronze,
      target: 100,
    ),
    Achievement(
      id: 'reps_1000',
      title: 'Thousand Club',
      description: 'Log 1,000 reps in total.',
      icon: 'bolt',
      category: AchievementCategory.volume,
      tier: AchievementTier.silver,
      target: 1000,
    ),
    Achievement(
      id: 'reps_10000',
      title: 'Ten Thousand',
      description: 'Log 10,000 reps in total.',
      icon: 'bolt',
      category: AchievementCategory.volume,
      tier: AchievementTier.gold,
      target: 10000,
    ),
    Achievement(
      id: 'day_50',
      title: 'Fifty a Day',
      description: 'Do 50 reps in a single day.',
      icon: 'target',
      category: AchievementCategory.volume,
      tier: AchievementTier.bronze,
      target: 50,
    ),
    Achievement(
      id: 'day_100',
      title: 'Hundred a Day',
      description: 'Do 100 reps in a single day.',
      icon: 'target',
      category: AchievementCategory.volume,
      tier: AchievementTier.silver,
      target: 100,
    ),
    Achievement(
      id: 'marathon',
      title: 'Marathon',
      description: 'Train for 60 minutes in one day.',
      icon: 'timer',
      category: AchievementCategory.volume,
      tier: AchievementTier.silver,
      target: 60,
    ),
    Achievement(
      id: 'level_5',
      title: 'Athlete',
      description: 'Reach level 5.',
      icon: 'medal',
      category: AchievementCategory.volume,
      tier: AchievementTier.silver,
      target: 5,
    ),
    Achievement(
      id: 'level_10',
      title: 'Legend',
      description: 'Reach level 10.',
      icon: 'crown',
      category: AchievementCategory.volume,
      tier: AchievementTier.gold,
      target: 10,
    ),
    // Coaching.
    Achievement(
      id: 'all_rounder',
      title: 'All-Rounder',
      description: 'Complete a set of every exercise.',
      icon: 'medal',
      category: AchievementCategory.coaching,
      tier: AchievementTier.gold,
      // ExerciseType.values.length: a list length is not a constant
      // expression, so the number is spelled out and checked by an assert
      // in [evaluate] and by the tests.
      target: 13,
    ),
    Achievement(
      id: 'form_master',
      title: 'Form Master',
      description: 'Finish a set of 10 or more reps with 90% good form.',
      icon: 'sparkle',
      category: AchievementCategory.coaching,
      tier: AchievementTier.silver,
      target: 1,
    ),
    // My PT.
    Achievement(
      id: 'pt_1',
      title: 'PT Rookie',
      description: 'Finish your first MY PT session.',
      icon: 'heart',
      category: AchievementCategory.pt,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'pt_10',
      title: 'PT Regular',
      description: 'Finish 10 MY PT sessions.',
      icon: 'heart',
      category: AchievementCategory.pt,
      tier: AchievementTier.silver,
      target: 10,
    ),
    Achievement(
      id: 'pt_50',
      title: 'PT Devotee',
      description: 'Finish 50 MY PT sessions.',
      icon: 'heart',
      category: AchievementCategory.pt,
      tier: AchievementTier.gold,
      target: 50,
    ),
    // Strength.
    Achievement(
      id: 'pr_1',
      title: 'First PR',
      description: 'Set your first personal record.',
      icon: 'trophy',
      category: AchievementCategory.strength,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'pr_10',
      title: 'Record Breaker',
      description: 'Set 10 personal records.',
      icon: 'trophy',
      category: AchievementCategory.strength,
      tier: AchievementTier.silver,
      target: 10,
    ),
    Achievement(
      id: 'heavy_100',
      title: 'Hundred Club',
      description: 'Lift 100 kg in a work set.',
      icon: 'dumbbell',
      category: AchievementCategory.strength,
      tier: AchievementTier.gold,
      target: 100,
    ),
    // Challenges.
    Achievement(
      id: 'challenge_1',
      title: 'Game On',
      description: 'Play your first challenge.',
      icon: 'group',
      category: AchievementCategory.challenge,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'challenge_5',
      title: 'Rivalry',
      description: 'Play five challenges.',
      icon: 'group',
      category: AchievementCategory.challenge,
      tier: AchievementTier.silver,
      target: 5,
    ),
    // Daily challenge.
    Achievement(
      id: 'daily_1',
      title: 'Daily Starter',
      description: 'Complete a daily challenge.',
      icon: 'calendar',
      category: AchievementCategory.daily,
      tier: AchievementTier.bronze,
      target: 1,
    ),
    Achievement(
      id: 'daily_7',
      title: 'Daily Habit',
      description: 'Complete seven daily challenges.',
      icon: 'calendar',
      category: AchievementCategory.daily,
      tier: AchievementTier.silver,
      target: 7,
    ),
    Achievement(
      id: 'daily_30',
      title: 'Daily Devotion',
      description: 'Complete 30 daily challenges.',
      icon: 'calendar',
      category: AchievementCategory.daily,
      tier: AchievementTier.gold,
      target: 30,
    ),
    // Body.
    Achievement(
      id: 'weigh_7',
      title: 'Weigh-in Week',
      description: 'Log your weight on seven days.',
      icon: 'scale',
      category: AchievementCategory.body,
      tier: AchievementTier.bronze,
      target: 7,
    ),
  ];

  static Achievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// One status per badge in [all]: earned badges first, newest first (ties
  /// in catalogue order), then locked badges by progress, highest first
  /// (ties in catalogue order).
  static List<AchievementStatus> evaluate(AchievementInput input) {
    assert(
      byId('all_rounder')!.target == ExerciseType.values.length,
      'all_rounder.target must equal ExerciseType.values.length',
    );
    final now = input.now;
    final results = _Evaluator(input).run();
    final statuses = [
      for (final a in all)
        _finish(a, results[a.id] ?? const _Result(0, null), now),
    ];
    // Sort indices so catalogue order is an explicit tiebreaker (List.sort
    // is not stable).
    final order = List<int>.generate(statuses.length, (i) => i)
      ..sort((x, y) {
        final a = statuses[x];
        final b = statuses[y];
        if (a.earned != b.earned) return a.earned ? -1 : 1;
        if (a.earned) {
          final byTime = b.earnedAt!.compareTo(a.earnedAt!);
          if (byTime != 0) return byTime;
        } else {
          final byProgress = b.progress.compareTo(a.progress);
          if (byProgress != 0) return byProgress;
        }
        return x.compareTo(y);
      });
    return [for (final i in order) statuses[i]];
  }

  /// The earned badges in [statuses] whose ids are not in [seenIds], in the
  /// order given. Store the ids you have shown and pass them back here to
  /// find what to celebrate next.
  static List<AchievementStatus> newlyEarned(
    List<AchievementStatus> statuses,
    Set<String> seenIds,
  ) => [
    for (final s in statuses)
      if (s.earned && !seenIds.contains(s.achievement.id)) s,
  ];

  static AchievementStatus _finish(Achievement a, _Result r, DateTime now) {
    final earned = r.current >= a.target;
    var at = earned ? (r.earnedAt ?? now) : null;
    if (at != null && at.isAfter(now)) at = now;
    return AchievementStatus(achievement: a, current: r.current, earnedAt: at);
  }
}

/// A badge's raw numbers before clamping against the evaluation time.
class _Result {
  const _Result(this.current, this.earnedAt);

  final int current;
  final DateTime? earnedAt;
}

/// Something that happened at [at] and counts [amount] towards a badge.
class _Event {
  const _Event(this.at, this.amount);

  final DateTime at;
  final int amount;
}

/// Events replayed in time order: a lifetime total and the moment the
/// running total first reached a target.
class _Tally {
  _Tally(Iterable<_Event> events)
    : _events = [
        for (final e in events)
          if (e.amount > 0) e,
      ]..sort((a, b) => a.at.compareTo(b.at));

  final List<_Event> _events;

  int get total => _events.fold(0, (sum, e) => sum + e.amount);

  DateTime? reachedAt(int target) {
    var sum = 0;
    for (final e in _events) {
      sum += e.amount;
      if (sum >= target) return e.at;
    }
    return null;
  }

  _Result result(int target) => _Result(total, reachedAt(target));
}

/// An [_Event] that belongs to the calendar day [day] (local midnight).
class _DayEvent {
  const _DayEvent(this.day, this.at, this.amount);

  final DateTime day;
  final DateTime at;
  final int amount;
}

/// Events summed per calendar day: the best single day and the moment a
/// day's running total first reached a target.
class _DayTotals {
  _DayTotals(Iterable<_DayEvent> events) {
    for (final e in events) {
      if (e.amount > 0) _byDay.putIfAbsent(e.day, () => []).add(e);
    }
    _days = _byDay.keys.toList()..sort();
    for (final list in _byDay.values) {
      list.sort((a, b) => a.at.compareTo(b.at));
    }
  }

  final _byDay = <DateTime, List<_DayEvent>>{};
  late final List<DateTime> _days;

  int get best {
    var best = 0;
    for (final list in _byDay.values) {
      final sum = list.fold(0, (s, e) => s + e.amount);
      if (sum > best) best = sum;
    }
    return best;
  }

  DateTime? reachedAt(int target) {
    for (final day in _days) {
      var sum = 0;
      for (final e in _byDay[day]!) {
        sum += e.amount;
        if (sum >= target) return e.at;
      }
    }
    return null;
  }

  _Result result(int target) => _Result(best, reachedAt(target));
}

/// Runs the catalogue against one [AchievementInput].
class _Evaluator {
  _Evaluator(this.input)
    : sessions = input.sessions.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime)),
      ptRecords = input.ptRecords.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime)),
      lifts = input.lifts.toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final AchievementInput input;
  final List<WorkoutSession> sessions;
  final List<PtRecord> ptRecords;
  final List<LiftEntry> lifts;

  static int _target(String id) => Achievements.byId(id)!.target;

  /// When a set counts as done: its end, or its start for an open one.
  static DateTime _finished(WorkoutSession s) => s.endTime ?? s.startTime;

  Map<String, _Result> run() {
    final out = <String, _Result>{};
    final done = [
      for (final s in sessions)
        if (s.verified && s.isCompleted) s,
    ];

    // first_set, early_bird, night_owl, form_master: one qualifying set.
    out['first_set'] = _Tally([for (final s in done) _Event(_finished(s), 1)])
        .result(_target('first_set'));
    out['early_bird'] = _Tally([
      for (final s in done)
        if (s.startTime.hour < 7) _Event(_finished(s), 1),
    ]).result(_target('early_bird'));
    out['night_owl'] = _Tally([
      for (final s in done)
        if (s.startTime.hour >= 22) _Event(_finished(s), 1),
    ]).result(_target('night_owl'));
    out['form_master'] = _Tally([
      for (final s in done)
        if ((s.formScore ?? 0) >= 0.9 && s.completedReps >= 10)
          _Event(_finished(s), 1),
    ]).result(_target('form_master'));

    // Streaks and weekly goals share the completed-day set.
    final activeDays = StatsCalculator.completedDays(
      sessions,
      ptRecords: ptRecords,
    );
    // Rest days bridge a streak here exactly as on the home screen, so a
    // Mon-Fri trainer with weekend rest days can reach the 7-day badge.
    final longest = StatsCalculator.longestStreak(
      sessions,
      ptRecords: ptRecords,
      restWeekdays: input.restWeekdays,
    );
    for (final id in const [
      'streak_3',
      'streak_7',
      'streak_30',
      'streak_100',
    ]) {
      out[id] = _Result(
        longest,
        _streakReachedAt(activeDays, _target(id), input.restWeekdays),
      );
    }
    out['weeks_4'] = _weeks(
      activeDays,
      input.weeklyGoal < 1 ? 1 : input.weeklyGoal,
      _target('weeks_4'),
      input.now,
    );

    // Lifetime reps: counted sets plus MY PT reps, like the stats screen.
    final reps = _Tally([
      for (final s in sessions)
        if (!s.skipped && !s.exercise.isTimed)
          _Event(_finished(s), s.completedReps),
      for (final r in ptRecords) _Event(r.endTime, r.totalReps),
    ]);
    for (final id in const ['reps_100', 'reps_1000', 'reps_10000']) {
      out[id] = reps.result(_target(id));
    }

    // Most reps of the reminder-style exercises in one day.
    final dayReps = _DayTotals([
      for (final s in sessions)
        if (!s.skipped && !s.exercise.isTimed)
          _DayEvent(
            AppDateUtils.dateOnly(s.startTime),
            _finished(s),
            s.completedReps,
          ),
    ]);
    for (final id in const ['day_50', 'day_100']) {
      out[id] = dayReps.result(_target(id));
    }

    // Active minutes in one day, summed in seconds so short sets add up.
    final active = <_DayEvent>[];
    for (final s in sessions) {
      final end = s.endTime;
      if (s.skipped || end == null) continue;
      active.add(
        _DayEvent(
          AppDateUtils.dateOnly(s.startTime),
          end,
          end.difference(s.startTime).inSeconds,
        ),
      );
    }
    for (final r in ptRecords) {
      active.add(
        _DayEvent(
          AppDateUtils.dateOnly(r.startTime),
          r.endTime,
          r.duration.inSeconds,
        ),
      );
    }
    final marathon = _DayTotals(active).result(_target('marathon') * 60);
    out['marathon'] = _Result(marathon.current ~/ 60, marathon.earnedAt);

    // Levels: replay XP in time order to date the level-up.
    // The daily-challenge bonus counts, as it does for the level shown on
    // the home screen; leaving it out kept "Reach level 5" locked at level 5.
    final challengeDays = {
      for (final d in input.dailyChallengeDays) AppDateUtils.dateOnly(d),
    };
    final xp = _Tally([
      for (final s in sessions)
        _Event(_finished(s), LevelSystem.xpForSession(s)),
      for (final r in ptRecords)
        _Event(r.endTime, LevelSystem.xpForPtRecord(r)),
      for (final d in challengeDays)
        _Event(
          AppDateUtils.addDays(d, 1).subtract(const Duration(seconds: 1)),
          DailyChallenges.bonusXp({d}),
        ),
    ]);
    final totalXp =
        LevelSystem.totalXp(sessions, ptRecords: ptRecords) +
        DailyChallenges.bonusXp(challengeDays);
    // Level 1 is the floor, so no XP shows as no progress.
    final level = totalXp > 0 ? LevelSystem.levelFor(totalXp).level : 0;
    for (final id in const ['level_5', 'level_10']) {
      out[id] = _Result(level, xp.reachedAt(_xpToReachLevel(_target(id))));
    }

    // Every exercise at least once.
    final seen = <ExerciseType>{};
    DateTime? allRounderAt;
    final allRounderTarget = _target('all_rounder');
    for (final s in done) {
      if (seen.add(s.exercise) &&
          allRounderAt == null &&
          seen.length >= allRounderTarget) {
        allRounderAt = _finished(s);
      }
    }
    out['all_rounder'] = _Result(seen.length, allRounderAt);

    // MY PT sessions.
    final pt = _Tally([
      for (final r in ptRecords)
        if (r.isCompleted) _Event(r.endTime, 1),
    ]);
    for (final id in const ['pt_1', 'pt_10', 'pt_50']) {
      out[id] = pt.result(_target(id));
    }

    // Personal records and the heaviest work set.
    final prs = _Tally([
      // Only records that beat something: a lift's first log is its
      // baseline, and counting those earned "Record Breaker" on day one.
      for (final r in RecordBook.recent(lifts, limit: 1000))
        if (r.previous != null) _Event(r.date, 1),
    ]);
    for (final id in const ['pr_1', 'pr_10']) {
      out[id] = prs.result(_target(id));
    }
    var top = 0.0;
    DateTime? heavyAt;
    final heavyTarget = _target('heavy_100');
    for (final e in lifts) {
      final w = e.topWeight;
      if (w > top) top = w;
      if (heavyAt == null && w >= heavyTarget) heavyAt = e.startTime;
    }
    out['heavy_100'] = _Result(top.floor(), heavyAt);

    // Challenges played.
    final challenges = _Tally([
      for (final c in input.challenges) _Event(c.date, 1),
    ]);
    for (final id in const ['challenge_1', 'challenge_5']) {
      out[id] = challenges.result(_target(id));
    }

    // Daily challenges, one per day.
    final daily = _Tally([
      for (final d in {
        for (final d in input.dailyChallengeDays) AppDateUtils.dateOnly(d),
      })
        _Event(d, 1),
    ]);
    for (final id in const ['daily_1', 'daily_7', 'daily_30']) {
      out[id] = daily.result(_target(id));
    }

    // Weigh-ins, one per day.
    out['weigh_7'] = _Tally([
      for (final d in {
        for (final w in input.bodyWeights) AppDateUtils.dateOnly(w.date),
      })
        _Event(d, 1),
    ]).result(_target('weigh_7'));

    return out;
  }

  /// The first day on which a run of consecutive active days reached
  /// [target], or null.
  static DateTime? _streakReachedAt(
    Set<DateTime> days,
    int target, [
    Set<int> restWeekdays = const {},
  ]) {
    final sorted = days.toList()..sort();
    var run = 0;
    DateTime? previous;
    for (final day in sorted) {
      run = previous != null && _bridged(previous, day, restWeekdays)
          ? run + 1
          : 1;
      if (run >= target) return day;
      previous = day;
    }
    return null;
  }

  /// Whether [to] continues a run from [from]: the next day, or only rest
  /// weekdays in between.
  static bool _bridged(DateTime from, DateTime to, Set<int> restWeekdays) {
    final gap = AppDateUtils.daysBetween(from, to);
    if (gap <= 1) return gap == 1;
    if (gap > DateTime.daysPerWeek) return false;
    for (var i = 1; i < gap; i++) {
      if (!restWeekdays.contains(AppDateUtils.addDays(from, i).weekday)) {
        return false;
      }
    }
    return true;
  }

  /// The longest run of consecutive Monday-based weeks with at least [goal]
  /// active days each. The week containing [now] counts as soon as it meets
  /// the goal and never breaks a run while it is still in progress; weeks
  /// after it are ignored. Dated to the day the goal was met in the week
  /// that completed the run.
  static _Result _weeks(
    Set<DateTime> activeDays,
    int goal,
    int target,
    DateTime now,
  ) {
    final byWeek = <DateTime, List<DateTime>>{};
    for (final d in activeDays) {
      byWeek.putIfAbsent(_weekStart(d), () => []).add(d);
    }
    final weeks = byWeek.keys.toList()..sort();
    final currentWeek = _weekStart(now);
    var best = 0;
    var run = 0;
    DateTime? previous;
    DateTime? at;
    for (final week in weeks) {
      if (week.isAfter(currentWeek)) break;
      final days = byWeek[week]!..sort();
      if (days.length < goal) {
        if (week == currentWeek) break;
        run = 0;
        previous = null;
        continue;
      }
      final consecutive =
          previous != null && AppDateUtils.daysBetween(previous, week) == 7;
      run = consecutive ? run + 1 : 1;
      if (run > best) best = run;
      if (at == null && run >= target) at = days[goal - 1];
      previous = week;
    }
    return _Result(best, at);
  }

  /// Local midnight of the Monday that starts the week of [d].
  static DateTime _weekStart(DateTime d) =>
      AppDateUtils.addDays(d, DateTime.monday - d.weekday);

  /// Total XP needed to stand at [level].
  static int _xpToReachLevel(int level) {
    var xp = 0;
    for (var l = 1; l < level; l++) {
      xp += LevelSystem.xpToFinishLevel(l);
    }
    return xp;
  }
}
