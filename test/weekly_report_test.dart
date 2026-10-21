import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/engagement/daily_challenge.dart';
import 'package:levelex/core/engagement/weekly_report.dart';
import 'package:levelex/core/levels/level_system.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/strength/models/lift_log.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/workout_session.dart';

var _ids = 0;

WorkoutSession session(
  DateTime at, {
  int reps = 10,
  int target = 10,
  ExerciseType exercise = ExerciseType.pushUp,
  bool verified = true,
  Duration length = const Duration(minutes: 1),
  SessionStatus? status,
}) => WorkoutSession(
  id: 's${_ids++}',
  startTime: at,
  endTime: at.add(length),
  targetReps: target,
  completedReps: reps,
  status:
      status ??
      (reps >= target ? SessionStatus.completed : SessionStatus.incomplete),
  exercise: exercise,
  verified: verified,
);

WorkoutSession skipped(DateTime at) => WorkoutSession(
  id: 'skip${_ids++}',
  startTime: at,
  targetReps: 10,
  completedReps: 0,
  status: SessionStatus.skipped,
);

PtRecord ptRecord(
  DateTime start, {
  Duration length = const Duration(minutes: 30),
  bool verified = true,
  bool finished = true,
}) => PtRecord(
  id: 'pt${_ids++}',
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
      reps: finished ? 30 : 10,
      seconds: 0,
      skipped: false,
    ),
  ],
  verified: verified,
  plannedItems: 1,
);

LiftEntry lift(String id, DateTime at, double kg, int reps) => LiftEntry(
  id: id,
  movementId: 'db_curl',
  startTime: at,
  sets: [LiftSet(weightKg: kg, reps: reps)],
);

