import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import '../models/equipment.dart';

/// One suggestion from a photo.
class EquipmentGuess {
  const EquipmentGuess({
    required this.type,
    required this.confidence,
    required this.evidence,
  });

  final Equipment type;

  /// 0..1, a combination of label confidence and how specific the label is.
  final double confidence;

  /// The labels that led here ("Bench 0.91").
  final String evidence;
}

/// Recognises gym equipment in a photo with ML Kit's on-device image
/// labeler. The base model knows benches, bikes, rowing, running and a few
/// generic cues (metal, muscle, sports), so results are ranked best guesses
/// that the user confirms; nothing is uploaded.
class EquipmentDetector {
  EquipmentDetector({ImageLabeler? labeler})
    : _labeler =
          labeler ??
          ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.35));

  final ImageLabeler _labeler;

  /// Label (lower case) → candidate equipment with a specificity weight.
  static const Map<String, List<(Equipment, double)>> labelMap = {
    'bench': [(Equipment.bench, 1.0)],
    'chair': [(Equipment.bench, 0.45)],
    'couch': [(Equipment.bench, 0.35)],
    'loveseat': [(Equipment.bench, 0.35)],
    'armrest': [(Equipment.bench, 0.3)],
    'bicycle': [(Equipment.bike, 1.0)],
    'cycling': [(Equipment.bike, 0.9)],
    'wheel': [(Equipment.bike, 0.4)],
    'rowing': [(Equipment.rower, 1.0)],
    'kayak': [(Equipment.rower, 0.3)],
    'canoe': [(Equipment.rower, 0.3)],
    'running': [(Equipment.treadmill, 0.8)],
    'marathon': [(Equipment.treadmill, 0.6)],
    'track': [(Equipment.treadmill, 0.5)],
    'race': [(Equipment.treadmill, 0.4)],
    'odometer': [(Equipment.treadmill, 0.6), (Equipment.bike, 0.4)],
    'handrail': [(Equipment.pullUpBar, 0.6)],
    'playground': [(Equipment.pullUpBar, 0.5)],
    'swing': [(Equipment.pullUpBar, 0.4)],
    'strap': [(Equipment.resistanceBands, 0.6), (Equipment.cableMachine, 0.3)],
    'chain': [(Equipment.cableMachine, 0.6)],
    'net': [(Equipment.cableMachine, 0.2)],
    'metal': [
      (Equipment.dumbbells, 0.5),
      (Equipment.barbell, 0.45),
      (Equipment.kettlebell, 0.35),
    ],
    'muscle': [
      (Equipment.dumbbells, 0.55),
      (Equipment.barbell, 0.45),
      (Equipment.kettlebell, 0.35),
    ],
    'gymnastics': [(Equipment.mat, 0.5), (Equipment.pullUpBar, 0.4)],
    'sports': [(Equipment.dumbbells, 0.3), (Equipment.medicineBall, 0.3)],
    'balance': [(Equipment.mat, 0.4), (Equipment.box, 0.3)],
    'cushion': [(Equipment.mat, 0.5)],
    'pillow': [(Equipment.mat, 0.4)],
    'textile': [(Equipment.mat, 0.4), (Equipment.resistanceBands, 0.2)],
    'tile': [(Equipment.mat, 0.3)],
    'toy': [(Equipment.medicineBall, 0.4), (Equipment.kettlebell, 0.2)],
    'balloon': [(Equipment.medicineBall, 0.5)],
    'roller': [(Equipment.box, 0.3)],
    'stairs': [(Equipment.box, 0.5)],
    'shelf': [(Equipment.dumbbells, 0.45)],
    'cabinetry': [(Equipment.dumbbells, 0.3)],
  };

  /// Ranked guesses for the photo at [path]. Empty when nothing matched.
  Future<List<EquipmentGuess>> detect(String path) async {
    List<ImageLabel> labels;
    try {
      labels = await _labeler.processImage(InputImage.fromFilePath(path));
    } catch (e) {
      debugPrint('Equipment labeling failed: $e');
      return const [];
    }
    return rank([for (final l in labels) (l.label, l.confidence)]);
  }

  /// Pure ranking of (label, confidence) pairs; testable without ML Kit.
  static List<EquipmentGuess> rank(Iterable<(String, double)> labels) {
    final scores = <Equipment, double>{};
    final evidence = <Equipment, List<String>>{};
    for (final (label, confidence) in labels) {
      final candidates = labelMap[label.toLowerCase()];
      if (candidates == null) continue;
      for (final (type, weight) in candidates) {
        final s = confidence * weight;
        scores[type] = (scores[type] ?? 0) + s;
        (evidence[type] ??= []).add('$label ${(confidence * 100).round()}%');
      }
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in ranked.take(3))
        EquipmentGuess(
          type: e.key,
          confidence: e.value.clamp(0.0, 1.0),
          evidence: evidence[e.key]!.join(', '),
        ),
    ];
  }

  Future<void> dispose() => _labeler.close();
}
