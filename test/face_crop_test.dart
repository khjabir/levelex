import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/utils/face_crop.dart';

/// Builds an NV21 buffer where Y encodes the raw x coordinate (×10) and the
/// chroma planes are neutral grey, so `rgbAt` reveals sampling positions.
Nv21PixelSource gradientNv21(int w, int h) {
  final bytes = Uint8List(w * h * 3 ~/ 2);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      bytes[y * w + x] = (x * 10).clamp(0, 255);
    }
  }
  for (var i = w * h; i < bytes.length; i++) {
    bytes[i] = 128; // neutral U/V
  }
  return Nv21PixelSource(bytes: bytes, width: w, height: h);
}

void main() {
  group('uprightToRaw', () {
    test('identity for 0 degrees', () {
      final p = uprightToRaw(
        3,
        4,
        rotationDegrees: 0,
        rawWidth: 8,
        rawHeight: 6,
      );
      expect((p.x, p.y), (3.0, 4.0));
    });

    test('inverts a 90 degree clockwise rotation', () {
      // raw (x=2, y=1) in an 8x6 image → rotated 90° CW → upright (4, 2).
      final p = uprightToRaw(
        4,
        2,
        rotationDegrees: 90,
        rawWidth: 8,
        rawHeight: 6,
      );
      expect((p.x, p.y), (2.0, 1.0));
    });

    test('inverts a 270 degree rotation', () {
      // raw (x=2, y=1) → rotated 270° CW → upright (1, 5).
      final p = uprightToRaw(
        1,
        5,
        rotationDegrees: 270,
        rawWidth: 8,
        rawHeight: 6,
      );
      expect((p.x, p.y), (2.0, 1.0));
    });

    test('inverts a 180 degree rotation', () {
      final p = uprightToRaw(
        5,
        4,
        rotationDegrees: 180,
        rawWidth: 8,
        rawHeight: 6,
      );
      expect((p.x, p.y), (2.0, 1.0));
    });
  });

  group('pixel sources', () {
    test('NV21 neutral chroma yields grey from luma', () {
      final src = gradientNv21(8, 6);
      final rgb = src.rgbAt(5, 0);
      expect((rgb >> 16) & 0xFF, 50);
      expect((rgb >> 8) & 0xFF, 50);
      expect(rgb & 0xFF, 50);
    });

    test('NV21 clamps out-of-range coordinates', () {
      final src = gradientNv21(8, 6);
      expect(src.rgbAt(-5, -5), src.rgbAt(0, 0));
      expect(src.rgbAt(100, 100), src.rgbAt(7, 5));
    });

    test('BGRA reads channels in the right order with stride', () {
      final bytes = Uint8List(2 * 16); // 2 rows, stride 16 (2 px + padding)
      bytes[16 + 4] = 10; // B of (1,1)
      bytes[16 + 5] = 20; // G
      bytes[16 + 6] = 30; // R
      final src = BgraPixelSource(
        bytes: bytes,
        width: 2,
        height: 2,
        rowStride: 16,
      );
      expect(src.rgbAt(1, 1), (30 << 16) | (20 << 8) | 10);
    });
  });

  group('FaceCropper', () {
    test('produces a 112x112x3 normalised tensor', () {
      final src = gradientNv21(64, 64);
      final out = FaceCropper.crop(
        src,
        boxLeft: 16,
        boxTop: 16,
        boxWidth: 32,
        boxHeight: 32,
        rotationDegrees: 0,
      );
      expect(out.length, 112 * 112 * 3);
      expect(out.every((v) => v >= -1 && v <= 1), isTrue);
      // Left edge of the crop samples darker (smaller x) than the right edge.
      final leftR = out[(56 * 112 + 2) * 3];
      final rightR = out[(56 * 112 + 109) * 3];
      expect(leftR, lessThan(rightR));
    });

    test('rotation 90 samples the raw buffer along the other axis', () {
      // With 90° rotation, moving across the upright x axis corresponds to
      // moving down the raw y axis, where Y is constant → no horizontal
      // gradient; moving down upright y walks raw x → vertical gradient.
      final src = gradientNv21(64, 64);
      final out = FaceCropper.crop(
        src,
        boxLeft: 16,
        boxTop: 16,
        boxWidth: 32,
        boxHeight: 32,
        rotationDegrees: 90,
      );
      final topR = out[(2 * 112 + 56) * 3];
      final bottomR = out[(109 * 112 + 56) * 3];
      final leftR = out[(56 * 112 + 2) * 3];
      final rightR = out[(56 * 112 + 109) * 3];
      expect((leftR - rightR).abs(), lessThan(0.05));
      expect(topR, isNot(closeTo(bottomR, 0.05)));
    });
  });
}
