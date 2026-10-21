import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';
import 'package:levelex/features/pt/mannequin/rig.dart';
import 'package:levelex/features/pt/models/movement_library.dart';

void main() {
  group('MannequinClip timing', () {
    test('reps ease into every key, circles run at constant speed', () {
      final squat = MannequinClips.clip('squat');
      final circles = MannequinClips.clip('arm_circles');
      expect(circles.continuous, isTrue);
      expect(squat.continuous, isFalse);
      final d = squat.durations.first;
      final down = (d * MannequinClip.eccentricFactor).round();
      final up = (d * MannequinClip.concentricFactor).round();
      // Eased: a quarter of the way down is well short of a quarter.
      expect(squat.framePosition(down ~/ 4), lessThan(0.12));
      expect(squat.framePosition(down ~/ 4), greaterThan(0.0));
      // Half way through the segment is exactly the middle.
      expect(squat.framePosition(down ~/ 2), closeTo(0.5, 0.02));
      final dc = circles.durations.first;
      expect(circles.framePosition(dc ~/ 4), closeTo(0.25, 0.02));
      // The way back up is quicker than the way down.
      expect(squat.totalMs, down + up);
      expect(up, lessThan(down));
      expect(squat.framePosition(down + up ~/ 2), closeTo(0.5, 0.02));
      expect(circles.framePosition(circles.totalMs - 1), closeTo(0.0, 0.05));
    });
  });

  group('MannequinFrame', () {
    test('a push-up clip is low and wide, a standing clip tall and narrow', () {
      final stand = MannequinFrame.ofClip(MannequinClips.clip('stand'));
      final push = MannequinFrame.ofClip(MannequinClips.clip('push_up'));
      expect(stand.height, greaterThan(1.5));
      expect(push.height, lessThan(stand.height * 0.6));
      expect(push.halfWidth, greaterThan(stand.halfWidth));
    });

    test('covers every keyframe of a clip', () {
      final jack = MannequinClips.clip('jumping_jack');
      final whole = MannequinFrame.ofClip(jack);
      for (final f in jack.frames) {
        final one = MannequinFrame.ofPoses([f]);
        expect(whole.height, greaterThanOrEqualTo(one.height - 1e-9));
        expect(whole.halfWidth, greaterThanOrEqualTo(one.halfWidth - 1e-9));
      }
    });
  });

  group('Rig', () {
    test('standing figure has feet on the floor and head on top', () {
      final j = Rig.solve(const RigPose.sym());
      expect(j['ankleL']!.y, closeTo(0.03, 0.08));
      expect(j['head']!.y, greaterThan(1.5));
      expect(j['head']!.y, lessThan(1.9));
      // Arms hang by the sides.
      expect(j['wristL']!.y, lessThan(j['shoulderL']!.y));
    });

    test('a plank is horizontal with hands and toes near the floor', () {
      final j = Rig.solve(MannequinClips.clip('push_up').frames.first);
      expect(j['wristL']!.y, lessThan(0.12));
      expect(j['toeL']!.y, lessThan(0.12));
      final torsoDy = (j['chest']!.y - j['pelvis']!.y).abs();
      final torsoDz = (j['chest']!.z - j['pelvis']!.z).abs();
      expect(torsoDz, greaterThan(torsoDy));
    });

    test('a squat lowers the pelvis', () {
      final stand = Rig.solve(const RigPose.sym());
      final bottom = Rig.solve(MannequinClips.clip('squat').frames.last);
      expect(bottom['pelvis']!.y, lessThan(stand['pelvis']!.y - 0.2));
    });

    test('mirrored pose swaps sides', () {
      const p = RigPose(hipFlexL: 80, kneeL: 90);
      final m = p.mirrored;
      expect(m.hipFlexR, 80);
      expect(m.kneeR, 90);
      expect(m.hipFlexL, 0);
    });

    test('clips interpolate smoothly and loop', () {
      final clip = MannequinClips.clip('curl');
      final start = clip.at(0);
      final mid = clip.at(clip.totalMs ~/ 4);
      final back = clip.at(clip.totalMs);
      expect(mid.elbowL, greaterThan(start.elbowL));
      expect(back.elbowL, closeTo(start.elbowL, 1e-6));
    });

    test('every movement has a mannequin clip', () {
      for (final m in MovementLibrary.all) {
        expect(
          MannequinClips.has(m.clip),
          isTrue,
          reason: '${m.id}: ${m.clip}',
        );
      }
    });

    test('every clip solves to finite positions', () {
      for (final id in MannequinClips.ids) {
        final clip = MannequinClips.clip(id);
        for (var t = 0; t < clip.totalMs; t += clip.totalMs ~/ 5 + 1) {
          final joints = Rig.solve(clip.at(t));
          for (final v in joints.values) {
            expect(v.x.isFinite && v.y.isFinite && v.z.isFinite, isTrue);
            expect(v.y, greaterThanOrEqualTo(-0.2), reason: id);
          }
        }
      }
    });
  });
}
