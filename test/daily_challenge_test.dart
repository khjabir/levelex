import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/engagement/daily_challenge.dart';
import 'package:levelex/core/levels/level_system.dart';
import 'package:levelex/core/utils/date_utils.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

var _ids = 0;

WorkoutSession session(
  DateTime at,
  ExerciseType exercise,
  int reps, {
  int? target,
  bool verified = true,
  SessionStatus? status,
}) {
  final goal = target ?? reps;
  return WorkoutSession(
    id: 's${_ids++}',
    startTime: at,
    endTime: at.add(const Duration(minutes: 1)),
    targetReps: goal,
    completedReps: reps,
    status:
        status ??
        (reps >= goal ? SessionStatus.completed : SessionStatus.incomplete),
    exercise: exercise,
    verified: verified,
  );
}

WorkoutSession skipped(DateTime at, ExerciseType exercise) => WorkoutSession(
  id: 'skip${_ids++}',
  startTime: at,
  targetReps: 10,
  completedReps: 0,
  status: SessionStatus.skipped,
  exercise: exercise,
);

/// Unverified sessions that meet every part of [c] exactly (0 XP, but they
/// count towards the challenge like the daily totals do).
List<WorkoutSession> meet(DailyChallenge c, {bool verified = false}) => [
  for (final p in c.parts)
    session(
      c.day.add(const Duration(hours: 9)),
      p.exercise,
      p.target,
      verified: verified,
    ),
];

PtRecord ptRecord(DateTime start) => PtRecord(
  id: 'pt-${start.toIso8601String()}',
  startTime: start,
  endTime: start.add(const Duration(minutes: 30)),
  mode: WorkoutMode.fullBody,
  plannedMinutes: 30,
  items: const [
    PtItemResult(
      movementId: 'push_up',
      phase: PlanPhase.main,
      setsPlanned: 3,
      setsDone: 3,
      reps: 30,
      seconds: 0,
      skipped: false,
    ),
  ],
  verified: true,
  plannedItems: 1,
);

/// Whether [day]'s challenge is strictly harder at [level] than at level 1
/// in at least one part, so meeting the level-1 targets exactly leaves it
/// unfinished at [level].
bool harderAt(DateTime day, int level) {
  final easy = DailyChallenges.forDay(day, level: 1).parts;
  final hard = DailyChallenges.forDay(day, level: level).parts;
  for (var i = 0; i < easy.length; i++) {
    if (hard[i].target > easy[i].target) return true;
  }
  return false;
}

