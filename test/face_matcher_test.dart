import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/models/face_template.dart';

List<double> unit(int dims, int seed) {
  final r = math.Random(seed);
  return FaceMatcher.normalize([
    for (var i = 0; i < dims; i++) r.nextDouble() - 0.5,
  ]);
}

void main() {
  group('FaceMatcher', () {
    test('identical vectors have similarity 1', () {
      final v = unit(192, 1);
      expect(FaceMatcher.cosineSimilarity(v, v), closeTo(1, 1e-9));
    });

    test('opposite vectors have similarity -1', () {
      final v = unit(192, 2);
      final neg = [for (final x in v) -x];
      expect(FaceMatcher.cosineSimilarity(v, neg), closeTo(-1, 1e-9));
    });

    test('unrelated random vectors are near zero', () {
      final a = unit(192, 3);
      final b = unit(192, 4);
      expect(FaceMatcher.cosineSimilarity(a, b).abs(), lessThan(0.3));
    });

    test('zero vector yields 0 and mismatched lengths throw', () {
      expect(FaceMatcher.cosineSimilarity([0, 0, 0], [1, 2, 3]), 0);
      expect(
        () => FaceMatcher.cosineSimilarity([1, 2], [1, 2, 3]),
        throwsArgumentError,
      );
    });

    test('average of noisy samples stays close to the source', () {
      final source = unit(192, 5);
      final r = math.Random(6);
      final samples = [
        for (var k = 0; k < 5; k++)
          [for (final x in source) x + (r.nextDouble() - 0.5) * 0.1],
      ];
      final template = FaceMatcher.average(samples);
      expect(FaceMatcher.cosineSimilarity(template, source), greaterThan(0.95));
      var norm = 0.0;
      for (final x in template) {
        norm += x * x;
      }
      expect(math.sqrt(norm), closeTo(1, 1e-9));
    });

    test('classification thresholds', () {
      expect(FaceMatcher.classify(0.9), FaceMatch.match);
      expect(FaceMatcher.classify(0.55), FaceMatch.match);
      expect(FaceMatcher.classify(0.45), FaceMatch.unknown);
      expect(FaceMatcher.classify(0.2), FaceMatch.mismatch);
    });
  });

  group('FaceTemplate', () {
    test('round-trips through a map and compares', () {
      final v = unit(192, 7);
      final template = FaceTemplate(
        embedding: v,
        registeredAt: DateTime(2026, 3, 1, 8),
        sampleCount: 5,
      );
      final restored = FaceTemplate.fromMap(template.toMap());
      expect(restored.embedding.length, 192);
      expect(restored.registeredAt, DateTime(2026, 3, 1, 8));
      expect(restored.sampleCount, 5);
      expect(restored.compare(v), FaceMatch.match);
      expect(restored.compare(unit(192, 8)), FaceMatch.mismatch);
    });
  });
}
