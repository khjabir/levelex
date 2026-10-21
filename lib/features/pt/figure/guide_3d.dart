import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/device/device_memory.dart';
import '../../../models/exercise.dart';
import '../../../models/user_settings.dart';
import '../../strength/logic/recovery.dart';
import '../../workout/exercise_icons.dart';
import '../mannequin/mannequin_3d.dart';
import '../models/movement_library.dart';
import '../models/muscle_group.dart';
import 'figure_3d.dart';
import 'figure_painter.dart';

/// Whether the detailed body should be used: the user's choice, or in Auto
/// the device's memory (lite on low-RAM phones).
final guideDetailedProvider = Provider<bool>((ref) {
  final quality = ref.watch(settingsProvider.select((s) => s.guideQuality));
  switch (quality) {
    case GuideQuality.detailed:
      return true;
    case GuideQuality.lite:
      return false;
    case GuideQuality.auto:
      final memory = ref.watch(deviceMemoryProvider).value;
      return memory?.detailedGuideOk ?? true;
  }
});

/// The movement guide: the detailed skinned body with the working muscles
/// lit, or the lite capsule mannequin on low-memory devices. Same contract
/// as [Mannequin3D]; the muscles come from the clip's movement.
class Guide3D extends ConsumerWidget {
  const Guide3D({
    super.key,
    required this.clipId,
    this.size,
    this.playing = true,
    this.interactive = true,
    this.autoRotate = true,
    this.initialYaw = -38,
    this.initialPitch = 14,
    this.highlight = const {},
    this.showFloor = true,
    this.compact = false,
    this.primary,
    this.secondary,
  });

  final String clipId;
  final double? size;
  final bool playing;
  final bool interactive;
  final bool autoRotate;
  final double initialYaw;
  final double initialPitch;
  final Set<String> highlight;
  final bool showFloor;
  final bool compact;

  /// Muscles to light up; when null they are looked up from the clip.
  final Set<MuscleGroup>? primary;
  final Set<MuscleGroup>? secondary;

  /// Muscles a clip trains, from the movement library or the camera
  /// exercise that shares the clip.
  static ({Set<MuscleGroup> primary, Set<MuscleGroup> secondary}) musclesFor(
    String clipId,
  ) {
    for (final m in MovementLibrary.all) {
      if (m.clip == clipId) return (primary: m.primary, secondary: m.secondary);
    }
    for (final t in ExerciseType.values) {
      if (t.clipId == clipId) {
        final e = MuscleRecovery.exerciseMuscles[t];
        if (e != null) return (primary: e.primary, secondary: e.secondary);
      }
    }
    return (primary: const {}, secondary: const {});
  }

  /// Muscle groups the body has a material for (cardio and mobility are
  /// not muscles).
  static const bodyGroups = {
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.biceps,
    MuscleGroup.triceps,
    MuscleGroup.core,
    MuscleGroup.glutes,
    MuscleGroup.quads,
    MuscleGroup.hamstrings,
    MuscleGroup.calves,
  };

  /// Material → strength. Secondary muscles glow at half strength, unless
  /// the movement's primary groups are cardio or mobility only, in which
  /// case the secondary muscles are the ones doing the work and light up
  /// fully (jumping jacks, high knees, the bike…).
  static MuscleEmphasis emphasisFor(
    Set<MuscleGroup> primary,
    Set<MuscleGroup> secondary,
  ) {
    final primaryBody = primary.where(bodyGroups.contains);
    final secondaryWeight = primaryBody.isEmpty ? 1.0 : 0.45;
    return {
      for (final g in secondary)
        if (bodyGroups.contains(g)) g.name: secondaryWeight,
      for (final g in primaryBody) g.name: 1.0,
    };
  }

  /// Mannequin parts for the lite guide: the body regions that hold the
  /// working muscles.
  static Set<String> litePartsFor(MuscleEmphasis emphasis) => {
    for (final e in emphasis.entries)
      if (e.value >= 0.45)
        switch (e.key) {
          'chest' || 'back' || 'core' => 'torso',
          'glutes' => 'hips',
          'shoulders' || 'biceps' || 'triceps' => 'arms',
          'quads' || 'hamstrings' || 'calves' => 'legs',
          _ => 'torso',
        },
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailed = ref.watch(guideDetailedProvider);
    final muscles = primary == null
        ? musclesFor(clipId)
        : (primary: primary!, secondary: secondary ?? const <MuscleGroup>{});
    final emphasis = emphasisFor(muscles.primary, muscles.secondary);
    if (!detailed) {
      return Mannequin3D(
        clipId: clipId,
        size: size,
        playing: playing,
        interactive: interactive,
        autoRotate: autoRotate,
        initialYaw: initialYaw,
        initialPitch: initialPitch,
        highlight: highlight,
        emphasis: litePartsFor(emphasis),
        showFloor: showFloor,
        compact: compact,
      );
    }
    return Figure3D(
      clipId: clipId,
      size: size,
      playing: playing,
      interactive: interactive,
      autoRotate: autoRotate,
      initialYaw: initialYaw,
      initialPitch: initialPitch,
      highlight: highlight,
      emphasis: emphasis,
      showFloor: showFloor,
      compact: compact,
    );
  }
}