void main() {
  final monday = DateTime(2026, 10, 19);
  final wednesday = DateTime(2026, 10, 21, 14);
  assert(monday.weekday == DateTime.monday);

  group('WeeklyReports.weekStartOf', () {
    test('is the Monday at local midnight', () {
      expect(WeeklyReports.weekStartOf(wednesday), monday);
      expect(WeeklyReports.weekStartOf(DateTime(2026, 10, 25, 23, 59)), monday);
      expect(WeeklyReports.weekStartOf(DateTime(2026, 10, 19, 15)), monday);
      expect(
        WeeklyReports.weekStartOf(DateTime(2026, 1, 1)),
        DateTime(2025, 12, 29),
      );
    });
  });

  group('WeeklyReports.build', () {
    final sessions = [
      session(DateTime(2026, 10, 19, 9)), // Mon, completed
      session(
        DateTime(2026, 10, 19, 10),
        reps: 12,
        length: const Duration(minutes: 2),
      ),
      session(
        DateTime(2026, 10, 20, 9),
        reps: 8,
        target: 15,
        exercise: ExerciseType.squat,
      ), // Tue, incomplete
      session(DateTime(2026, 10, 21, 9), verified: false), // Wed, unverified
      session(
        DateTime(2026, 10, 22, 9),
        reps: 30,
        target: 30,
        exercise: ExerciseType.plank,
      ), // Thu, timed
      skipped(DateTime(2026, 10, 23, 9)), // Fri
      session(DateTime(2026, 10, 18, 9)), // previous Sunday
      session(DateTime(2026, 10, 26, 0, 0, 1)), // next Monday
    ];
    final ptRecords = [
      ptRecord(DateTime(2026, 10, 24, 9), finished: false), // Sat, attempted
      ptRecord(DateTime(2026, 10, 25, 9)), // Sun, completed
      ptRecord(DateTime(2026, 10, 17, 9)), // previous week
    ];
    final lifts = [
      lift('l1', DateTime(2026, 10, 12, 9), 20, 10),
      lift('l2', DateTime(2026, 10, 20, 9), 22.5, 10),
      lift('l3', DateTime(2026, 10, 23, 9), 20, 8),
    ];
    final challengeDays = {
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 22),
      DateTime(2026, 10, 15),
    };

    WeeklyReport build({int goal = 4}) => WeeklyReports.build(
      weekOf: wednesday,
      sessions: sessions,
      ptRecords: ptRecords,
      lifts: lifts,
      challengeDays: challengeDays,
      goal: goal,
    );

    test('counts the week only', () {
      final r = build();
      expect(r.weekStart, monday);
      expect(r.weekEnd, DateTime(2026, 10, 25));
      expect(r.workouts, 5);
      expect(r.activeDays, 3);
      expect(r.activeWeekdays, {
        DateTime.monday,
        DateTime.thursday,
        DateTime.sunday,
      });
      expect(r.reps, 10 + 12 + 8 + 10 + 10 + 30);
      expect(r.activeMinutes, 1 + 2 + 1 + 1 + 1 + 30 + 30);
      expect(r.dailyChallenges, 2);
      expect(r.prs, 3);
      final sessionXp = sessions
          .where(
            (s) =>
                s.startTime.month == 10 &&
                s.startTime.day >= 19 &&
                s.startTime.day <= 25,
          )
          .fold(0, (sum, s) => sum + LevelSystem.xpForSession(s));
      expect(sessionXp, 125 + 145 + 48 + 0 + 85);
      final ptXp =
          LevelSystem.xpForPtRecord(ptRecords[0]) +
          LevelSystem.xpForPtRecord(ptRecords[1]);
      expect(ptXp, 260 + 340);
      expect(r.xp, sessionXp + ptXp + 2 * DailyChallenge.bonusXp);
    });

    test('goal progress', () {
      final r = build();
      expect(r.goal, 4);
      expect(r.goalProgress, closeTo(0.75, 1e-9));
      expect(r.goalMet, isFalse);
      final met = build(goal: 3);
      expect(met.goalProgress, 1);
      expect(met.goalMet, isTrue);
      final easy = build(goal: 2);
      expect(easy.goalProgress, 1);
      expect(easy.goalMet, isTrue);
      final none = build(goal: 0);
      expect(none.goalProgress, 1);
      expect(none.goalMet, isTrue);
    });

    test('an empty week is all zeros', () {
      final r = WeeklyReports.build(
        weekOf: DateTime(2026, 5, 6),
        sessions: sessions,
        ptRecords: ptRecords,
        lifts: lifts,
        challengeDays: challengeDays,
        goal: 3,
      );
      expect(r.weekStart, DateTime(2026, 5, 4));
      expect(r.workouts, 0);
      expect(r.activeDays, 0);
      expect(r.activeWeekdays, isEmpty);
      expect(r.reps, 0);
      expect(r.activeMinutes, 0);
      expect(r.xp, 0);
      expect(r.prs, 0);
      expect(r.dailyChallenges, 0);
      expect(r.goalProgress, 0);
      expect(r.goalMet, isFalse);
    });

    test('sessions without an end time add no minutes', () {
      final open = WorkoutSession(
        id: 'open',
        startTime: DateTime(2026, 10, 20, 9),
        targetReps: 10,
        completedReps: 10,
        status: SessionStatus.completed,
      );
      final r = WeeklyReports.build(
        weekOf: wednesday,
        sessions: [open],
        ptRecords: const [],
        lifts: const [],
        challengeDays: const {},
        goal: 3,
      );
      expect(r.workouts, 1);
      expect(r.activeMinutes, 0);
    });
  });

  group('WeeklyReports.consecutiveWeeksMet', () {
    // Weeks of 9/28, 10/5 and 10/12 each have two active days; the current
    // week (10/19, through Wednesday 10/21) has one.
    final past = [
      session(DateTime(2026, 9, 28, 9)),
      session(DateTime(2026, 9, 30, 9)),
      session(DateTime(2026, 10, 6, 9)),
      session(DateTime(2026, 10, 8, 9)),
      session(DateTime(2026, 10, 13, 9)),
      session(DateTime(2026, 10, 15, 9)),
    ];
    final current = session(DateTime(2026, 10, 19, 9));

    int weeks(
      Iterable<WorkoutSession> s, {
      Iterable<PtRecord> pt = const [],
      int goal = 2,
    }) => WeeklyReports.consecutiveWeeksMet(
      through: wednesday,
      sessions: s,
      ptRecords: pt,
      goal: goal,
    );

    test('skips the current week while it is not met yet', () {
      expect(weeks([...past, current]), 3);
      expect(weeks(past), 3);
    });

    test('counts the current week once it is met', () {
      expect(weeks([...past, current, session(DateTime(2026, 10, 21, 9))]), 4);
    });

    test('stops at the first week that missed the goal', () {
      final gap = past.where((s) => s.startTime.day != 8).toList();
      expect(weeks([...gap, current]), 1);
      expect(weeks([...gap, current, session(DateTime(2026, 10, 20, 9))]), 2);
    });

    test('is zero without history or when the last two weeks missed', () {
      expect(weeks(const []), 0);
      expect(weeks([session(DateTime(2026, 10, 1, 9))]), 0);
      expect(weeks([current]), 0);
    });

    test('a completed PT session is an active day', () {
      final gap = past.where((s) => s.startTime.day != 8).toList();
      expect(
        weeks([...gap, current], pt: [ptRecord(DateTime(2026, 10, 9, 18))]),
        3,
      );
      expect(
        weeks(
          [...gap, current],
          pt: [ptRecord(DateTime(2026, 10, 9, 18), finished: false)],
        ),
        1,
      );
    });

    test('multiple sessions on one day are one active day', () {
      expect(
        weeks([
          session(DateTime(2026, 10, 13, 9)),
          session(DateTime(2026, 10, 13, 10)),
          session(DateTime(2026, 10, 13, 11)),
        ]),
        0,
      );
      expect(weeks([session(DateTime(2026, 10, 13, 9))], goal: 1), 1);
      expect(weeks([current], goal: 1), 1);
    });

    test('a goal of zero counts every week back to the first active day', () {
      expect(weeks([session(DateTime(2026, 10, 1, 9))], goal: 0), 4);
    });
  });
}