void main() {
  final monday = DateTime(2026, 10, 19);
  assert(monday.weekday == DateTime.monday);

  group('DailyChallenges.forDay', () {
    test('is deterministic for the same day and level', () {
      final a = DailyChallenges.forDay(DateTime(2026, 10, 20), level: 3);
      final b = DailyChallenges.forDay(DateTime(2026, 10, 20), level: 3);
      expect(a.parts, b.parts);
      expect(a.title, b.title);
      expect(a.tagline, b.tagline);
      expect(a.day, DateTime(2026, 10, 20));
    });

    test('ignores the time of day', () {
      final a = DailyChallenges.forDay(
        DateTime(2026, 10, 20, 23, 59),
        level: 2,
      );
      final b = DailyChallenges.forDay(DateTime(2026, 10, 20, 0, 1), level: 2);
      expect(a.parts, b.parts);
      expect(a.title, b.title);
    });

    test('different days give different challenges', () {
      final firsts = <ExerciseType>{};
      final taglines = <String>{};
      for (var i = 0; i < 14; i++) {
        final c = DailyChallenges.forDay(
          AppDateUtils.addDays(monday, i),
          level: 1,
        );
        firsts.add(c.parts.first.exercise);
        taglines.add(c.tagline);
      }
      expect(firsts.length, greaterThan(3));
      expect(taglines.length, 14);
    });

    test('never repeats the previous day\'s first exercise', () {
      var previous = DailyChallenges.forDay(DateTime(2025, 12, 31), level: 1);
      for (var i = 0; i < 730; i++) {
        final day = AppDateUtils.addDays(DateTime(2026, 1, 1), i);
        final c = DailyChallenges.forDay(day, level: 1 + i % 7);
        expect(
          c.parts.first.exercise,
          isNot(previous.parts.first.exercise),
          reason: '$day repeats ${previous.day}',
        );
        previous = c;
      }
    });

    test('uses every exercise over time', () {
      final seen = <ExerciseType>{};
      for (var i = 0; i < 120; i++) {
        final c = DailyChallenges.forDay(
          AppDateUtils.addDays(monday, i),
          level: 1,
        );
        seen.addAll(c.parts.map((p) => p.exercise));
      }
      expect(seen, containsAll(ExerciseType.values));
    });

    test('has one part on Mon/Wed/Fri/Sun and two on Tue/Thu/Sat', () {
      for (var week = 0; week < 20; week++) {
        for (var d = 0; d < 7; d++) {
          final day = AppDateUtils.addDays(monday, week * 7 + d);
          final c = DailyChallenges.forDay(day, level: 1);
          final two = const {
            DateTime.tuesday,
            DateTime.thursday,
            DateTime.saturday,
          }.contains(day.weekday);
          expect(c.parts.length, two ? 2 : 1, reason: '$day');
          if (two) {
            expect(c.parts[0].exercise, isNot(c.parts[1].exercise));
          }
          if (day.weekday == DateTime.saturday) {
            expect(
              c.parts.where((p) => p.exercise.isTimed).length,
              1,
              reason: 'Saturday pairs a rep part with a timed part: $day',
            );
          }
        }
      }
    });

    test('titles and taglines name the day and the targets', () {
      for (var d = 0; d < 7; d++) {
        final day = AppDateUtils.addDays(monday, d);
        final c = DailyChallenges.forDay(day, level: 4);
        expect(c.title, isNotEmpty);
        expect(c.title[0], c.title[0].toUpperCase());
        if (c.parts.length == 1) {
          final e = c.parts.single.exercise;
          expect(c.title.toLowerCase(), startsWith(e.singular.toLowerCase()));
          expect(
            c.title,
            endsWith(
              const [
                'Monday',
                'Tuesday',
                'Wednesday',
                'Thursday',
                'Friday',
                'Saturday',
                'Sunday',
              ][day.weekday - 1],
            ),
          );
        } else {
          expect(c.title, anyOf(contains(' & '), contains(' combo')));
        }
        for (final p in c.parts) {
          expect(c.tagline, contains('${p.target}'));
          expect(
            c.tagline,
            contains(
              p.exercise.isTimed ? 'second' : p.exercise.countLabel(p.target),
            ),
          );
        }
        expect(c.tagline, endsWith('.'));
        expect(c.tagline[0], c.tagline[0].toUpperCase());
      }
    });

    test('a two-part tagline reads like a sentence', () {
      final c = DailyChallenge(
        day: monday,
        title: 't',
        tagline: '',
        parts: const [
          DailyChallengePart(exercise: ExerciseType.pushUp, target: 25),
          DailyChallengePart(exercise: ExerciseType.plank, target: 40),
        ],
      );
      expect(c.parts[0].describe(), '25 push-ups');
      expect(c.parts[1].describe(), 'a 40-second plank');
      expect(c.totalTarget, 65);
    });
  });

  group('DailyChallenges.targetFor', () {
    test('level 1 is the default target', () {
      for (final e in ExerciseType.values) {
        expect(DailyChallenges.targetFor(e, level: 1), e.defaultTarget);
      }
    });

    test('grows 12% per level with rounding rules', () {
      expect(DailyChallenges.targetFor(ExerciseType.pushUp, level: 5), 15);
      expect(DailyChallenges.targetFor(ExerciseType.burpee, level: 5), 12);
      // 20 × 1.48 = 29.6 → 30 (≥ 20: multiple of 5).
      expect(DailyChallenges.targetFor(ExerciseType.jumpingJack, level: 5), 30);
      // 30 × 1.48 = 44.4 → 44 → 45 s.
      expect(DailyChallenges.targetFor(ExerciseType.plank, level: 5), 45);
      // 10 × 2.08 = 20.8 → 21 → 20.
      expect(DailyChallenges.targetFor(ExerciseType.pushUp, level: 10), 20);
    });

    test('caps at four times the default', () {
      expect(DailyChallenges.targetFor(ExerciseType.pushUp, level: 26), 40);
      expect(DailyChallenges.targetFor(ExerciseType.plank, level: 26), 120);
      expect(
        DailyChallenges.targetFor(ExerciseType.jumpingJack, level: 26),
        80,
      );
      // 8 × 4 = 32 → nearest multiple of 5 below the cap.
      expect(DailyChallenges.targetFor(ExerciseType.burpee, level: 26), 30);
      for (final e in ExerciseType.values) {
        expect(
          DailyChallenges.targetFor(e, level: 100),
          DailyChallenges.targetFor(e, level: 26),
        );
        expect(
          DailyChallenges.targetFor(e, level: 100),
          lessThanOrEqualTo(e.defaultTarget * 4),
        );
      }
    });

    test('never decreases with level and respects the rounding rules', () {
      for (final e in ExerciseType.values) {
        var last = 0;
        for (var level = 1; level <= 40; level++) {
          final t = DailyChallenges.targetFor(e, level: level);
          expect(t, greaterThanOrEqualTo(last), reason: '$e level $level');
          if (e.isTimed || t >= 20) expect(t % 5, 0, reason: '$e level $level');
          last = t;
        }
      }
    });

    test('levels below 1 behave like level 1', () {
      expect(DailyChallenges.targetFor(ExerciseType.pushUp, level: 0), 10);
      expect(DailyChallenges.targetFor(ExerciseType.pushUp, level: -3), 10);
    });

    test('forDay uses targetFor for every part', () {
      for (var i = 0; i < 14; i++) {
        final day = AppDateUtils.addDays(monday, i);
        final c = DailyChallenges.forDay(day, level: 7);
        for (final p in c.parts) {
          expect(p.target, DailyChallenges.targetFor(p.exercise, level: 7));
        }
      }
    });
  });

  group('DailyChallenges.progress', () {
    final day = DateTime(2026, 10, 20);
    final challenge = DailyChallenge(
      day: day,
      title: 'Test',
      tagline: '',
      parts: const [
        DailyChallengePart(exercise: ExerciseType.pushUp, target: 20),
        DailyChallengePart(exercise: ExerciseType.plank, target: 40),
      ],
    );

    test('sums only that day\'s non-skipped sessions of each exercise', () {
      final sessions = [
        session(DateTime(2026, 10, 20, 9), ExerciseType.pushUp, 12),
        session(
          DateTime(2026, 10, 20, 12),
          ExerciseType.pushUp,
          6,
          target: 10,
          verified: false,
        ),
        session(DateTime(2026, 10, 19, 9), ExerciseType.pushUp, 50),
        session(DateTime(2026, 10, 21, 0, 0, 1), ExerciseType.pushUp, 50),
        skipped(DateTime(2026, 10, 20, 15), ExerciseType.pushUp),
        session(DateTime(2026, 10, 20, 18), ExerciseType.plank, 25),
        session(DateTime(2026, 10, 20, 19), ExerciseType.squat, 30),
      ];
      final p = DailyChallenges.progress(challenge, sessions);
      expect(p.done, [18, 25]);
      expect(p.completed, isFalse);
      expect(p.remainingParts, 2);
      expect(p.fraction, closeTo((18 / 20 + 25 / 40) / 2, 1e-9));

      final more = [
        ...sessions,
        session(DateTime(2026, 10, 20, 20), ExerciseType.plank, 20),
      ];
      final p2 = DailyChallenges.progress(challenge, more);
      expect(p2.done, [18, 45]);
      expect(p2.completed, isFalse);
      expect(p2.remainingParts, 1);
      expect(p2.fraction, closeTo((18 / 20 + 1) / 2, 1e-9));

      final done = [
        ...more,
        session(DateTime(2026, 10, 20, 21), ExerciseType.pushUp, 2),
      ];
      final p3 = DailyChallenges.progress(challenge, done);
      expect(p3.completed, isTrue);
      expect(p3.remainingParts, 0);
      expect(p3.fraction, 1);
    });

    test('empty history is zero progress', () {
      final p = DailyChallenges.progress(challenge, const []);
      expect(p.done, [0, 0]);
      expect(p.fraction, 0);
      expect(p.completed, isFalse);
      expect(p.remainingParts, 2);
    });
  });

  group('DailyChallenges.completedDays', () {
    test('is empty without sessions', () {
      expect(
        DailyChallenges.completedDays(
          sessions: const [],
          ptRecords: [ptRecord(DateTime(2026, 10, 1, 9))],
          through: DateTime(2026, 10, 21),
        ),
        isEmpty,
      );
    });

    test('the challenge bonus alone can raise the level and the targets', () {
      // Four unverified challenge days earn 240 bonus XP and no session XP,
      // so day 5 is generated at level 2. Pick a start where that matters.
      var start = DateTime(2026, 1, 5);
      while (!harderAt(AppDateUtils.addDays(start, 4), 2)) {
        start = AppDateUtils.addDays(start, 1);
      }
      final days = [
        for (var i = 0; i < 10; i++) AppDateUtils.addDays(start, i),
      ];
      final sessions = <WorkoutSession>[
        for (var i = 0; i < 5; i++)
          ...meet(DailyChallenges.forDay(days[i], level: 1)),
        // Day 7 at level 2 (240 bonus XP, still below level 3).
        ...meet(DailyChallenges.forDay(days[6], level: 2)),
        // Day 9: effort on the wrong exercise.
        session(
          days[8].add(const Duration(hours: 9)),
          DailyChallenges.forDay(days[8], level: 2).parts.first.exercise ==
                  ExerciseType.squat
              ? ExerciseType.pushUp
              : ExerciseType.squat,
          99,
        ),
      ];
      expect(LevelSystem.levelFor(4 * DailyChallenge.bonusXp).level, 2);
      expect(LevelSystem.levelFor(5 * DailyChallenge.bonusXp).level, 2);

      // Without the bonus every one of the first five days would count.
      expect(
        DailyChallenges.progress(
          DailyChallenges.forDay(days[4], level: 1),
          sessions,
        ).completed,
        isTrue,
      );

      final completed = DailyChallenges.completedDays(
        sessions: sessions,
        ptRecords: const [],
        through: days[9],
      );
      expect(completed, {days[0], days[1], days[2], days[3], days[6]});
    });

    test('stops at `through`', () {
      final days = [
        for (var i = 0; i < 4; i++) AppDateUtils.addDays(monday, i),
      ];
      final sessions = [
        for (final d in days) ...meet(DailyChallenges.forDay(d, level: 1)),
      ];
      expect(
        DailyChallenges.completedDays(
          sessions: sessions,
          ptRecords: const [],
          through: days[1].add(const Duration(hours: 23)),
        ),
        {days[0], days[1]},
      );
      expect(
        DailyChallenges.completedDays(
          sessions: sessions,
          ptRecords: const [],
          through: AppDateUtils.addDays(monday, -1),
        ),
        isEmpty,
      );
    });

    test('verified session XP and earlier PT records set the level', () {
      // A PT record before the first session already puts the user at
      // level 2 (340 XP), so day 1 is generated at level 2.
      var day = DateTime(2026, 2, 2);
      while (!harderAt(day, 2)) {
        day = AppDateUtils.addDays(day, 1);
      }
      final pt = [
        ptRecord(AppDateUtils.addDays(day, -3).add(const Duration(hours: 9))),
      ];
      expect(
        LevelSystem.levelFor(LevelSystem.xpForPtRecord(pt.single)).level,
        2,
      );

      final easy = meet(DailyChallenges.forDay(day, level: 1), verified: true);
      expect(
        DailyChallenges.completedDays(
          sessions: easy,
          ptRecords: pt,
          through: day,
        ),
        isEmpty,
      );
      expect(
        DailyChallenges.completedDays(
          sessions: easy,
          ptRecords: const [],
          through: day,
        ),
        {day},
      );
      final hard = meet(DailyChallenges.forDay(day, level: 2), verified: true);
      expect(
        DailyChallenges.completedDays(
          sessions: hard,
          ptRecords: pt,
          through: day,
        ),
        {day},
      );
    });

    test('a skipped reminder does not complete a day', () {
      final c = DailyChallenges.forDay(monday, level: 1);
      final sessions = [
        skipped(monday.add(const Duration(hours: 9)), c.parts.first.exercise),
      ];
      expect(
        DailyChallenges.completedDays(
          sessions: sessions,
          ptRecords: const [],
          through: monday,
        ),
        isEmpty,
      );
    });
  });

  group('DailyChallenges.streak and bonusXp', () {
    final done = {
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 9),
      DateTime(2026, 3, 10),
    };

    test('counts consecutive days ending today', () {
      expect(DailyChallenges.streak(done, DateTime(2026, 3, 10, 20)), 3);
    });

    test('carries over from yesterday', () {
      expect(DailyChallenges.streak(done, DateTime(2026, 3, 11, 8)), 3);
    });

    test('breaks after a missed day', () {
      expect(DailyChallenges.streak(done, DateTime(2026, 3, 12, 8)), 0);
      expect(
        DailyChallenges.streak({
          ...done,
          DateTime(2026, 3, 6),
        }, DateTime(2026, 3, 10)),
        3,
      );
    });

    test('is zero without challenge days', () {
      expect(DailyChallenges.streak(const {}, DateTime(2026, 3, 10)), 0);
    });

    test('bonus XP is 60 per completed day', () {
      expect(DailyChallenges.bonusXp(done), 180);
      expect(DailyChallenges.bonusXp(const {}), 0);
      expect(DailyChallenge.bonusXp, 60);
    });
  });
}
