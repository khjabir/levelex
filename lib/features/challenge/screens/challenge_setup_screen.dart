import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../models/exercise.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../../pt/figure/guide_3d.dart';
import '../../workout/exercise_icons.dart';
import '../challenge_providers.dart';
import '../models/challenge.dart';
import 'player_avatar.dart';

/// Set up a quick challenge: who plays, which exercise, how it is scored.
class ChallengeSetupScreen extends ConsumerStatefulWidget {
  const ChallengeSetupScreen({super.key});

  @override
  ConsumerState<ChallengeSetupScreen> createState() =>
      _ChallengeSetupScreenState();
}

class _ChallengeSetupScreenState extends ConsumerState<ChallengeSetupScreen> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();

  static const timedOptions = [30, 45, 60, 90];
  static const targetOptions = [10, 20, 30, 50];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addPlayer() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    ref.read(challengeConfigProvider.notifier).addPlayer(name);
    _nameController.clear();
  }

  Future<void> _photoFor(ChallengePlayer player) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            if (player.photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () {
                  ref
                      .read(challengeConfigProvider.notifier)
                      .setPhoto(player.id, null);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 600,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
    } catch (e) {
      debugPrint('Player photo failed: $e');
    }
    if (file == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/players');
      await folder.create(recursive: true);
      final target = File(
        '${folder.path}/${player.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(file.path).copy(target.path);
      ref
          .read(challengeConfigProvider.notifier)
          .setPhoto(player.id, target.path);
    } catch (e) {
      debugPrint('Saving player photo failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(challengeConfigProvider);
    final notifier = ref.read(challengeConfigProvider.notifier);
    final records = ref.watch(challengeRecordsProvider);
    final options = config.mode == ChallengeMode.timed
        ? timedOptions
        : targetOptions;
    return Scaffold(
      appBar: AppBar(title: const Text('Challenge')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children:
                    [
                          AppCard(
                            glow: true,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.emoji_events_rounded,
                                  color: AppColors.warning,
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Take turns in front of the camera. Reps '
                                    'are counted and coached the same way for '
                                    'everyone, and the winner takes the cup. '
                                    'Challenge rounds never touch your own '
                                    'streak or XP.',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const SectionHeader('Players'),
                          AppCard(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            child: Column(
                              children: [
                                for (final p in config.players)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: GestureDetector(
                                      onTap: () => _photoFor(p),
                                      child: PlayerAvatar(player: p, size: 44),
                                    ),
                                    title: Text(p.name),
                                    subtitle: Text(
                                      p.photoPath == null
                                          ? 'Tap the avatar to add a photo'
                                          : 'Photo added',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Remove ${p.name}',
                                      onPressed: () =>
                                          notifier.removePlayer(p.id),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _nameController,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        decoration: const InputDecoration(
                                          hintText: 'Add a player by name',
                                          isDense: true,
                                        ),
                                        onSubmitted: (_) => _addPlayer(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      onPressed: _addPlayer,
                                      icon: const Icon(Icons.add),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          const SectionHeader('Exercise'),
                          SizedBox(
                            height: 118,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: ExerciseType.values.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final type = ExerciseType.values[i];
                                final selected = config.exercise == type;
                                return GestureDetector(
                                  onTap: () => notifier.update(
                                    (c) => c.copyWith(
                                      exercise: type,
                                      // Holds are "longest hold" in target
                                      // mode; keep the value sensible.
                                      value:
                                          type.isTimed &&
                                              c.mode == ChallengeMode.target
                                          ? 60
                                          : c.value,
                                    ),
                                  ),
                                  child: AnimatedContainer(
                                    duration: AppTokens.normal,
                                    width: 104,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary.withValues(
                                              alpha: 0.12,
                                            )
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : Colors.white.withValues(
                                                alpha: 0.06,
                                              ),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Guide3D(
                                            clipId: type.clipId,
                                            playing: selected,
                                            interactive: false,
                                            autoRotate: false,
                                            showFloor: false,
                                            compact: true,
                                          ),
                                        ),
                                        Text(
                                          type.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: selected
                                                    ? AppColors.primary
                                                    : AppColors.textPrimary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 22),
                          const SectionHeader('Rules'),
                          SegmentedButton<ChallengeMode>(
                            segments: [
                              for (final m in ChallengeMode.values)
                                ButtonSegment(value: m, label: Text(m.label)),
                            ],
                            selected: {config.mode},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) => notifier.update(
                              (c) => c.copyWith(
                                mode: s.first,
                                value: s.first == ChallengeMode.timed
                                    ? 30
                                    : (c.exercise.isTimed ? 60 : 20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final v in options)
                                ChoiceChip(
                                  label: Text(
                                    config.mode == ChallengeMode.timed ||
                                            config.exercise.isTimed
                                        ? '$v s'
                                        : '$v reps',
                                  ),
                                  selected: config.value == v,
                                  onSelected: (_) => notifier.update(
                                    (c) => c.copyWith(value: v),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            config.describe,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          if (records.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            const SectionHeader('Hall of fame'),
                            AppCard(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < records.length && i < 6;
                                    i++
                                  ) ...[
                                    if (i > 0)
                                      const Divider(indent: 20, endIndent: 20),
                                    _RecordTile(record: records[i]),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ]
                        .animate(interval: 40.ms)
                        .fadeIn(duration: 280.ms)
                        .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!config.ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Add at least two players to start.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  PrimaryButton(
                    label: 'START CHALLENGE',
                    icon: Icons.emoji_events_rounded,
                    onPressed: config.ready
                        ? () => context.push(Routes.challengePlay)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final ChallengeRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = record.winner;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: w == null
          ? const Icon(Icons.emoji_events_outlined)
          : PlayerAvatar(player: w.player, size: 40, crowned: true),
      title: Text(
        w == null
            ? 'No scores'
            : record.tie
            ? 'Tie: ${record.scores[0].player.name} & ${record.scores[1].player.name}'
            : '${w.player.name} won',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        '${record.exercise.label} · ${w?.reps ?? 0} '
        '${record.exercise.countLabel(w?.reps ?? 0)} · '
        '${DateFormat.MMMd().format(record.date)}',
      ),
    );
  }
}
