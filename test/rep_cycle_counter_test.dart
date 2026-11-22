import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/workout/analysis/rep_cycle_counter.dart';

class Feeder {
  Feeder(this.counter, {this.gapMs = 80});

  final RepCycleCounter counter;
  final int gapMs;
  DateTime now = DateTime(2026, 1, 1);
  CycleUpdate? last;

  CycleUpdate feed(
    double? signal, {
    bool valid = true,
    bool Function()? vetoWork,
    bool Function()? vetoRest,
  }) {
    now = now.add(Duration(milliseconds: gapMs));
    last = counter.update(
      signal: signal,
      now: now,
      valid: valid,
      vetoWork: vetoWork,
      vetoRest: vetoRest,
    );
    return last!;
  }

  void hold(double signal, int frames, {bool Function()? vetoWork}) {
    for (var i = 0; i < frames; i++) {
      feed(signal, vetoWork: vetoWork);
    }
  }
}

CycleConfig angleConfig({bool adaptive = true}) => CycleConfig(
  restDefault: 150,
  workDefault: 100,
  adaptive: adaptive,
  minRange: 35,
  margin: 0.3,
);

void main() {
  group('RepCycleCounter', () {
    test('rest → work → rest counts one rep', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(170, 3);
      expect(c.phase, CyclePhase.rest);
      f.hold(80, 4);
      expect(c.phase, CyclePhase.work);
      f.hold(170, 3);
      expect(c.repCount, 1);
      expect(c.phase, CyclePhase.rest);
    });

    test('a half rep that returns to rest is reported as shallow', () {
      final c = RepCycleCounter(config: angleConfig(adaptive: false));
      final f = Feeder(c);
      f.hold(170, 3);
      // Down to 125°: half way to the work threshold (100), never reaching it.
      f.hold(125, 4);
      expect(c.phase, CyclePhase.rest);
      var shallow = false;
      for (var i = 0; i < 3; i++) {
        shallow = shallow || f.feed(170).shallowAttempt;
      }
      expect(shallow, isTrue);
      expect(c.repCount, 0);
      // A tiny wobble is not a shallow attempt.
      f.hold(160, 3);
      shallow = false;
      for (var i = 0; i < 3; i++) {
        shallow = shallow || f.feed(170).shallowAttempt;
      }
      expect(shallow, isFalse);
    });

    test('a vetoed descent is not reported as shallow', () {
      final c = RepCycleCounter(config: angleConfig(adaptive: false));
      final f = Feeder(c);
      f.hold(170, 3);
      f.hold(80, 4, vetoWork: () => true);
      expect(c.phase, CyclePhase.rest);
      var shallow = false;
      for (var i = 0; i < 3; i++) {
        shallow = shallow || f.feed(170).shallowAttempt;
      }
      expect(shallow, isFalse);
    });

    test('starting in the work position needs a rest first', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(80, 4);
      expect(c.phase, CyclePhase.ready);
      f.hold(170, 3);
      f.hold(80, 4);
      f.hold(170, 3);
      expect(c.repCount, 1);
    });

    test('signal inside the band keeps the phase', () {
      final c = RepCycleCounter(config: angleConfig(adaptive: false));
      final f = Feeder(c);
      f.hold(170, 3);
      f.hold(125, 6);
      expect(c.phase, CyclePhase.rest);
      expect(c.repCount, 0);
    });

    test('one noisy frame does not transition', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(170, 3);
      f.feed(80);
      expect(c.phase, CyclePhase.rest);
    });

    test('too short a work phase is rejected', () {
      final c = RepCycleCounter(
        config: const CycleConfig(
          restDefault: 150,
          workDefault: 100,
          minFrames: 1,
          minWorkDuration: Duration(milliseconds: 300),
        ),
      );
      final f = Feeder(c, gapMs: 50);
      f.hold(170, 2);
      f.feed(80);
      final u = f.feed(170);
      expect(u.rejection, CycleRejection.tooSoon);
      expect(c.repCount, 0);
    });

    test('cooldown blocks a second rep immediately after the first', () {
      final c = RepCycleCounter(
        config: const CycleConfig(
          restDefault: 150,
          workDefault: 100,
          minFrames: 1,
          minWorkDuration: Duration.zero,
          cooldown: Duration(milliseconds: 1000),
        ),
      );
      final f = Feeder(c, gapMs: 100);
      f.hold(170, 2);
      f.feed(80);
      f.feed(170);
      f.feed(80);
      final u = f.feed(170);
      expect(u.rejection, CycleRejection.cooldown);
      expect(c.repCount, 1);
      // Two seconds at rest (frames keep coming, as from a camera).
      f.hold(170, 20);
      f.feed(80);
      f.feed(170);
      expect(c.repCount, 2);
    });

    test('vetoWork refuses the descent and keeps rest', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(170, 3);
      f.hold(80, 4, vetoWork: () => true);
      expect(c.phase, CyclePhase.rest);
      expect(f.last!.rejection, CycleRejection.vetoed);
    });

    test('thresholds adapt to a shallow but consistent range', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      for (var i = 0; i < 5; i++) {
        f.hold(165, 4);
        f.hold(115, 4);
      }
      f.hold(165, 4);
      expect(c.workThreshold, greaterThan(100));
      expect(c.repCount, greaterThanOrEqualTo(2));
    });

    test('a range that is too small never adapts', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      for (var i = 0; i < 5; i++) {
        f.hold(170, 4);
        f.hold(145, 4);
      }
      expect(c.workThreshold, 100);
      expect(c.repCount, 0);
    });

    test('restIsHigh=false counts low → high → low', () {
      final c = RepCycleCounter(
        config: const CycleConfig(
          restDefault: 0.3,
          workDefault: 1.3,
          restIsHigh: false,
          adaptive: false,
          minGap: 0.4,
        ),
      );
      final f = Feeder(c);
      f.hold(0, 3);
      expect(c.phase, CyclePhase.rest);
      f.hold(2, 4);
      expect(c.phase, CyclePhase.work);
      f.hold(0, 3);
      expect(c.repCount, 1);
      expect(f.last!.depth, 0);
    });

    test('depth runs 0 → 1 between the thresholds', () {
      final c = RepCycleCounter(config: angleConfig(adaptive: false));
      final f = Feeder(c);
      expect(f.feed(150).depth, closeTo(0, 1e-9));
      expect(f.feed(125).depth, closeTo(0.5, 1e-9));
      expect(f.feed(100).depth, closeTo(1, 1e-9));
    });

    test('completes at the target', () {
      final c = RepCycleCounter(config: angleConfig(), target: 2);
      final f = Feeder(c);
      f.hold(170, 3);
      for (var i = 0; i < 3; i++) {
        f.hold(80, 4);
        f.hold(170, 3);
      }
      expect(c.repCount, 2);
      expect(c.phase, CyclePhase.completed);
    });

    test('invalid frames clear pending transitions', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(170, 3);
      f.feed(80);
      f.feed(80, valid: false);
      f.feed(80);
      expect(c.phase, CyclePhase.rest);
    });

    test('invalidate drops the in-flight rep but keeps the count', () {
      final c = RepCycleCounter(config: angleConfig());
      final f = Feeder(c);
      f.hold(170, 3);
      f.hold(80, 4);
      f.hold(170, 3);
      f.hold(80, 4);
      c.invalidate();
      expect(c.phase, CyclePhase.ready);
      expect(c.repCount, 1);
      f.hold(170, 3);
      expect(c.repCount, 1);
    });
  });
}
