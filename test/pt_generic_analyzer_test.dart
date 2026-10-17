import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/analysis/generic_analyzers.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/workout/analysis/rep_cycle_counter.dart';
import 'package:levelex/models/form_status.dart';

import 'support/synthetic_bodies.dart';

void main() {
  group('GenericAngleAnalyzer', () {
    test('counts curls from the elbow angle while standing', () {
      final a = GenericAngleAnalyzer(
        spec: const AngleTracking(
          joint: JointKind.elbow,
          restAngle: 155,
          workAngle: 65,
          requireUpright: true,
        ),
        label: 'Curls',
        targetReps: 3,
      );
      final d = Driver(a, view: View.front);
      d.settle(Body.standing(170));
      for (var i = 0; i < 3; i++) {
        d.phase(Body.standing(45));
        d.phase(Body.standing(170));
      }
      expect(a.repCount, 3);
      expect(d.last!.phase, CyclePhase.completed);
    });

    test('a half curl is reported as too shallow', () {
      final a = GenericAngleAnalyzer(
        spec: const AngleTracking(
          joint: JointKind.elbow,
          restAngle: 155,
          workAngle: 65,
        ),
        label: 'Curls',
      );
      final d = Driver(a, view: View.side);
      d.settle(Body.standing(170));
      d.phase(Body.standing(110));
      var shallow = false;
      for (var i = 0; i < 4; i++) {
        shallow =
            shallow || d.feed(Body.standing(170)).event == FormStatus.goDeeper;
      }
      expect(a.repCount, 0);
      expect(shallow, isTrue);
    });

    test('lying bodies do not count for upright-only movements', () {
      final a = GenericAngleAnalyzer(
        spec: const AngleTracking(
          joint: JointKind.elbow,
          restAngle: 155,
          workAngle: 65,
          requireUpright: true,
        ),
        label: 'Curls',
      );
      final d = Driver(a, view: View.side);
      d.settle(Body.pushUp(170));
      d.phase(Body.pushUp(60));
      d.phase(Body.pushUp(170));
      expect(a.repCount, 0);
      expect(d.last!.formStatus, FormStatus.notInPosition);
    });
  });

  group('GenericHoldAnalyzer', () {
    test('accrues seconds while the knee angle is in range', () {
      final a = GenericHoldAnalyzer(
        spec: const HoldTracking(
          joint: JointKind.knee,
          minAngle: 60,
          maxAngle: 125,
        ),
        label: 'Wall sit',
        targetSeconds: 2,
      );
      final d = Driver(a, view: View.side, frameGap: 100);
      d.phase(Body.squat(90), frames: 30);
      expect(a.secondsHeld, greaterThanOrEqualTo(2));
      expect(a.repCount, greaterThanOrEqualTo(2));
      expect(d.last!.phase, CyclePhase.completed);
    });

    test('standing straight does not count as a wall sit', () {
      final a = GenericHoldAnalyzer(
        spec: const HoldTracking(
          joint: JointKind.knee,
          minAngle: 60,
          maxAngle: 125,
        ),
        label: 'Wall sit',
      );
      final d = Driver(a, view: View.side, frameGap: 100);
      d.phase(Body.squat(175), frames: 20);
      expect(a.secondsHeld, 0);
      expect(d.last!.formStatus, FormStatus.notInPosition);
    });
  });

  group('PtAnalyzerFactory', () {
    test('returns null for timers and an analyzer otherwise', () {
      expect(
        PtAnalyzerFactory.create(const TimerTracking(), label: 'x'),
        isNull,
      );
      expect(
        PtAnalyzerFactory.create(
          const AngleTracking(
            joint: JointKind.hip,
            restAngle: 170,
            workAngle: 100,
          ),
          label: 'x',
        ),
        isA<GenericAngleAnalyzer>(),
      );
    });
  });
}
