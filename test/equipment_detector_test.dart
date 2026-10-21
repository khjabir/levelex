import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/data/equipment_detector.dart';
import 'package:levelex/features/pt/models/equipment.dart';

void main() {
  test('ranks specific labels above generic ones', () {
    final guesses = EquipmentDetector.rank([
      ('Bench', 0.92),
      ('Metal', 0.80),
      ('Room', 0.75),
    ]);
    expect(guesses.first.type, Equipment.bench);
    expect(guesses.first.evidence, contains('Bench'));
    expect(guesses.map((g) => g.type), contains(Equipment.dumbbells));
  });

  test('returns nothing for unrelated photos', () {
    expect(EquipmentDetector.rank([('Cat', 0.9), ('Sky', 0.8)]), isEmpty);
  });

  test('bikes, rowers and treadmills come from sport labels', () {
    expect(
      EquipmentDetector.rank([('Bicycle', 0.9)]).first.type,
      Equipment.bike,
    );
    expect(
      EquipmentDetector.rank([('Rowing', 0.7)]).first.type,
      Equipment.rower,
    );
    expect(
      EquipmentDetector.rank([('Running', 0.7), ('Odometer', 0.5)]).first.type,
      Equipment.treadmill,
    );
  });
}
