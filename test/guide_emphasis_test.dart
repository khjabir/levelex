import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/figure/guide_3d.dart';
import 'package:levelex/features/pt/models/muscle_group.dart';

void main() {
  group('Guide3D muscle emphasis', () {
    test('primary full, secondary half', () {
      final e = Guide3D.emphasisFor(
        {MuscleGroup.chest, MuscleGroup.triceps},
        {MuscleGroup.shoulders, MuscleGroup.core},
      );
      expect(e['chest'], 1.0);
      expect(e['triceps'], 1.0);
      expect(e['shoulders'], 0.45);
      expect(e['core'], 0.45);
    });

    test('cardio movements light their secondary muscles fully', () {
      final e = Guide3D.emphasisFor(
        {MuscleGroup.cardio},
        {MuscleGroup.shoulders, MuscleGroup.calves},
      );
      expect(e.containsKey('cardio'), isFalse);
      expect(e['shoulders'], 1.0);
      expect(e['calves'], 1.0);
    });

    test('every library clip lights something or is a breathing drill', () {
      for (final id in [
        'push_up',
        'squat',
        'jumping_jack',
        'bike',
        'plank',
        'curl',
        'hinge',
        'high_knees',
      ]) {
        final m = Guide3D.musclesFor(id);
        expect(
          Guide3D.emphasisFor(m.primary, m.secondary),
          isNotEmpty,
          reason: id,
        );
      }
    });

    test('lite parts map muscles to body regions', () {
      final parts = Guide3D.litePartsFor({
        'quads': 1.0,
        'glutes': 1.0,
        'core': 0.45,
        'shoulders': 0.2,
      });
      expect(parts, {'legs', 'hips', 'torso'});
    });
  });
}
