import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/geometry.dart';
import 'package:levelex/core/utils/gravity.dart';

void expectVec(Vec3? v, double x, double y, double z) {
  expect(v, isNotNull);
  expect(v!.x, closeTo(x, 1e-6));
  expect(v.y, closeTo(y, 1e-6));
  expect(v.z, closeTo(z, 1e-6));
}

void main() {
  group('GravityEstimator', () {
    test('upright portrait phone, front camera: down is image +y', () {
      final g = GravityEstimator.gravityInImageFrame(
        ax: 0,
        ay: 9.81,
        az: 0,
        orientation: DeviceOrientation.portraitUp,
        frontCamera: true,
      );
      expectVec(g, 0, 1, 0);
    });

    test('upright portrait phone, back camera: down is image +y', () {
      final g = GravityEstimator.gravityInImageFrame(
        ax: 0,
        ay: 9.81,
        az: 0,
        orientation: DeviceOrientation.portraitUp,
        frontCamera: false,
      );
      expectVec(g, 0, 1, 0);
    });

    test(
      'phone flat on a table, front camera looks up: down is toward camera',
      () {
        final g = GravityEstimator.gravityInImageFrame(
          ax: 0,
          ay: 0,
          az: 9.81,
          orientation: DeviceOrientation.portraitUp,
          frontCamera: true,
        );
        expectVec(g, 0, 0, -1);
      },
    );

    test('phone flat on a table, back camera looks down: down is away', () {
      final g = GravityEstimator.gravityInImageFrame(
        ax: 0,
        ay: 0,
        az: 9.81,
        orientation: DeviceOrientation.portraitUp,
        frontCamera: false,
      );
      expectVec(g, 0, 0, 1);
    });

    test('landscape left (top facing left): down is still image +y', () {
      // Right edge points up, so gravity pulls towards the left edge (-x).
      final g = GravityEstimator.gravityInImageFrame(
        ax: 9.81,
        ay: 0,
        az: 0,
        orientation: DeviceOrientation.landscapeLeft,
        frontCamera: false,
      );
      expectVec(g, 0, 1, 0);
    });

    test('landscape right (top facing right): down is still image +y', () {
      final g = GravityEstimator.gravityInImageFrame(
        ax: -9.81,
        ay: 0,
        az: 0,
        orientation: DeviceOrientation.landscapeRight,
        frontCamera: true,
      );
      expectVec(g, 0, 1, 0);
    });

    test('phone on its side with auto-rotate off: down is image +x', () {
      // Top facing left but the UI stayed in portrait: gravity now points
      // along the image's horizontal axis (towards the left edge of the
      // natural orientation = image +x for the front camera).
      final g = GravityEstimator.gravityInImageFrame(
        ax: 9.81,
        ay: 0,
        az: 0,
        orientation: DeviceOrientation.portraitUp,
        frontCamera: true,
      );
      expectVec(g, 1, 0, 0);
    });

    test('tilted phone keeps a unit vector', () {
      final g = GravityEstimator.gravityInImageFrame(
        ax: 0,
        ay: 6.9,
        az: 6.9,
        orientation: DeviceOrientation.portraitUp,
        frontCamera: true,
      );
      expect(g!.length, closeTo(1, 1e-9));
      expect(g.y, greaterThan(0));
      expect(g.z, lessThan(0));
    });

    test('zero reading yields null', () {
      expect(
        GravityEstimator.gravityInImageFrame(
          ax: 0,
          ay: 0,
          az: 0,
          orientation: DeviceOrientation.portraitUp,
          frontCamera: true,
        ),
        isNull,
      );
    });
  });

  group('Geometry 3D', () {
    test('angleAt3 of a straight line is 180', () {
      expect(
        Geometry.angleAt3(
          const Vec3(0, 0, 0),
          const Vec3(1, 0, 0),
          const Vec3(2, 0, 0),
        ),
        closeTo(180, 1e-9),
      );
    });

    test('angleAt3 uses depth: a bend only visible in z is detected', () {
      // Shoulder and wrist overlap in x/y; the elbow sticks out towards the
      // camera, so the 2D angle would be 0 but the 3D angle is 90.
      expect(
        Geometry.angleAt3(
          const Vec3(0, 0, 0),
          const Vec3(0, 0.5, -0.5),
          const Vec3(0, 1, 0),
        ),
        closeTo(90, 1e-9),
      );
    });

    test('deviationAlong measures offset towards up', () {
      final d = Geometry.deviationAlong(
        const Vec3(0.5, 0.3, 0),
        const Vec3(0, 0.5, 0),
        const Vec3(1, 0.5, 0),
        const Vec3(0, -1, 0),
      );
      expect(d, closeTo(0.2, 1e-9));
    });
  });
}
