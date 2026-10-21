import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'figure_model.dart';

/// Loads the athlete body once and shares it; null when the asset is
/// missing or unreadable (the lite mannequin takes over).
abstract final class FigureAssets {
  static const path = 'assets/figure/athlete.glb';
  static Future<FigureModel?>? _future;
  static FigureModel? _model;

  static FigureModel? get modelIfLoaded => _model;

  static Future<FigureModel?> load() {
    return _future ??= () async {
      try {
        final data = await rootBundle.load(path);
        final model = FigureModel.fromGlb(data);
        _model = model;
        return model;
      } catch (e, st) {
        debugPrint('Figure asset unavailable, using the lite guide: $e\n$st');
        return null;
      }
    }();
  }
}
