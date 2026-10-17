import 'dart:math' as math;
import 'dart:typed_data';

/// Read-only RGB access to a camera buffer in its *raw* (unrotated) layout.
abstract class PixelSource {
  int get width;
  int get height;

  /// Returns packed `0xRRGGBB` for the pixel at raw coordinates, clamping
  /// out-of-range coordinates to the edge.
  int rgbAt(int x, int y);
}

/// Android camera frames: NV21 = full-resolution Y plane followed by
/// interleaved V/U samples at half resolution.
class Nv21PixelSource implements PixelSource {
  Nv21PixelSource({
    required this.bytes,
    required this.width,
    required this.height,
    int? rowStride,
  }) : rowStride = rowStride ?? width;

  final Uint8List bytes;
  @override
  final int width;
  @override
  final int height;
  final int rowStride;

  @override
  int rgbAt(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final yIndex = cy * rowStride + cx;
    final uvIndex = height * rowStride + (cy >> 1) * rowStride + (cx >> 1) * 2;
    if (yIndex >= bytes.length || uvIndex + 1 >= bytes.length) return 0;
    final yv = bytes[yIndex];
    final v = bytes[uvIndex] - 128;
    final u = bytes[uvIndex + 1] - 128;
    return _packYuv(yv, u, v);
  }
}

/// iOS camera frames: 32-bit BGRA with a row stride that may include padding.
class BgraPixelSource implements PixelSource {
  BgraPixelSource({
    required this.bytes,
    required this.width,
    required this.height,
    int? rowStride,
  }) : rowStride = rowStride ?? width * 4;

  final Uint8List bytes;
  @override
  final int width;
  @override
  final int height;
  final int rowStride;

  @override
  int rgbAt(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final i = cy * rowStride + cx * 4;
    if (i + 2 >= bytes.length) return 0;
    return (bytes[i + 2] << 16) | (bytes[i + 1] << 8) | bytes[i];
  }
}

int _packYuv(int y, int u, int v) {
  final r = (y + 1.402 * v).round().clamp(0, 255);
  final g = (y - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
  final b = (y + 1.772 * u).round().clamp(0, 255);
  return (r << 16) | (g << 8) | b;
}

/// Maps a point in the *upright* image (ML Kit's coordinate space) back to
/// raw buffer coordinates, undoing a clockwise rotation of [rotationDegrees]
/// that was applied to the raw image.
({double x, double y}) uprightToRaw(
  double x,
  double y, {
  required int rotationDegrees,
  required int rawWidth,
  required int rawHeight,
}) {
  switch (rotationDegrees) {
    case 90:
      // upright.x = rawH - 1 - raw.y ; upright.y = raw.x
      return (x: y, y: rawHeight - 1 - x);
    case 180:
      return (x: rawWidth - 1 - x, y: rawHeight - 1 - y);
    case 270:
      // upright.x = raw.y ; upright.y = rawW - 1 - raw.x
      return (x: rawWidth - 1 - y, y: x);
    default:
      return (x: x, y: y);
  }
}

/// Produces the 112×112 RGB tensor MobileFaceNet expects from a detected
/// face: the crop is centred on the face box, enlarged by [margin], rotated so
/// the eyes are level, and normalised to `(p - 127.5) / 128`.
abstract final class FaceCropper {
  static const outputSize = 112;

  /// [box*] describe the face bounding box and [leftEye]/[rightEye] the eye
  /// centres, all in upright-image pixel coordinates. [rotationDegrees] is
  /// the clockwise rotation that was applied to the raw buffer to make it
  /// upright (0 on iOS).
  static Float32List crop(
    PixelSource source, {
    required double boxLeft,
    required double boxTop,
    required double boxWidth,
    required double boxHeight,
    ({double x, double y})? leftEye,
    ({double x, double y})? rightEye,
    required int rotationDegrees,
    double margin = 1.15,
  }) {
    final size = math.max(boxWidth, boxHeight) * margin;
    var cx = boxLeft + boxWidth / 2;
    var cy = boxTop + boxHeight / 2;
    var angle = 0.0;
    if (leftEye != null && rightEye != null) {
      angle = math.atan2(rightEye.y - leftEye.y, rightEye.x - leftEye.x);
      // Keep the box centre but nudge towards the eye line, which anchors the
      // crop like the aligner used to train the model.
      final eyeMidX = (leftEye.x + rightEye.x) / 2;
      final eyeMidY = (leftEye.y + rightEye.y) / 2;
      cx = (cx + eyeMidX) / 2;
      cy = (cy * 0.6 + eyeMidY * 0.4) + size * 0.05;
    }
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);

    final out = Float32List(outputSize * outputSize * 3);
    var o = 0;
    for (var v = 0; v < outputSize; v++) {
      final dy = (v / (outputSize - 1) - 0.5) * size;
      for (var u = 0; u < outputSize; u++) {
        final dx = (u / (outputSize - 1) - 0.5) * size;
        // Rotate the sampling grid by the eye angle around the centre.
        final ux = cx + dx * cosA - dy * sinA;
        final uy = cy + dx * sinA + dy * cosA;
        final raw = uprightToRaw(
          ux,
          uy,
          rotationDegrees: rotationDegrees,
          rawWidth: source.width,
          rawHeight: source.height,
        );
        final rgb = source.rgbAt(raw.x.round(), raw.y.round());
        out[o++] = (((rgb >> 16) & 0xFF) - 127.5) / 128;
        out[o++] = (((rgb >> 8) & 0xFF) - 127.5) / 128;
        out[o++] = ((rgb & 0xFF) - 127.5) / 128;
      }
    }
    return out;
  }
}
