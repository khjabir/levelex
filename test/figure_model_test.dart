import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/figure_model.dart';
import 'package:levelex/features/pt/mannequin/mannequin_clips.dart';

void main() {
  late FigureModel model;

  setUpAll(() {
    final bytes = File('assets/figure/athlete.glb').readAsBytesSync();
    model = FigureModel.fromGlb(ByteData.sublistView(bytes));
  });

  group('athlete.glb', () {
    test('is a skinned body of a sane size', () {
      expect(model.vertexCount, inInclusiveRange(2000, 40000));
      expect(model.triangleCount, inInclusiveRange(4000, 40000));
      expect(model.skinJoints.length, 21);
      expect(model.warmth.length, model.vertexCount);
      expect(model.warmth.every((w) => w >= 0 && w <= 1), isTrue);
      expect(model.warmth.any((w) => w > 0.3), isTrue);
      final b = model.restBounds;
      expect(b.max.y - b.min.y, inInclusiveRange(1.5, 2.0));
      expect(b.min.y, closeTo(0, 0.08));
    });

    test('names every muscle group material', () {
      final names = {for (final p in model.primitives) p.materialName};
      for (final g in [
        'chest',
        'back',
        'shoulders',
        'biceps',
        'triceps',
        'core',
        'glutes',
        'quads',
        'hamstrings',
        'calves',
        'skin',
        'hair',
        'sclera',
        'iris',
        'shirt',
        'shorts',
      ]) {
        // Muscles under the clothes are named `<garment>.<muscle>`.
        expect(
          names.any((n) => n == g || n.endsWith('.$g')),
          isTrue,
          reason: g,
        );
      }
    });

    test('has every clip as an animation', () {
      for (final id in MannequinClips.ids) {
        expect(model.animations.keys, contains(id), reason: id);
      }
    });

    test('bones match the rig joints', () {
      for (final n in [
        'pelvis',
        'spineLower',
        'spineUpper',
        'upperArmL',
        'forearmR',
        'thighL',
        'shinR',
        'footL',
        'head',
      ]) {
        expect(model.nodeIndex(n), isNot(-1), reason: n);
      }
    });

    test('skinning moves the body with the squat', () {
      model.resetPose();
      model.pose();
      model.skin();
      final rest = Float32List.fromList(model.skinnedPositions);
      model.resetPose();
      model.sample(model.animations['squat']!, 1);
      model.pose();
      model.skin();
      var moved = 0;
      var maxY = 0.0;
      for (var v = 0; v < model.vertexCount; v++) {
        if ((model.skinnedPositions[v * 3 + 1] - rest[v * 3 + 1]).abs() >
            0.02) {
          moved++;
        }
        if (model.skinnedPositions[v * 3 + 1] > maxY) {
          maxY = model.skinnedPositions[v * 3 + 1];
        }
      }
      expect(moved, greaterThan(model.vertexCount ~/ 3));
      // The head is lower at the bottom of a squat than when standing.
      final restTop = model.restBounds.max.y;
      expect(maxY, lessThan(restTop - 0.15));
      // Nothing explodes: every vertex stays within a 2.5 m box.
      for (var v = 0; v < model.vertexCount; v++) {
        for (var k = 0; k < 3; k++) {
          expect(model.skinnedPositions[v * 3 + k].abs(), lessThan(2.5));
        }
      }
    });

    test('applyLife nudges the pose without breaking it', () {
      model.resetPose();
      model.sample(model.animations['stand']!, 0);
      model.pose();
      model.skin();
      final still = Float32List.fromList(model.skinnedPositions);
      model.resetPose();
      model.sample(model.animations['stand']!, 0);
      model.applyLife(1.7, towardCamera: 60);
      model.pose();
      model.skin();
      var maxMove = 0.0;
      var moved = 0;
      for (var v = 0; v < model.vertexCount; v++) {
        final dx = model.skinnedPositions[v * 3] - still[v * 3];
        final dy = model.skinnedPositions[v * 3 + 1] - still[v * 3 + 1];
        final dz = model.skinnedPositions[v * 3 + 2] - still[v * 3 + 2];
        final d = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d > maxMove) maxMove = d;
        if (d > 0.002) moved++;
      }
      expect(moved, greaterThan(100));
      // Subtle: nothing moves more than a few centimetres.
      expect(maxMove, lessThan(0.08));
    });

    test('idle head turn faces the camera side', () {
      (double, double) nose() {
        model.pose();
        model.skin();
        final pos = model.skinnedPositions;
        var top = -1e9;
        for (var v = 0; v < model.vertexCount; v++) {
          if (pos[v * 3 + 1] > top) top = pos[v * 3 + 1];
        }
        var best = -1;
        var bestZ = -1e9;
        for (var v = 0; v < model.vertexCount; v++) {
          if (pos[v * 3 + 1] < top - 0.3) continue;
          if (pos[v * 3 + 2] > bestZ) {
            bestZ = pos[v * 3 + 2];
            best = v;
          }
        }
        return (pos[best * 3], pos[best * 3 + 2]);
      }

      model.resetPose();
      model.sample(model.animations['stand']!, 0);
      final still = nose();
      model.resetPose();
      model.sample(model.animations['stand']!, 0);
      // A camera yaw of -60 puts the camera on the body's right (-x).
      model.applyLife(0, towardCamera: -60);
      final turned = nose();
      expect(turned.$1, lessThan(still.$1 - 0.02));
    });

    test('sampleBlend mixes two movements', () {
      final squat = model.animations['squat']!;
      final press = model.animations['shoulder_press']!;
      Float32List snapshot() {
        model.pose();
        model.skin();
        return Float32List.fromList(model.skinnedPositions);
      }

      model.sampleBlend(squat, 1, press, 1, 0);
      final a = snapshot();
      model.sampleBlend(squat, 1, press, 1, 1);
      final b = snapshot();
      model.sampleBlend(squat, 1, press, 1, 0.5);
      final mid = snapshot();
      model.resetPose();
      model.sample(squat, 1);
      final pureA = snapshot();
      model.resetPose();
      model.sample(press, 1);
      final pureB = snapshot();
      var differ = 0;
      for (var i = 0; i < a.length; i += 3) {
        expect(a[i], closeTo(pureA[i], 1e-5));
        expect(b[i], closeTo(pureB[i], 1e-5));
        // Rotations blend on arcs, so a midpoint can leave the straight
        // line between the two poses by a few centimetres.
        final lo = math.min(a[i], b[i]) - 0.15;
        final hi = math.max(a[i], b[i]) + 0.15;
        expect(mid[i], inInclusiveRange(lo, hi));
        if ((a[i] - b[i]).abs() > 0.05) differ++;
      }
      expect(differ, greaterThan(100));
    });

    test('sampling at a keyframe matches the key, between keys blends', () {
      final a = model.animations['push_up']!;
      expect(a.duration, greaterThan(0));
      model.resetPose();
      model.sample(a, 0);
      model.pose();
      model.skin();
      final top = Float32List.fromList(model.skinnedPositions);
      model.resetPose();
      model.sample(a, 0.5);
      model.pose();
      model.skin();
      final mid = Float32List.fromList(model.skinnedPositions);
      model.resetPose();
      model.sample(a, 1);
      model.pose();
      model.skin();
      final bottom = model.skinnedPositions;
      var between = 0;
      for (var v = 0; v < model.vertexCount; v += 25) {
        final y = mid[v * 3 + 1];
        final lo = top[v * 3 + 1] < bottom[v * 3 + 1]
            ? top[v * 3 + 1]
            : bottom[v * 3 + 1];
        final hi = top[v * 3 + 1] < bottom[v * 3 + 1]
            ? bottom[v * 3 + 1]
            : top[v * 3 + 1];
        if (y >= lo - 0.03 && y <= hi + 0.03) between++;
      }
      expect(between, greaterThan((model.vertexCount ~/ 25) * 0.9));
    });
  });
}
