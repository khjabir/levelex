import 'dart:math' as math;

/// An immutable 2D point used for landmark geometry.
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);

  double get length => math.sqrt(x * x + y * y);

  @override
  String toString() => 'Point2($x, $y)';
}

/// An immutable 3D vector in image units (x right, y down, z away from the
/// camera), as produced by pose landmarks with depth.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);

  final double x;
  final double y;
  final double z;

  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  double get length => math.sqrt(x * x + y * y + z * z);

  /// Unit vector, or [zero] for a zero-length vector.
  Vec3 get normalized {
    final l = length;
    return l == 0 ? zero : Vec3(x / l, y / l, z / l);
  }

  /// Mean of two vectors.
  Vec3 midpoint(Vec3 o) => Vec3((x + o.x) / 2, (y + o.y) / 2, (z + o.z) / 2);

  @override
  bool operator ==(Object other) =>
      other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() =>
      'Vec3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${z.toStringAsFixed(3)})';
}

/// Pure geometry helpers shared by the analyzer and tests.
abstract final class Geometry {
  /// Returns the angle at vertex [b] formed by the segments `b→a` and `b→c`,
  /// in degrees within `[0, 180]`.
  ///
  /// Returns `0` when either segment has zero length.
  static double angleAt(Point2 a, Point2 b, Point2 c) {
    final ba = a - b;
    final bc = c - b;
    final lenProduct = ba.length * bc.length;
    if (lenProduct == 0) return 0;
    final cosine = ((ba.x * bc.x) + (ba.y * bc.y)) / lenProduct;
    // Clamp to guard against floating point drift outside [-1, 1].
    final clamped = cosine.clamp(-1.0, 1.0);
    return math.acos(clamped) * 180 / math.pi;
  }

  /// 3D version of [angleAt]: angle at vertex [b] in degrees `[0, 180]`.
  static double angleAt3(Vec3 a, Vec3 b, Vec3 c) {
    final ba = a - b;
    final bc = c - b;
    final lenProduct = ba.length * bc.length;
    if (lenProduct == 0) return 0;
    final clamped = (ba.dot(bc) / lenProduct).clamp(-1.0, 1.0);
    return math.acos(clamped) * 180 / math.pi;
  }

  /// Angle between two direction vectors in degrees `[0, 180]`.
  static double angleBetween(Vec3 a, Vec3 b) {
    final lenProduct = a.length * b.length;
    if (lenProduct == 0) return 0;
    final clamped = (a.dot(b) / lenProduct).clamp(-1.0, 1.0);
    return math.acos(clamped) * 180 / math.pi;
  }

  /// Euclidean distance between two points.
  static double distance(Point2 a, Point2 b) => (a - b).length;

  /// Euclidean distance between two 3D points.
  static double distance3(Vec3 a, Vec3 b) => (a - b).length;

  /// Signed perpendicular distance from [p] to the infinite line through
  /// [a] and [b].
  ///
  /// The sign is chosen so that a positive value means [p] lies "above" the
  /// line in screen coordinates (towards smaller `y`), regardless of whether
  /// [a] is to the left or right of [b]. Returns `0` if [a] == [b].
  static double signedDistanceAboveLine(Point2 p, Point2 a, Point2 b) {
    final d = b - a;
    final len = d.length;
    if (len == 0) return 0;
    // Perpendicular (normal) of the direction vector.
    var nx = -d.y / len;
    var ny = d.x / len;
    // Orient the normal so it points "up" on screen (negative y).
    if (ny > 0) {
      nx = -nx;
      ny = -ny;
    }
    final ap = p - a;
    return ap.x * nx + ap.y * ny;
  }

  /// Component of [p]'s offset from the line through [a] and [b] along the
  /// direction [up] (unit vector). Positive means [p] is displaced towards
  /// [up] relative to the line. Returns `0` for a degenerate line.
  static double deviationAlong(Vec3 p, Vec3 a, Vec3 b, Vec3 up) {
    final d = b - a;
    final len = d.length;
    if (len == 0) return 0;
    final dir = d * (1 / len);
    final ap = p - a;
    // Remove the component along the line, leaving the perpendicular offset.
    final perpendicular = ap - dir * ap.dot(dir);
    return perpendicular.dot(up);
  }
}
