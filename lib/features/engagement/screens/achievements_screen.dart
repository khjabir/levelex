import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/engagement/achievements.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/badge_tile.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/share_card.dart';
import '../../../widgets/share_sheet.dart';
import '../engagement_providers.dart';

/// The trophy room: every badge, earned or in progress, by category.
class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the room clears the "new" markers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(markAchievementsSeenProvider)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuses = ref.watch(achievementsProvider);
    final earned = statuses.where((s) => s.earned).toList();
    final byCategory = <AchievementCategory, List<AchievementStatus>>{};
    for (final s in statuses) {
      byCategory.putIfAbsent(s.achievement.category, () => []).add(s);
    }
    final next = statuses.where((s) => !s.earned).take(3).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  AppCard(
                    glow: earned.isNotEmpty,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${earned.length} of ${statuses.length} badges',
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                earned.isEmpty
                                    ? 'Your first set earns the first one.'
                                    : 'Latest: ${earned.first.achievement.title}'
                                          '${earned.first.earnedAt != null ? ' · ${DateFormat.MMMd().format(earned.first.earnedAt!)}' : ''}',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.emoji_events_rounded,
                          size: 42,
                          color: AppColors.warning,
                        ),
                      ],
                    ),
                  ),
                  if (next.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const SectionHeader('Closest'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < next.length; i++) ...[
                            if (i > 0) const Divider(indent: 16, endIndent: 16),
                            ListTile(
                              dense: true,
                              minLeadingWidth: 48,
                              leading: SizedBox(
                                width: 48,
                                height: 48,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: BadgeTile(
                                      title: '',
                                      icon: next[i].achievement.icon,
                                      tier: next[i].achievement.tier.name,
                                      progress: next[i].progress,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(next[i].achievement.title),
                              subtitle: Text(
                                '${next[i].achievement.description} · '
                                '${next[i].current}/${next[i].achievement.target}',
                              ),
                              onTap: () => _detail(next[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  for (final c in AchievementCategory.values)
                    if (byCategory[c] != null) ...[
                      const SizedBox(height: 20),
                      SectionHeader(
                        '${c.label} · '
                        '${byCategory[c]!.where((s) => s.earned).length}/${byCategory[c]!.length}',
                      ),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        // Room for two title lines and the progress line,
                        // taller as the text grows.
                        childAspectRatio:
                            0.7 /
                            MediaQuery.textScalerOf(context)
                                .scale(1)
                                .clamp(1.0, 2.0),
                        children: [
                          for (final s in byCategory[c]!)
                            BadgeTile(
                              title: s.achievement.title,
                              icon: s.achievement.icon,
                              tier: s.achievement.tier.name,
                              earned: s.earned,
                              progress: s.progress,
                              subtitle: s.earned
                                  ? (s.earnedAt == null
                                        ? null
                                        : DateFormat.MMMd().format(s.earnedAt!))
                                  : '${s.current}/${s.achievement.target}',
                              onTap: () => _detail(s),
                            ),
                        ],
                      ),
                    ],
                ]
                .animate(interval: 30.ms)
                .fadeIn(duration: 240.ms)
                .slideY(begin: 0.03, end: 0, curve: AppTokens.curve),
      ),
    );
  }

  Future<void> _detail(AchievementStatus s) async {
    final today = ref.read(clockProvider);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                child: BadgeTile(
                  title: '',
                  icon: s.achievement.icon,
                  tier: s.achievement.tier.name,
                  earned: s.earned,
                  progress: s.progress,
                  large: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.achievement.title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                s.achievement.description,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                s.earned
                    ? 'Earned${s.earnedAt != null ? ' ${DateFormat.yMMMd().format(s.earnedAt!)}' : ''} · ${s.achievement.tier.label}'
                    : '${s.current} of ${s.achievement.target} · ${s.achievement.tier.label}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: s.earned ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              if (s.earned) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showShareSheet(
                      this.context,
                      ShareCardData(
                        headline: 'BADGE EARNED',
                        title: s.achievement.title,
                        subtitle: s.achievement.description,
                        date: s.earnedAt ?? today,
                        stats: [
                          ShareStat(
                            label: 'Tier',
                            value: s.achievement.tier.label,
                          ),
                          ShareStat(
                            label: 'Category',
                            value: s.achievement.category.label,
                          ),
                        ],
                        accent: 'warning',
                      ),
                    );
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
