import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/features/workout/analysis/body_tracker.dart';

import 'support/synthetic_bodies.dart';

void main() {
  group('BodyTracker', () {
    test('becomes stable after a few consistent frames', () {
      final t = BodyTracker();
      var at = DateTime(2026);
      for (var i = 0; i < 3; i++) {
        at = at.add(const Duration(milliseconds: 80));
        expect(
          t.update(View.side.project(Body.pushUp(170), at: at)),
          TrackQuality.stable,
        );
      }
      expect(t.isStable, isTrue);
    });

    test('a skeleton jump breaks the track', () {
      final t = BodyTracker();
      var at = DateTime(2026);
      for (var i = 0; i < 3; i++) {
        at = at.add(const Duration(milliseconds: 80));
        t.update(View.side.project(Body.pushUp(170), at: at));
      }
      at = at.add(const Duration(milliseconds: 80));
      final q = t.update(
        View.side.project(Body.pushUp(170), at: at, offsetX: 0.9),
      );
      expect(q, TrackQuality.jumped);
      expect(t.isStable, isFalse);
      expect(t.breaks, 1);
    });

    test('a hand-sized fragment is implausible', () {
      final t = BodyTracker();
      final q = t.update(
        View.side.project(
          Body.handFragment(const Vec3(0, 0.5, 0)),
          at: DateTime(2026),
        ),
      );
      expect(q, TrackQuality.implausible);
    });

    test('an empty frame is missing', () {
      final t = BodyTracker();
      expect(
        t.update(View.side.project(Body(const {}), at: DateTime(2026))),
        TrackQuality.missing,
      );
    });

    test('a long gap restarts stability without counting a break', () {
      final t = BodyTracker();
      var at = DateTime(2026);
      for (var i = 0; i < 3; i++) {
        at = at.add(const Duration(milliseconds: 80));
        t.update(View.side.project(Body.pushUp(170), at: at));
      }
      at = at.add(const Duration(seconds: 3));
      final q = t.update(
        View.side.project(Body.pushUp(170), at: at, offsetX: 0.9),
      );
      expect(q, TrackQuality.stable);
      expect(t.breaks, 0);
      expect(t.isStable, isFalse);
    });
  });
}
