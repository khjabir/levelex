import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/constants/app_constants.dart';
import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/features/workout/analysis/analyzer_factory.dart';
import 'package:levelex/features/workout/analysis/floor_analyzers.dart';
import 'package:levelex/features/workout/analysis/leg_analyzers.dart';
import 'package:levelex/features/workout/analysis/plank_analyzer.dart';
import 'package:levelex/features/workout/push_up_analyzer.dart';
import 'package:levelex/models/exercise.dart';
import 'package:levelex/models/form_status.dart';
import 'package:levelex/models/pose_result.dart';

import 'support/synthetic_bodies.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Push-ups
  // ---------------------------------------------------------------------------
  for (final (name, view) in [
    ('side view', View.side),
    ('front view', View.front),
    ('elevated front view', View.elevated),
  ]) {
    group('PushUpAnalyzer from the $name', () {
      test('UP DOWN UP counts one rep', () {
        final a = PushUpAnalyzer();
        final d = Driver(a, view: view);
        d.settle(Body.pushUp(170));
        expect(d.last!.phase, CyclePhase.rest);
        d.phase(Body.pushUp(80));
        expect(d.last!.phase, CyclePhase.work);
        d.phase(Body.pushUp(170));
        expect(a.repCount, 1);
        expect(d.last!.formStatus, FormStatus.goodForm);
        expect(d.last!.inPosition, isTrue);
      });

      test('five reps with depth noise are all counted', () {
        final a = PushUpAnalyzer();
        final d = Driver(a, view: view, depthNoise: 0.04);
        d.settle(Body.pushUp(170));
        for (var i = 0; i < 5; i++) {
          d.phase(Body.pushUp(80));
          d.phase(Body.pushUp(170));
        }
        expect(a.repCount, 5);
      });

      test('works without a motion sensor', () {
        final a = PushUpAnalyzer();
        final d = Driver(a, view: view, withGravity: false);
        d.settle(Body.pushUp(170));
        d.phase(Body.pushUp(80));
        d.phase(Body.pushUp(170));
        d.phase(Body.pushUp(80));
        d.phase(Body.pushUp(170));
        expect(a.repCount, 2);
      });

      test('UP UP UP counts zero', () {
        final a = PushUpAnalyzer();
        final d = Driver(a, view: view);
        d.settle(Body.pushUp(170));
        d.phase(Body.pushUp(170));
        d.phase(Body.pushUp(170));
        expect(a.repCount, 0);
      });
    });
  }

  group('PushUpAnalyzer tolerance', () {
    test('a rep that stops at 105° still counts with default thresholds', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(165));
      d.phase(Body.pushUp(105));
      expect(d.last!.phase, CyclePhase.work);
      d.phase(Body.pushUp(165));
      expect(a.repCount, 1);
    });

    test('relaxed strictness counts an even shallower rep', () {
      final a = PushUpAnalyzer(
        thresholds: PushUpThresholds.forSensitivity(FormSensitivity.low),
      );
      final d = Driver(a);
      d.settle(Body.pushUp(165));
      d.phase(Body.pushUp(115));
      d.phase(Body.pushUp(165));
      expect(a.repCount, 1);
    });

    test('a half rep is not counted but the coach says go lower', () {
      final a = PushUpAnalyzer(
        thresholds: const PushUpThresholds(adaptiveThresholds: false),
      );
      final d = Driver(a);
      d.settle(Body.pushUp(165));
      // Elbows to 120°: the shoulders come only an eighth of the way down.
      d.phase(Body.pushUp(120));
      expect(d.last!.phase, CyclePhase.rest);
      var event = false;
      for (var i = 0; i < 4; i++) {
        event = event || d.feed(Body.pushUp(165)).event == FormStatus.goDeeper;
      }
      expect(event, isTrue);
      expect(a.repCount, 0);
      expect(a.diagnostics.shallowAttempts, 1);
    });
  });

  group('PushUpAnalyzer false positives', () {
    test('a hand waved in front of the camera never counts', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      expect(a.repCount, 1);
      // ML Kit latches onto a hand: a tiny skeleton that moves around.
      for (var i = 0; i < 12; i++) {
        final x = 0.2 + 0.05 * (i % 4);
        d.feed(Body.handFragment(Vec3(x, 0.8 + 0.1 * (i % 3), 0)));
      }
      expect(a.repCount, 1);
      expect(a.diagnostics.trackBreaks + 1, greaterThanOrEqualTo(1));
      // The real body comes back and counting resumes cleanly.
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      expect(a.repCount, 2);
    });

    test('a second person stepping in front does not add reps', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      // The skeleton jumps to a standing person elsewhere in the frame who
      // swings their arms.
      for (var cycle = 0; cycle < 3; cycle++) {
        d.phase(Body.standing(170));
        d.phase(Body.standing(80));
      }
      expect(a.repCount, 0);
    });

    test('standing and swinging the arms never counts', () {
      final a = PushUpAnalyzer();
      final d = Driver(a, view: View.front);
      d.settle(Body.standing(170));
      for (var cycle = 0; cycle < 3; cycle++) {
        d.phase(Body.standing(80));
        d.phase(Body.standing(170));
      }
      expect(a.repCount, 0);
      expect(d.last!.formStatus, FormStatus.notInPosition);
    });

    test('standing arm swings never count without a sensor either', () {
      final a = PushUpAnalyzer();
      final d = Driver(a, withGravity: false);
      d.settle(Body.standing(170));
      for (var cycle = 0; cycle < 3; cycle++) {
        d.phase(Body.standing(80));
        d.phase(Body.standing(170));
      }
      expect(a.repCount, 0);
    });

    test('bending the elbows without lowering the body does not count', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.elbowTwitch(80));
      expect(d.last!.phase, CyclePhase.rest);
      d.phase(Body.pushUp(170));
      expect(a.repCount, 0);
      expect(a.diagnostics.rejections.keys, contains('shouldersDidNotMove'));
    });

    test('a single noisy frame does not flip the phase', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.feed(Body.pushUp(80));
      expect(d.last!.phase, CyclePhase.rest);
    });
  });

  group('PushUpAnalyzer robustness', () {
    test('reaches completed at the target and stops', () {
      final a = PushUpAnalyzer(targetReps: 2);
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      for (var i = 0; i < 3; i++) {
        d.phase(Body.pushUp(80));
        d.phase(Body.pushUp(170));
      }
      expect(a.repCount, 2);
      expect(d.last!.phase, CyclePhase.completed);
    });

    test('keeps counting after the phone is rotated mid-set', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      d.orientationTag = 1;
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      expect(a.repCount, 2);
      expect(a.diagnostics.orientationChanges, 1);
    });

    test('keeps counting after the user shifts position', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      // Slide sideways over a few frames (continuous, not a jump).
      for (var i = 1; i <= 6; i++) {
        d.feed(Body.pushUp(170), offsetX: 0.5 + 0.02 * i);
      }
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(80), offsetX: 0.62);
      }
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(170), offsetX: 0.62);
      }
      expect(a.repCount, 2);
    });

    test('adapts to a shallow range of motion', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(165));
      for (var i = 0; i < 6; i++) {
        d.phase(Body.pushUp(110));
        d.phase(Body.pushUp(165));
      }
      expect(a.repCount, greaterThanOrEqualTo(2));
    });

    test('depth gauge: 0 at the top, 1 at the bottom', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      expect(d.last!.depth, closeTo(0, 0.05));
      d.phase(Body.pushUp(80));
      expect(d.last!.depth, closeTo(1, 0.05));
    });

    test('diagnostics report mentions reps and thresholds', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      final report = a.diagnostics.report();
      expect(report, contains('reps=1'));
      expect(report, contains('thresholds'));
      expect(report, contains('Push-ups'));
    });

    test('reset clears everything', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(80));
      d.phase(Body.pushUp(170));
      a.reset();
      expect(a.repCount, 0);
      expect(a.formScore, isNull);
    });
  });

  group('PushUpAnalyzer confidence and form', () {
    final lowArms = {
      for (final s in BodySide.values) ...{
        s.shoulder: 0.3,
        s.elbow: 0.3,
        s.wrist: 0.3,
      },
    };

    test('low arm confidence blocks counting', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(80), conf: lowArms);
      }
      expect(d.last!.formStatus, FormStatus.armNotVisible);
      d.phase(Body.pushUp(170));
      expect(a.repCount, 0);
    });

    test('empty frames report body not visible', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      expect(d.feedEmpty().formStatus, FormStatus.bodyNotVisible);
    });

    test('falls back to the one visible arm', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      final rightHidden = {
        LandmarkType.rightShoulder: 0.2,
        LandmarkType.rightElbow: 0.2,
        LandmarkType.rightWrist: 0.2,
      };
      for (var i = 0; i < 7; i++) {
        d.feed(Body.pushUp(170), conf: rightHidden);
      }
      expect(d.last!.limbsUsed, 1);
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(80), conf: rightHidden);
      }
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(170), conf: rightHidden);
      }
      expect(a.repCount, 1);
    });

    test('raised and sagging hips are flagged in every view', () {
      for (final view in [View.side, View.front, View.elevated]) {
        final high = PushUpAnalyzer();
        final dh = Driver(high, view: view);
        dh.settle(Body.pushUp(170, hipOffset: 0.2));
        expect(dh.last!.formStatus, FormStatus.hipsTooHigh, reason: '$view');
        final low = PushUpAnalyzer();
        final dl = Driver(low, view: view);
        dl.settle(Body.pushUp(170, hipOffset: -0.2));
        expect(dl.last!.formStatus, FormStatus.hipsTooLow, reason: '$view');
      }
    });

    test('relaxed sensitivity tolerates a small sag', () {
      final strict = PushUpAnalyzer(
        thresholds: PushUpThresholds.forSensitivity(FormSensitivity.high),
      );
      final relaxed = PushUpAnalyzer(
        thresholds: PushUpThresholds.forSensitivity(FormSensitivity.low),
      );
      Driver(strict).settle(Body.pushUp(170, hipOffset: -0.13));
      Driver(relaxed).settle(Body.pushUp(170, hipOffset: -0.13));
      expect(strict.formStatus, FormStatus.hipsTooLow);
      expect(relaxed.formStatus, FormStatus.goodForm);
    });

    test('body touching the frame edge asks the user to move back', () {
      final a = PushUpAnalyzer();
      final d = Driver(a);
      for (var i = 0; i < 4; i++) {
        d.feed(Body.pushUp(170), offsetX: 0.0);
      }
      expect(d.last!.formStatus, FormStatus.moveBack);
    });
  });

  // ---------------------------------------------------------------------------
  // Squats & lunges
  // ---------------------------------------------------------------------------
  group('SquatAnalyzer', () {
    for (final (name, view) in [('side', View.side), ('front', View.front)]) {
      test('counts squats from the $name', () {
        final a = SquatAnalyzer();
        final d = Driver(a, view: view);
        d.settle(Body.squat(175));
        expect(d.last!.inPosition, isTrue);
        for (var i = 0; i < 3; i++) {
          d.phase(Body.squat(95));
          d.phase(Body.squat(175));
        }
        expect(a.repCount, 3);
      });
    }

    test('standing arm swings do not count as squats', () {
      final a = SquatAnalyzer();
      final d = Driver(a);
      d.settle(Body.standing(170));
      for (var i = 0; i < 3; i++) {
        d.phase(Body.standing(80));
        d.phase(Body.standing(170));
      }
      expect(a.repCount, 0);
    });

    test('a plank is not a squat position', () {
      final a = SquatAnalyzer();
      final d = Driver(a);
      d.settle(Body.pushUp(170));
      expect(d.last!.inPosition, isFalse);
      expect(d.last!.formStatus, FormStatus.notInPosition);
    });
  });

  group('LungeAnalyzer', () {
    test('counts lunges', () {
      final a = LungeAnalyzer();
      final d = Driver(a);
      d.settle(Body.lunge(175));
      for (var i = 0; i < 3; i++) {
        d.phase(Body.lunge(95));
        d.phase(Body.lunge(175));
      }
      expect(a.repCount, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // Sit-ups
  // ---------------------------------------------------------------------------
  group('SitUpAnalyzer', () {
    test('counts sit-ups from the side', () {
      final a = SitUpAnalyzer();
      final d = Driver(a);
      final lying = Body.sitUp(135);
      final up = Body.sitUp(50);
      d.settle(lying);
      expect(d.last!.inPosition, isTrue);
      for (var i = 0; i < 3; i++) {
        d.transition(lying, up);
        d.phase(up);
        d.transition(up, lying);
        d.phase(lying);
      }
      expect(a.repCount, 3);
    });

    test('standing is not a sit-up position', () {
      final a = SitUpAnalyzer();
      final d = Driver(a);
      d.settle(Body.standing(170));
      expect(d.last!.inPosition, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Burpees
  // ---------------------------------------------------------------------------
  group('BurpeeAnalyzer', () {
    test('standing → floor → standing counts one burpee', () {
      final a = BurpeeAnalyzer();
      final d = Driver(a);
      final stand = Body.standing(175);
      final floor = Body.pushUp(170);
      d.settle(stand);
      expect(d.last!.phase, CyclePhase.rest);
      for (var i = 0; i < 3; i++) {
        for (var t = 1; t <= 4; t++) {
          d.feed(Body.blend(stand, floor, t / 4));
        }
        d.phase(floor);
        for (var t = 3; t >= 0; t--) {
          d.feed(Body.blend(stand, floor, t / 4));
        }
        d.phase(stand);
      }
      expect(a.repCount, 3);
    });

    test('bending forward without reaching the floor does not count', () {
      final a = BurpeeAnalyzer();
      final d = Driver(a);
      final stand = Body.standing(175);
      final floor = Body.pushUp(170);
      d.settle(stand);
      for (var i = 0; i < 3; i++) {
        d.phase(Body.blend(stand, floor, 0.3));
        d.phase(stand);
      }
      expect(a.repCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Jumping jacks
  // ---------------------------------------------------------------------------
  group('JumpingJackAnalyzer', () {
    test('closed → open → closed counts one from the front', () {
      final a = JumpingJackAnalyzer();
      final d = Driver(a, view: View.front);
      d.settle(Body.jumpingJack(0));
      expect(d.last!.phase, CyclePhase.rest);
      for (var i = 0; i < 4; i++) {
        d.phase(Body.jumpingJack(1));
        d.phase(Body.jumpingJack(0));
      }
      expect(a.repCount, 4);
    });

    test('raising the arms without moving the feet does not count', () {
      final a = JumpingJackAnalyzer();
      final d = Driver(a, view: View.front);
      final closed = Body.jumpingJack(0);
      final armsOnly = Body(Map.of(Body.jumpingJack(1).joints));
      for (final s in BodySide.values) {
        armsOnly.joints[s.ankle] = closed.joints[s.ankle]!;
        armsOnly.joints[s.knee] = closed.joints[s.knee]!;
      }
      d.settle(closed);
      for (var i = 0; i < 3; i++) {
        d.phase(armsOnly);
        d.phase(closed);
      }
      expect(a.repCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Plank
  // ---------------------------------------------------------------------------
  group('PlankAnalyzer', () {
    test('accrues seconds while holding and completes at the target', () {
      final a = PlankAnalyzer(targetSeconds: 3);
      final d = Driver(a, frameGap: 100);
      d.settle(Body.pushUp(170));
      for (var i = 0; i < 32; i++) {
        d.feed(Body.pushUp(170));
      }
      expect(a.repCount, 3);
      expect(d.last!.phase, CyclePhase.completed);
      expect(d.last!.formStatus, FormStatus.goodForm);
    });

    test('standing does not count as a plank', () {
      final a = PlankAnalyzer(targetSeconds: 30);
      final d = Driver(a, frameGap: 100);
      for (var i = 0; i < 30; i++) {
        d.feed(Body.standing(175));
      }
      expect(a.repCount, 0);
      expect(d.last!.formStatus, FormStatus.notInPosition);
    });

    test('sagging hips still hold but are flagged', () {
      final a = PlankAnalyzer(targetSeconds: 30);
      final d = Driver(a, frameGap: 100);
      for (var i = 0; i < 15; i++) {
        d.feed(Body.pushUp(170, hipOffset: -0.2));
      }
      expect(a.repCount, greaterThanOrEqualTo(1));
      expect(d.last!.formStatus, FormStatus.hipsTooLow);
    });

    test('a long gap is not credited', () {
      final a = PlankAnalyzer(targetSeconds: 30);
      final d = Driver(a, frameGap: 100);
      d.settle(Body.pushUp(170));
      d.now = d.now.add(const Duration(seconds: 20));
      d.feed(Body.pushUp(170));
      expect(a.secondsHeld, lessThan(2));
    });
  });

  group('ExerciseAnalyzerFactory', () {
    test('creates an analyzer for every exercise', () {
      for (final type in ExerciseType.values) {
        final a = ExerciseAnalyzerFactory.create(
          type,
          thresholds: const PushUpThresholds(),
          target: type.defaultTarget,
        );
        expect(a.type, type);
      }
    });
  });
}
