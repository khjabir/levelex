import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/engagement/achievements.dart';
import 'package:levelex/core/levels/level_system.dart';
import 'package:levelex/core/utils/date_utils.dart';
import 'package:levelex/features/challenge/models/challenge.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/strength/logic/records.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

final now = DateTime(2026, 4, 1, 12);

WorkoutSession session(
  DateTime at, {
  int reps = 10,
  int target = 10,
  ExerciseType exercise = ExerciseType.pushUp,
  bool verified = true,
  double? formScore,
  Duration length = const Duration(minutes: 1),
}) => WorkoutSession(
  id: '${exercise.id}-${at.toIso8601String()}',
  startTime: at,
  endTime: at.add(length),
  targetReps: target,
  completedReps: reps,
  status: reps >= target ? SessionStatus.completed : SessionStatus.incomplete,
  exercise: exercise,
  formScore: formScore,
  verified: verified,
);

PtRecord ptRecord(
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  bool verified = true,
  bool finished = true,
  int reps = 30,
  int? activeSeconds,
}) => PtRecord(
  id: 'pt-${start.toIso8601String()}',
  startTime: start,
  endTime: start.add(length),
  mode: WorkoutMode.fullBody,
  plannedMinutes: length.inMinutes,
  items: [
    PtItemResult(
      movementId: 'push_up',
      phase: PlanPhase.main,
      setsPlanned: 3,
      setsDone: finished ? 3 : 1,
      reps: reps,
      seconds: 0,
      skipped: false,
    ),
  ],
  verified: verified,
  plannedItems: 1,
  activeSeconds: activeSeconds,
);

LiftEntry lift(String id, DateTime at, List<LiftSet> sets) =>
    LiftEntry(id: id, movementId: 'custom:bench', startTime: at, sets: sets);

ChallengeRecord challenge(DateTime at) => ChallengeRecord(
  id: 'ch-${at.toIso8601String()}',
  date: at,
  exercise: ExerciseType.pushUp,
  mode: ChallengeMode.timed,
  value: 30,
  scores: const [],
);

/// Completed push-up sets at 09:00 on [count] consecutive days from [first].
List<WorkoutSession> dailySets(DateTime first, int count) => [
  for (var i = 0; i < count; i++)
    session(AppDateUtils.addDays(first, i).add(const Duration(hours: 9))),
];

List<AchievementStatus> evaluate({
  Iterable<WorkoutSession> sessions = const [],
  Iterable<PtRecord> ptRecords = const [],
  Iterable<LiftEntry> lifts = const [],
  Iterable<BodyWeightEntry> bodyWeights = const [],
  Iterable<ChallengeRecord> challenges = const [],
  Set<DateTime> dailyChallengeDays = const {},
  int weeklyGoal = 3,
  DateTime? at,
}) => Achievements.evaluate(
  AchievementInput(
    now: at ?? now,
    sessions: sessions,
    ptRecords: ptRecords,
    lifts: lifts,
    bodyWeights: bodyWeights,
    challenges: challenges,
    dailyChallengeDays: dailyChallengeDays,
    weeklyGoal: weeklyGoal,
  ),
);

AchievementStatus find(List<AchievementStatus> statuses, String id) =>
    statuses.singleWhere((s) => s.achievement.id == id);

List<String> ids(Iterable<AchievementStatus> statuses) => [
  for (final s in statuses) s.achievement.id,
];

