import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/workout/analysis/analyzer_factory.dart';
import 'package:levelex/core/constants/app_constants.dart';

import '../support/pose_replay.dart';

/// Replays recorded ML Kit sequences through the analyzers and prints how
/// many reps each one counted.
///
/// `POSE_REPLAY=frames_dir [POSE_MODEL=accurate] [POSE_TRACE=sequence]
/// flutter test test/preview/pose_replay_test.dart`
void main() {
  final root = Platform.environment['POSE_REPLAY'];
  final model = Platform.environment['POSE_MODEL'] ?? 'base';
  final trace = Platform.environment['POSE_TRACE'];

  test('replay recorded sequences', () {
    final dirs =
        Directory(root!)
            .listSync()
            .whereType<Directory>()
            .where((d) => File('${d.path}/pose_$model.jsonl').existsSync())
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    var ok = 0;
    var total = 0;
    final lines = <String>[];
    for (final dir in dirs) {
      final seq = PoseSequence.load(dir, model: model);
      if (trace != null && seq.name == trace) _trace(seq);
      final out = replay(seq);
      total++;
      final good = seq.exercise.isTimed
          ? (out.counted - out.expected).abs() <= 1
          : out.counted == out.expected;
      if (good) ok++;
      lines.add('${good ? '  ' : '✗ '}${out.summary}');
    }
    // ignore: avoid_print
    print('[replay $model] $ok/$total sequences right\n${lines.join('\n')}');
  }, skip: root == null ? 'Set POSE_REPLAY to replay' : false);
}

void _trace(PoseSequence seq) {
  final analyzer = ExerciseAnalyzerFactory.create(
    seq.exercise,
    thresholds: const PushUpThresholds(),
    target: 9999,
  );
  var i = 0;
  for (final pose in seq.poses()) {
    final a = analyzer.processPose(pose);
    // ignore: avoid_print
    print(
      '${i.toString().padLeft(3)} ${a.trackQuality.name.padRight(10)} '
      '${a.phase.name.padRight(9)} ${a.formStatus.name.padRight(14)} '
      'sig ${a.signal?.toStringAsFixed(2) ?? '-'} '
      'rest ${a.restThreshold?.toStringAsFixed(1) ?? '-'} '
      'work ${a.workThreshold?.toStringAsFixed(1) ?? '-'} '
      'tilt ${a.bodyTilt?.toStringAsFixed(0) ?? '-'} '
      'reps ${a.repCount}${a.rejection != null ? ' ${a.rejection!.name}' : ''}',
    );
    i++;
  }
}
