import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/geometry.dart';

void main() {
  group('Geometry.angleAt', () {
    test('straight line gives 180 degrees', () {
      final angle = Geometry.angleAt(
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(2, 0),
      );
      expect(angle, closeTo(180, 1e-6));
    });

    test('right angle gives 90 degrees', () {
      final angle = Geometry.angleAt(
        const Point2(0, 1),
        const Point2(0, 0),
        const Point2(1, 0),
      );
      expect(angle, closeTo(90, 1e-6));
    });

    test('folded back gives 0 degrees', () {
      final angle = Geometry.angleAt(
        const Point2(1, 0),
        const Point2(0, 0),
        const Point2(2, 0),
      );
      expect(angle, closeTo(0, 1e-6));
    });

    test('elbow angle example: shoulder-elbow-wrist bent ~60 degrees', () {
      // Equilateral-ish triangle: 60 degrees at the elbow.
      final angle = Geometry.angleAt(
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(0.5, 0.8660254),
      );
      expect(angle, closeTo(60, 1e-4));
    });

    test('degenerate (zero length) segments return 0 rather than NaN', () {
      final angle = Geometry.angleAt(
        const Point2(1, 1),
        const Point2(1, 1),
        const Point2(2, 2),
      );
      expect(angle, 0);
      expect(angle.isNaN, isFalse);
    });
  });

  group('Geometry.signedDistanceAboveLine', () {
    test('point above a horizontal line is positive', () {
      final d = Geometry.signedDistanceAboveLine(
        const Point2(0.5, 0.2),
        const Point2(0, 0.5),
        const Point2(1, 0.5),
      );
      expect(d, closeTo(0.3, 1e-9));
    });

    test(
      'point below a horizontal line is negative regardless of direction',
      () {
        final d1 = Geometry.signedDistanceAboveLine(
          const Point2(0.5, 0.8),
          const Point2(0, 0.5),
          const Point2(1, 0.5),
        );
        final d2 = Geometry.signedDistanceAboveLine(
          const Point2(0.5, 0.8),
          const Point2(1, 0.5),
          const Point2(0, 0.5),
        );
        expect(d1, closeTo(-0.3, 1e-9));
        expect(d2, closeTo(-0.3, 1e-9));
      },
    );

    test('point on the line is zero', () {
      final d = Geometry.signedDistanceAboveLine(
        const Point2(0.5, 0.5),
        const Point2(0, 0.5),
        const Point2(1, 0.5),
      );
      expect(d, closeTo(0, 1e-9));
    });
  });
}
