import 'package:flutter/services.dart' show DeviceOrientation;

import 'geometry.dart';

/// Converts a device accelerometer reading into the direction of gravity
/// expressed in the *upright camera image* frame used for pose landmarks
/// (x right, y down, z away from the camera).
///
/// Conventions (Android, which `sensors_plus` also applies on iOS): device x
/// points right in natural portrait, y towards the top edge, z out of the
/// screen; at rest the accelerometer reports the acceleration *opposing*
/// gravity (+9.81 on the axis pointing up).
abstract final class GravityEstimator {
  /// Returns a unit vector pointing *down* in image coordinates, or null for
  /// a degenerate (all-zero) reading.
  static Vec3? gravityInImageFrame({
    required double ax,
    required double ay,
    required double az,
    required DeviceOrientation orientation,
    required bool frontCamera,
  }) {
    final accel = Vec3(ax, ay, az);
    if (accel.length < 1e-6) return null;
    // Gravity direction in the device frame.
    final g = (-accel).normalized;

    // Screen frame (x right, y down) for the current UI orientation.
    final double sx;
    final double sy;
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        sx = g.x;
        sy = -g.y;
      case DeviceOrientation.landscapeLeft: // top of device facing left
        sx = -g.y;
        sy = -g.x;
      case DeviceOrientation.portraitDown:
        sx = -g.x;
        sy = g.y;
      case DeviceOrientation.landscapeRight: // top of device facing right
        sx = g.y;
        sy = g.x;
    }

    // The unmirrored front-camera image is horizontally flipped relative to
    // the screen and looks along +z (out of the screen); the back camera
    // looks along -z.
    final imageX = frontCamera ? -sx : sx;
    final imageZ = frontCamera ? g.z : -g.z;
    return Vec3(imageX, sy, imageZ).normalized;
  }
}
