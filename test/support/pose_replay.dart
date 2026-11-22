import 'dart:convert';
import 'dart:io';

import 'package:levelex/core/constants/app_constants.dart';
import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/features/workout/analysis/analyzer_factory.dart';
import 'package:levelex/features/workout/push_up_analyzer.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/pose_result.dart';

/// A recorded pose sequence: ML Kit landmarks per frame (as the probe in
/// `tool/pose_probe/` writes them) plus what the frames showed.
class PoseSequence {
  PoseSequence({
    required this.name,
    required this.exercise,
    required this.frames,
    required this.frameMs,
    required this.reps,
    required this.holdSeconds,
    required this.width,
    required this.height,
    required this.gravity,
  });

  /// Loads `<dir>/meta.json` and `<dir>/pose_<model>.jsonl`.
  factory PoseSequence.load(Directory dir, {String model = 'base'}) {
    final meta =
        jsonDecode(File('${dir.path}/meta.json').readAsStringSync()) as Map;
    final lines = File('${dir.path}/pose_$model.jsonl')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .toList();
    return PoseSequence.fromJson(
      dir.path.split('/').last,
      meta.cast<String, Object?>(),
      [for (final l in lines) (jsonDecode(l) as Map).cast<String, Object?>()],
    );
  }

  factory PoseSequence.fromJson(
    String name,
    Map<String, Object?> meta,
    List<Map<String, Object?>> frames,
  ) {
    final g = (meta['gravity'] as List?)?.cast<num>();
    return PoseSequence(
      name: name,
      exercise: ExerciseType.values.byName(meta['exercise']! as String),
      frames: frames,
      frameMs: (meta['frameMs']! as num).toInt(),
      reps: (meta['reps'] as num? ?? 0).toInt(),
      holdSeconds: (meta['holdSeconds'] as num? ?? 0).toInt(),
      width: (meta['width']! as num).toDouble(),
      height: (meta['height']! as num).toDouble(),
      gravity: g == null
          ? null
          : Vec3(g[0].toDouble(), g[1].toDouble(), g[2].toDouble()),
    );
  }

  final String name;
  final ExerciseType exercise;

  /// One map per frame: ML Kit landmark name → [x px, y px, z, likelihood].
  final List<Map<String, Object?>> frames;
  final int frameMs;
  final int reps;
  final int holdSeconds;
  final double width;
  final double height;
  final Vec3? gravity;

  int get framesWithPose => frames.where((f) => f.isNotEmpty).length;

  /// Builds the [PoseResult]s exactly as `PoseDetectionService` does.
  List<PoseResult> poses({bool withGravity = true, int dropEvery = 0}) {
    final start = DateTime(2026, 1, 1, 12);
    final uniform = width > height ? width : height;
    final out = <PoseResult>[];
    for (var i = 0; i < frames.length; i++) {
      final at = start.add(Duration(milliseconds: i * frameMs));
      final g = withGravity ? gravity : null;
      final f = frames[i];
      if (f.isEmpty || (dropEvery > 0 && i % dropEvery == dropEvery - 1)) {
        out.add(PoseResult.empty(at, gravity: g));
        continue;
      }
      final landmarks = <LandmarkType, PoseLandmark>{};
      for (final type in LandmarkType.values) {
        final v = (f[type.name] as List?)?.cast<num>();
        if (v == null) continue;
        final x = v[0].toDouble(), y = v[1].toDouble(), z = v[2].toDouble();
        landmarks[type] = PoseLandmark(
          type: type,
          x: x / width,
          y: y / height,
          position: Vec3(x / uniform, y / uniform, z / uniform),
          likelihood: v[3].toDouble().clamp(0.0, 1.0),
        );
      }
      out.add(PoseResult(landmarks: landmarks, timestamp: at, gravity: g));
    }
    return out;
  }
}

/// What an analyzer made of a sequence.
class ReplayOutcome {
  ReplayOutcome(this.sequence, this.analyzer, this.counted, this.statuses);

  final PoseSequence sequence;
  final ExerciseAnalyzer analyzer;
  final int counted;
  final Map<String, int> statuses;

  /// Reps shown (clips of alternating moves hold two reps per loop), or
  /// for holds the seconds the pose was visible (lead-in and tail too).
  int get expected => sequence.exercise.isTimed
      ? sequence.holdSeconds + 2
      : sequence.reps * repsPerLoop(sequence.exercise) +
            (startsMidRep(sequence.exercise) ? 1 : 0);

  String get summary {
    final top = statuses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final d = analyzer.diagnostics;
    return '${sequence.name.padRight(34)} '
        '${'$counted/$expected'.padLeft(6)}  '
        'pose ${sequence.framesWithPose}/${sequence.frames.length}  '
        '${top.take(3).map((e) => '${e.key}:${e.value}').join(' ')}'
        '${d.rejections.isEmpty ? '' : '  rej ${d.rejections}'}';
  }
}

/// Feeds a sequence to a fresh analyzer for its exercise.
ReplayOutcome replay(
  PoseSequence sequence, {
  PushUpThresholds thresholds = const PushUpThresholds(),
  bool withGravity = true,
  int dropEvery = 0,
}) {
  final analyzer = ExerciseAnalyzerFactory.create(
    sequence.exercise,
    thresholds: thresholds,
    target: 9999,
  );
  final statuses = <String, int>{};
  for (final pose in sequence.poses(
    withGravity: withGravity,
    dropEvery: dropEvery,
  )) {
    final a = analyzer.processPose(pose);
    statuses.update(a.formStatus.name, (v) => v + 1, ifAbsent: () => 1);
  }
  return ReplayOutcome(sequence, analyzer, analyzer.repCount, statuses);
}

/// Reps in one loop of an exercise's guide clip.
int repsPerLoop(ExerciseType type) => switch (type) {
  ExerciseType.lunge ||
  ExerciseType.highKnees ||
  ExerciseType.mountainClimber => 2,
  _ => 1,
};

/// Clips whose first frame is already part of a rep. (High knees and
/// mountain climbers start with one knee driven, but that pose is held
/// before the set starts, so the counter rightly treats it as the start.)
bool startsMidRep(ExerciseType type) => false;
