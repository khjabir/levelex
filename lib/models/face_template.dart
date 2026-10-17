import 'dart:math' as math;

/// Outcome of comparing a live face with the registered template.
enum FaceMatch {
  /// Confidently the registered person.
  match,

  /// Confidently somebody else.
  mismatch,

  /// Not enough evidence either way (angle, lighting, partial face).
  unknown,
}

/// Thresholds for face verification using cosine similarity of embeddings.
class FaceMatchThresholds {
  const FaceMatchThresholds({
    this.matchSimilarity = 0.55,
    this.rejectSimilarity = 0.35,
  });

  /// At or above this similarity the face counts as the registered user.
  final double matchSimilarity;

  /// Below this similarity the face is confidently a different person.
  final double rejectSimilarity;
}

/// Pure-Dart face embedding maths (no ML dependencies).
abstract final class FaceMatcher {
  /// Cosine similarity in `[-1, 1]`; `0` when either vector is all zeros.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) {
      throw ArgumentError('Embeddings must have the same non-zero length');
    }
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Returns [v] scaled to unit length (unchanged if all zeros).
  static List<double> normalize(List<double> v) {
    var norm = 0.0;
    for (final x in v) {
      norm += x * x;
    }
    norm = math.sqrt(norm);
    if (norm == 0) return List<double>.from(v);
    return [for (final x in v) x / norm];
  }

  /// Element-wise mean of unit-normalised [samples], normalised again. Used
  /// to build a robust template from several registration frames.
  static List<double> average(List<List<double>> samples) {
    if (samples.isEmpty) throw ArgumentError('No samples');
    final length = samples.first.length;
    final sum = List<double>.filled(length, 0);
    for (final s in samples) {
      final n = normalize(s);
      for (var i = 0; i < length; i++) {
        sum[i] += n[i];
      }
    }
    return normalize([for (final x in sum) x / samples.length]);
  }

  static FaceMatch classify(
    double similarity, {
    FaceMatchThresholds thresholds = const FaceMatchThresholds(),
  }) {
    if (similarity >= thresholds.matchSimilarity) return FaceMatch.match;
    if (similarity < thresholds.rejectSimilarity) return FaceMatch.mismatch;
    return FaceMatch.unknown;
  }
}

/// The registered user's face, stored only as a numeric embedding (never an
/// image) on the device.
class FaceTemplate {
  const FaceTemplate({
    required this.embedding,
    required this.registeredAt,
    required this.sampleCount,
  });

  final List<double> embedding;
  final DateTime registeredAt;
  final int sampleCount;

  FaceMatch compare(
    List<double> candidate, {
    FaceMatchThresholds thresholds = const FaceMatchThresholds(),
  }) => FaceMatcher.classify(
    FaceMatcher.cosineSimilarity(embedding, candidate),
    thresholds: thresholds,
  );

  Map<String, dynamic> toMap() => {
    'embedding': embedding,
    'registeredAt': registeredAt.millisecondsSinceEpoch,
    'sampleCount': sampleCount,
  };

  factory FaceTemplate.fromMap(Map<String, dynamic> map) => FaceTemplate(
    embedding: [
      for (final v in map['embedding'] as List) (v as num).toDouble(),
    ],
    registeredAt: DateTime.fromMillisecondsSinceEpoch(
      map['registeredAt'] as int,
    ),
    sampleCount: (map['sampleCount'] as int?) ?? 1,
  );
}
