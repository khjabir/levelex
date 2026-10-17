import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../models/face_template.dart';
import '../pt/pt_providers.dart';

/// The registered face template (null until the user enrols).
class FaceTemplateNotifier extends Notifier<FaceTemplate?> {
  @override
  FaceTemplate? build() => ref.watch(settingsRepositoryProvider).faceTemplate;

  Future<FaceTemplate> register(List<List<double>> samples) async {
    final template = await ref
        .read(workoutServiceProvider)
        .registerFace(samples);
    state = template;
    return template;
  }

  /// Deletes the face template and, with it, every recorded session.
  Future<void> erase() async {
    await ref.read(workoutServiceProvider).eraseFaceData();
    await ref.read(ptRecordsProvider.notifier).clear();
    state = null;
    ref.read(sessionsProvider.notifier).refresh();
  }
}

final faceTemplateProvider =
    NotifierProvider<FaceTemplateNotifier, FaceTemplate?>(
      FaceTemplateNotifier.new,
    );

final faceRegisteredProvider = Provider<bool>(
  (ref) => ref.watch(faceTemplateProvider) != null,
);
