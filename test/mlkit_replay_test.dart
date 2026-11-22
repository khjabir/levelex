import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/pose_replay.dart';

/// Regression test on real detector output: Google ML Kit (the app's pose
/// detector, base model, stream mode) run on rendered videos of the 3D
/// athlete doing every camera-tracked exercise, filmed from the side, the
/// front and a diagonal. Each sequence holds four reps (eight knee drives
/// or lunges for the alternating moves) or a hold of ~9 s.
///
/// Regenerate with `test/preview/pose_frames_test.dart` (frames),
/// `tool/pose_probe/` (ML Kit on an emulator) and
/// `test/preview/pose_replay_test.dart` (report).
void main() {
  final doc = jsonDecode(
    utf8.decode(
      gzip.decode(
        File('test/fixtures/mlkit_pose_sequences.json.gz').readAsBytesSync(),
      ),
    ),
  ) as Map<String, dynamic>;

  group('ML Kit recordings', () {
    for (final entry in doc.entries) {
      final data = entry.value as Map<String, dynamic>;
      test(entry.key, () {
        final seq = PoseSequence.fromJson(
          entry.key,
          (data['meta'] as Map).cast<String, Object?>(),
          [
            for (final f in data['frames'] as List)
              (f as Map).cast<String, Object?>(),
          ],
        );
        final out = replay(seq);
        if (seq.exercise.isTimed) {
          expect(out.counted, closeTo(out.expected, 1), reason: out.summary);
        } else {
          expect(out.counted, out.expected, reason: out.summary);
        }
      });
    }
  });
}
