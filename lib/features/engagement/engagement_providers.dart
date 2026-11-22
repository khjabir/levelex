import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/engagement/achievements.dart';
import '../../core/engagement/daily_challenge.dart';
import '../../core/engagement/personal_best.dart';
import '../../core/engagement/weekly_report.dart';
import '../../core/levels/level_system.dart';
import '../../core/utils/date_utils.dart';
import '../../models/exercise.dart';
import '../challenge/challenge_providers.dart';
import '../pt/pt_providers.dart';
import '../strength/strength_providers.dart';

// -----------------------------------------------------------------------------
// Daily challenge
// -----------------------------------------------------------------------------

/// Today's challenge, scaled to the level at the start of today (so it does
/// not move while you are doing it).
final dailyChallengeProvider = Provider<DailyChallenge>((ref) {
  final now = ref.watch(clockProvider);
  final today = AppDateUtils.dateOnly(now);
  final sessions = ref.watch(sessionsProvider);
  final pt = ref.watch(ptRecordsProvider);
  final before = [
    for (final s in sessions)
      if (s.startTime.isBefore(today)) s,
  ];
  final ptBefore = [
    for (final r in pt)
      if (r.startTime.isBefore(today)) r,
  ];
  final days = ref.watch(dailyChallengeDaysProvider);
  final bonus = DailyChallenges.bonusXp({
    for (final d in days)
      if (d.isBefore(today)) d,
  });
  final level = LevelSystem.levelFor(
    LevelSystem.totalXp(before, ptRecords: ptBefore) + bonus,
  ).level;
  return DailyChallenges.forDay(today, level: level);
});

final dailyChallengeProgressProvider = Provider<DailyChallengeProgress>(
  (ref) => DailyChallenges.progress(
    ref.watch(dailyChallengeProvider),
    ref.watch(sessionsProvider),
  ),
);

final dailyChallengeStreakProvider = Provider<int>(
  (ref) => DailyChallenges.streak(
    ref.watch(dailyChallengeDaysProvider),
    ref.watch(clockProvider),
  ),
);

// -----------------------------------------------------------------------------
// Personal bests
// -----------------------------------------------------------------------------

final personalBestsProvider = Provider<Map<ExerciseType, PersonalBest>>(
  (ref) => PersonalBests.all(ref.watch(sessionsProvider)),
);

// -----------------------------------------------------------------------------
// Weekly report
// -----------------------------------------------------------------------------

WeeklyReport _report(Ref ref, DateTime weekOf) => WeeklyReports.build(
  weekOf: weekOf,
  sessions: ref.watch(sessionsProvider),
  ptRecords: ref.watch(ptRecordsProvider),
  lifts: ref.watch(liftLogProvider),
  challengeDays: ref.watch(dailyChallengeDaysProvider),
  goal: ref.watch(settingsProvider.select((s) => s.weeklyGoal)),
);

final thisWeekReportProvider = Provider<WeeklyReport>(
  (ref) => _report(ref, ref.watch(clockProvider)),
);

final lastWeekReportProvider = Provider<WeeklyReport>(
  (ref) => _report(ref, AppDateUtils.addDays(ref.watch(clockProvider), -7)),
);

final weeksMetProvider = Provider<int>(
  (ref) => WeeklyReports.consecutiveWeeksMet(
    through: ref.watch(clockProvider),
    sessions: ref.watch(sessionsProvider),
    ptRecords: ref.watch(ptRecordsProvider),
    goal: ref.watch(settingsProvider.select((s) => s.weeklyGoal)),
  ),
);

// -----------------------------------------------------------------------------
// Achievements
// -----------------------------------------------------------------------------

final achievementsProvider = Provider<List<AchievementStatus>>((ref) {
  final settings = ref.watch(settingsProvider);
  return Achievements.evaluate(
    AchievementInput(
      sessions: ref.watch(sessionsProvider),
      ptRecords: ref.watch(ptRecordsProvider),
      lifts: ref.watch(liftLogProvider),
      bodyWeights: ref.watch(bodyWeightProvider),
      challenges: ref.watch(challengeRecordsProvider),
      dailyChallengeDays: ref.watch(dailyChallengeDaysProvider),
      weeklyGoal: settings.weeklyGoal,
      restWeekdays: settings.restWeekdays,
      now: ref.watch(clockProvider),
    ),
  );
});

final earnedAchievementCountProvider = Provider<int>(
  (ref) => ref.watch(achievementsProvider).where((a) => a.earned).length,
);

/// Earned badges the user has not been shown yet.
final newAchievementsProvider = Provider<List<AchievementStatus>>((ref) {
  final seen = ref.watch(settingsProvider.select((s) => s.achievementsSeen));
  return Achievements.newlyEarned(ref.watch(achievementsProvider), seen);
});

/// The badges that were new when a result screen first showed them, kept
/// for that screen (keyed by the session or record id) after they are
/// marked seen; watching [newAchievementsProvider] directly made them
/// vanish one frame after appearing.
final newBadgesShownProvider = Provider.autoDispose
    .family<List<AchievementStatus>, String>(
      (ref, occasion) => ref.read(newAchievementsProvider),
    );

/// Marks every currently earned badge as seen.
final markAchievementsSeenProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final earned = {
      for (final a in ref.read(achievementsProvider))
        if (a.earned) a.achievement.id,
    };
    final current = ref.read(settingsProvider).achievementsSeen;
    if (current.containsAll(earned)) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWith(achievementsSeen: {...current, ...earned}),
        );
  };
});