void main() {
  group('Achievements catalogue', () {
    test('has unique ids, known icons and a working lookup', () {
      final all = Achievements.all;
      expect(all.map((a) => a.id).toSet().length, all.length);
      for (final a in all) {
        expect(Achievements.iconKeys, contains(a.icon), reason: a.id);
        expect(a.target, greaterThan(0), reason: a.id);
        expect(Achievements.byId(a.id), same(a));
      }
      expect(Achievements.byId('nope'), isNull);
      expect(
        Achievements.byId('all_rounder')!.target,
        ExerciseType.values.length,
      );
    });
  });

  group('Achievements.evaluate', () {
    test('empty input leaves every badge locked at zero progress', () {
      final statuses = evaluate();
      expect(statuses.length, Achievements.all.length);
      expect(ids(statuses).toSet(), {for (final a in Achievements.all) a.id});
      for (final s in statuses) {
        expect(s.earned, isFalse, reason: s.achievement.id);
        expect(s.current, 0, reason: s.achievement.id);
        expect(s.progress, 0, reason: s.achievement.id);
        expect(s.earnedAt, isNull, reason: s.achievement.id);
      }
    });

    test('first_set needs one completed, verified set', () {
      final at = DateTime(2026, 3, 10, 9);
      expect(
        find(
          evaluate(sessions: [session(at, verified: false)]),
          'first_set',
        ).earned,
        isFalse,
      );
      expect(
        find(evaluate(sessions: [session(at, reps: 4)]), 'first_set').earned,
        isFalse,
      );
      final earned = find(evaluate(sessions: [session(at)]), 'first_set');
      expect(earned.earned, isTrue);
      expect(earned.current, 1);
      expect(earned.progress, 1);
      expect(earned.earnedAt, DateTime(2026, 3, 10, 9, 1));
    });

    test('reps tiers add MY PT reps and ignore timed holds', () {
      final statuses = evaluate(
        sessions: [
          session(DateTime(2026, 3, 1, 9), reps: 30, target: 30),
          session(DateTime(2026, 3, 2, 9), reps: 30, target: 30),
          session(
            DateTime(2026, 3, 3, 9),
            reps: 60,
            target: 60,
            exercise: ExerciseType.plank,
          ),
        ],
        ptRecords: [ptRecord(DateTime(2026, 3, 4, 18), reps: 50)],
      );
      final hundred = find(statuses, 'reps_100');
      expect(hundred.earned, isTrue);
      expect(hundred.current, 110);
      expect(hundred.earnedAt, DateTime(2026, 3, 4, 18, 30));
      final thousand = find(statuses, 'reps_1000');
      expect(thousand.earned, isFalse);
      expect(thousand.current, 110);
      expect(thousand.progress, closeTo(0.11, 1e-9));
    });

    test('day_50 sums the sets of one day', () {
      final statuses = evaluate(
        sessions: [
          session(DateTime(2026, 3, 10, 9), reps: 20, target: 20),
          session(DateTime(2026, 3, 10, 10), reps: 20, target: 20),
          session(DateTime(2026, 3, 10, 11), reps: 20, target: 20),
          session(DateTime(2026, 3, 11, 9), reps: 40, target: 40),
          session(DateTime(2026, 3, 12, 9), reps: 40, target: 40),
        ],
      );
      final fifty = find(statuses, 'day_50');
      expect(fifty.earned, isTrue);
      expect(fifty.current, 60);
      expect(fifty.earnedAt, DateTime(2026, 3, 10, 11, 1));
      final hundred = find(statuses, 'day_100');
      expect(hundred.earned, isFalse);
      expect(hundred.current, 60);
    });

    test('early_bird and night_owl go by the start hour', () {
      final early = evaluate(sessions: [session(DateTime(2026, 3, 10, 6, 30))]);
      expect(find(early, 'early_bird').earned, isTrue);
      expect(find(early, 'night_owl').earned, isFalse);

      final late = evaluate(sessions: [session(DateTime(2026, 3, 10, 22, 15))]);
      expect(find(late, 'night_owl').earned, isTrue);
      expect(find(late, 'early_bird').earned, isFalse);

      final noon = evaluate(sessions: [session(DateTime(2026, 3, 10, 12))]);
      expect(find(noon, 'early_bird').earned, isFalse);
      expect(find(noon, 'night_owl').earned, isFalse);

      final unverified = evaluate(
        sessions: [session(DateTime(2026, 3, 10, 6), verified: false)],
      );
      expect(find(unverified, 'early_bird').earned, isFalse);
    });

    test('all_rounder counts distinct exercises', () {
      final few = evaluate(
        sessions: [
          session(DateTime(2026, 3, 1, 9)),
          session(DateTime(2026, 3, 2, 9)),
          session(DateTime(2026, 3, 3, 9)),
          session(DateTime(2026, 3, 3, 10), exercise: ExerciseType.squat),
        ],
      );
      expect(find(few, 'all_rounder').current, 2);
      expect(find(few, 'all_rounder').earned, isFalse);

      final types = ExerciseType.values;
      final every = evaluate(
        sessions: [
          for (var i = 0; i < types.length; i++)
            session(
              DateTime(2026, 3, 1, 8 + i),
              exercise: types[i],
              reps: types[i].defaultTarget,
              target: types[i].defaultTarget,
            ),
        ],
      );
      final status = find(every, 'all_rounder');
      expect(status.earned, isTrue);
      expect(status.current, types.length);
      expect(status.earnedAt, DateTime(2026, 3, 1, 8 + types.length - 1, 1));
    });

    test('streak tiers follow the longest run of days', () {
      final week = evaluate(sessions: dailySets(DateTime(2026, 3, 1), 7));
      expect(find(week, 'streak_3').earned, isTrue);
      expect(find(week, 'streak_3').earnedAt, DateTime(2026, 3, 3));
      expect(find(week, 'streak_7').earned, isTrue);
      expect(find(week, 'streak_7').earnedAt, DateTime(2026, 3, 7));
      expect(find(week, 'streak_30').earned, isFalse);
      expect(find(week, 'streak_30').current, 7);

      final gap = evaluate(
        sessions: [
          ...dailySets(DateTime(2026, 3, 1), 3),
          ...dailySets(DateTime(2026, 3, 5), 3),
        ],
      );
      expect(find(gap, 'streak_3').earned, isTrue);
      expect(find(gap, 'streak_7').earned, isFalse);
      expect(find(gap, 'streak_7').current, 3);
    });

    test('weeks_4 counts consecutive weeks that hit the goal', () {
      final lastMonday = DateTime(2026, 3, 9);
      expect(lastMonday.weekday, DateTime.monday);
      final wednesday = DateTime(2026, 3, 18, 12);

      List<WorkoutSession> week(DateTime monday, List<int> offsets) => [
        for (final o in offsets)
          session(
            AppDateUtils.addDays(monday, o).add(const Duration(hours: 9)),
          ),
      ];
      final mondays = [
        for (var i = 3; i >= 0; i--) AppDateUtils.addDays(lastMonday, -7 * i),
      ];

      final full = evaluate(
        sessions: [
          for (final m in mondays) ...week(m, [0, 2, 4]),
        ],
        at: wednesday,
      );
      expect(find(full, 'weeks_4').earned, isTrue);
      expect(find(full, 'weeks_4').current, 4);
      expect(find(full, 'weeks_4').earnedAt, DateTime(2026, 3, 13));

      final broken = evaluate(
        sessions: [
          ...week(mondays[0], [0, 2, 4]),
          ...week(mondays[1], [0, 2]),
          ...week(mondays[2], [0, 2, 4]),
          ...week(mondays[3], [0, 2, 4]),
        ],
        at: wednesday,
      );
      expect(find(broken, 'weeks_4').earned, isFalse);
      expect(find(broken, 'weeks_4').current, 2);

      final easier = evaluate(
        sessions: [
          ...week(mondays[0], [0, 2, 4]),
          ...week(mondays[1], [0, 2]),
          ...week(mondays[2], [0, 2, 4]),
          ...week(mondays[3], [0, 2, 4]),
        ],
        weeklyGoal: 2,
        at: wednesday,
      );
      expect(find(easier, 'weeks_4').earned, isTrue);
    });

    test('marathon adds up a day\'s active minutes', () {
      final day = DateTime(2026, 3, 10);
      final pt = ptRecord(
        day.add(const Duration(hours: 7)),
        length: const Duration(minutes: 45),
        activeSeconds: 40 * 60,
      );
      final one = session(
        day.add(const Duration(hours: 9)),
        length: const Duration(minutes: 12),
      );
      final two = session(
        day.add(const Duration(hours: 10)),
        length: const Duration(minutes: 12),
      );
      final earned = evaluate(sessions: [one, two], ptRecords: [pt]);
      expect(find(earned, 'marathon').earned, isTrue);
      expect(find(earned, 'marathon').current, 64);
      expect(find(earned, 'marathon').earnedAt, DateTime(2026, 3, 10, 10, 12));

      final split = evaluate(
        sessions: [
          one,
          session(
            DateTime(2026, 3, 11, 10),
            length: const Duration(minutes: 12),
          ),
        ],
        ptRecords: [pt],
      );
      expect(find(split, 'marathon').earned, isFalse);
      expect(find(split, 'marathon').current, 52);
    });

    test('level tiers cross with the set that earned the XP', () {
      final fourteen = dailySets(DateTime(2026, 3, 1), 14);
      expect(LevelSystem.levelFor(LevelSystem.totalXp(fourteen)).level, 5);
      final statuses = evaluate(sessions: fourteen);
      final five = find(statuses, 'level_5');
      expect(five.earned, isTrue);
      expect(five.current, 5);
      expect(five.earnedAt, DateTime(2026, 3, 14, 9, 1));
      expect(find(statuses, 'level_10').current, 5);
      expect(find(statuses, 'level_10').earned, isFalse);

      final thirteen = evaluate(sessions: fourteen.sublist(0, 13));
      expect(find(thirteen, 'level_5').earned, isFalse);
      expect(
        find(thirteen, 'level_5').current,
        LevelSystem.levelFor(LevelSystem.totalXp(fourteen.sublist(0, 13)))
            .level,
      );
    });

    test('pr tiers count personal records from the lift log', () {
      final lifts = [
        lift('a', DateTime(2026, 3, 1, 10), const [
          LiftSet(weightKg: 60, reps: 5),
        ]),
        lift('b', DateTime(2026, 3, 8, 10), const [
          LiftSet(weightKg: 70, reps: 5),
        ]),
      ];
      final statuses = evaluate(lifts: lifts);
      final first = find(statuses, 'pr_1');
      expect(first.earned, isTrue);
      expect(first.earnedAt, DateTime(2026, 3, 1, 10));
      final ten = find(statuses, 'pr_10');
      expect(ten.earned, isFalse);
      expect(ten.current, RecordBook.recent(lifts, limit: 1000).length);
      expect(ten.current, 6);
    });

    test('heavy_100 needs a 100 kg work set', () {
      final heavy = evaluate(
        lifts: [
          lift('a', DateTime(2026, 3, 1, 10), const [
            LiftSet(weightKg: 100, reps: 3),
          ]),
        ],
      );
      expect(find(heavy, 'heavy_100').earned, isTrue);
      expect(find(heavy, 'heavy_100').current, 100);
      expect(find(heavy, 'heavy_100').earnedAt, DateTime(2026, 3, 1, 10));

      final light = evaluate(
        lifts: [
          lift('a', DateTime(2026, 3, 1, 10), const [
            LiftSet(weightKg: 100, reps: 1, warmUp: true),
            LiftSet(weightKg: 80, reps: 5),
          ]),
        ],
      );
      expect(find(light, 'heavy_100').earned, isFalse);
      expect(find(light, 'heavy_100').current, 80);
      expect(find(light, 'heavy_100').progress, 0.8);
    });

    test('pt tiers count completed MY PT sessions', () {
      final start = DateTime(2026, 3, 1, 18);
      final one = evaluate(ptRecords: [ptRecord(start)]);
      expect(find(one, 'pt_1').earned, isTrue);
      expect(find(one, 'pt_1').earnedAt, DateTime(2026, 3, 1, 18, 30));
      expect(find(one, 'pt_10').current, 1);

      expect(
        find(
          evaluate(ptRecords: [ptRecord(start, verified: false)]),
          'pt_1',
        ).earned,
        isFalse,
      );
      expect(
        find(
          evaluate(ptRecords: [ptRecord(start, finished: false)]),
          'pt_1',
        ).earned,
        isFalse,
      );

      final ten = evaluate(
        ptRecords: [
          for (var i = 0; i < 10; i++)
            ptRecord(
              AppDateUtils.addDays(start, i).add(const Duration(hours: 18)),
            ),
        ],
      );
      expect(find(ten, 'pt_10').earned, isTrue);
      expect(find(ten, 'pt_50').current, 10);
    });

    test('form_master needs 90% form on a set of ten', () {
      final at = DateTime(2026, 3, 1, 9);
      bool earned(WorkoutSession s) =>
          find(evaluate(sessions: [s]), 'form_master').earned;
      expect(
        earned(session(at, reps: 12, target: 12, formScore: 0.95)),
        isTrue,
      );
      expect(earned(session(at, reps: 8, target: 8, formScore: 0.95)), isFalse);
      expect(
        earned(session(at, reps: 12, target: 12, formScore: 0.8)),
        isFalse,
      );
      expect(earned(session(at, reps: 12, target: 12)), isFalse);
      expect(
        earned(
          session(at, reps: 12, target: 12, formScore: 0.95, verified: false),
        ),
        isFalse,
      );
    });

    test('challenge, daily and weigh-in tiers count their records', () {
      final statuses = evaluate(
        challenges: [challenge(DateTime(2026, 3, 5, 19))],
        dailyChallengeDays: {for (var i = 7; i >= 1; i--) DateTime(2026, 3, i)},
        bodyWeights: [
          for (var i = 1; i <= 7; i++)
            BodyWeightEntry(date: DateTime(2026, 3, i), kg: 80),
          BodyWeightEntry(date: DateTime(2026, 3, 7), kg: 79),
        ],
      );
      expect(find(statuses, 'challenge_1').earned, isTrue);
      expect(find(statuses, 'challenge_1').earnedAt, DateTime(2026, 3, 5, 19));
      expect(find(statuses, 'challenge_5').current, 1);

      expect(find(statuses, 'daily_7').earned, isTrue);
      expect(find(statuses, 'daily_7').earnedAt, DateTime(2026, 3, 7));
      expect(find(statuses, 'daily_30').current, 7);

      expect(find(statuses, 'weigh_7').earned, isTrue);
      expect(find(statuses, 'weigh_7').current, 7);
      expect(find(statuses, 'weigh_7').earnedAt, DateTime(2026, 3, 7));
    });

    test('newlyEarned skips badges already seen and keeps the order', () {
      final statuses = evaluate(sessions: [session(DateTime(2026, 3, 1, 6))]);
      expect(ids(Achievements.newlyEarned(statuses, const {})), [
        'first_set',
        'early_bird',
      ]);
      expect(ids(Achievements.newlyEarned(statuses, const {'first_set'})), [
        'early_bird',
      ]);
      expect(
        Achievements.newlyEarned(statuses, const {'first_set', 'early_bird'}),
        isEmpty,
      );
    });

    test('orders earned by recency, then locked by progress', () {
      final statuses = evaluate(
        sessions: [
          session(DateTime(2026, 3, 1, 6)),
          session(DateTime(2026, 3, 3, 23)),
        ],
      );
      expect(ids(statuses).sublist(0, 5), [
        'night_owl', // newest
        'first_set', // same moment as early_bird: catalogue order
        'early_bird',
        'level_5', // 2/5
        'streak_3', // 1/3
      ]);

      final earned = statuses.where((s) => s.earned).toList();
      final locked = statuses.where((s) => !s.earned).toList();
      expect(statuses.sublist(0, earned.length), earned);
      for (var i = 1; i < earned.length; i++) {
        expect(
          earned[i].earnedAt!.isAfter(earned[i - 1].earnedAt!),
          isFalse,
          reason: '${earned[i - 1]} before ${earned[i]}',
        );
      }
      final catalogue = [for (final a in Achievements.all) a.id];
      for (var i = 1; i < locked.length; i++) {
        final a = locked[i - 1];
        final b = locked[i];
        expect(
          b.progress,
          lessThanOrEqualTo(a.progress),
          reason: '$a before $b',
        );
        if (a.progress == b.progress) {
          expect(
            catalogue.indexOf(a.achievement.id),
            lessThan(catalogue.indexOf(b.achievement.id)),
            reason: '$a before $b',
          );
        }
      }
    });

    test('earnedAt is set for every earned badge and never after now', () {
      final statuses = evaluate(
        sessions: [
          ...dailySets(DateTime(2026, 3, 1), 7),
          session(DateTime(2026, 4, 2, 6)), // clock ahead of now
        ],
        ptRecords: [ptRecord(DateTime(2026, 3, 2, 18))],
        lifts: [
          lift('a', DateTime(2026, 3, 1, 10), const [
            LiftSet(weightKg: 60, reps: 5),
          ]),
        ],
        challenges: [challenge(DateTime(2026, 3, 5, 19))],
        dailyChallengeDays: {DateTime(2026, 3, 1)},
        bodyWeights: [
          for (var i = 1; i <= 7; i++)
            BodyWeightEntry(date: DateTime(2026, 3, i), kg: 80),
        ],
      );
      final earned = statuses.where((s) => s.earned).toList();
      expect(
        ids(earned),
        containsAll([
          'first_set',
          'streak_7',
          'reps_100',
          'pt_1',
          'pr_1',
          'challenge_1',
          'daily_1',
          'weigh_7',
          'early_bird',
        ]),
      );
      for (final s in statuses) {
        if (s.earned) {
          expect(s.earnedAt, isNotNull, reason: s.achievement.id);
          expect(s.earnedAt!.isAfter(now), isFalse, reason: s.achievement.id);
        } else {
          expect(s.earnedAt, isNull, reason: s.achievement.id);
        }
      }
      expect(find(statuses, 'early_bird').earnedAt, now);
      expect(find(statuses, 'reps_100').earnedAt, DateTime(2026, 3, 7, 9, 1));
    });
  });
}
