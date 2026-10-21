import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/core/levels/level_system.dart';
import 'package:levelex/features/pt/models/equipment.dart';
import 'package:levelex/features/pt/models/movement.dart';
import 'package:levelex/features/pt/models/pt_record.dart';
import 'package:levelex/features/pt/models/workout_plan.dart';
import 'package:levelex/features/pt/planner/coach_voice.dart';
import 'package:levelex/models/form_status.dart';

PtRecord record({bool verified = true, int skipped = 0}) => PtRecord(
  id: 'r1',
  startTime: DateTime(2026, 10, 14, 7),
  endTime: DateTime(2026, 10, 14, 7, 30),
  mode: WorkoutMode.push,
  plannedMinutes: 30,
  items: [
    for (var i = 0; i < 4; i++)
      PtItemResult(
        movementId: 'push_up',
        phase: PlanPhase.main,
        setsPlanned: 3,
        setsDone: i < skipped ? 0 : 3,
        reps: i < skipped ? 0 : 30,
        seconds: 0,
        skipped: i < skipped,
        mistakes: i == 0 ? const {FormStatus.goDeeper: 2} : const {},
      ),
  ],
  verified: verified,
);

void main() {
  test('PtRecord round-trips through a map', () {
    final r = record();
    final back = PtRecord.fromMap(r.toMap());
    expect(back.id, r.id);
    expect(back.mode, WorkoutMode.push);
    expect(back.items.length, 4);
    expect(back.items.first.mistakes[FormStatus.goDeeper], 2);
    expect(back.totalReps, 120);
    expect(back.verified, isTrue);
  });

  test('XP rewards verified sessions only', () {
    expect(LevelSystem.xpForPtRecord(record()), 30 * 8 + 120 * 2 + 40);
    expect(LevelSystem.xpForPtRecord(record(verified: false)), 0);
    expect(LevelSystem.xpForPtRecord(record(skipped: 2)), 30 * 8 + 60 * 2);
  });

  test('XP counts active time, not paused time', () {
    final r = PtRecord(
      id: 'r2',
      startTime: DateTime(2026, 10, 14, 7),
      endTime: DateTime(2026, 10, 14, 8),
      mode: WorkoutMode.push,
      plannedMinutes: 30,
      items: record().items,
      verified: true,
      activeSeconds: 20 * 60,
    );
    expect(r.duration, const Duration(minutes: 20));
    expect(LevelSystem.xpForPtRecord(r), 20 * 8 + 120 * 2 + 40);
    expect(PtRecord.fromMap(r.toMap()).activeSeconds, 20 * 60);
  });

  test('completion is measured against the whole plan', () {
    final r = PtRecord(
      id: 'r3',
      startTime: DateTime(2026, 10, 14, 7),
      endTime: DateTime(2026, 10, 14, 7, 10),
      mode: WorkoutMode.push,
      plannedMinutes: 30,
      items: record().items.take(1).toList(),
      verified: true,
      plannedItems: 8,
    );
    expect(r.itemCount, 8);
    expect(r.completion, 1 / 8);
    expect(PtRecord.fromMap(r.toMap()).plannedItems, 8);
    // Older records without a planned count fall back to their results.
    expect(record().completion, 1);
  });

  test('gym profile toggles, updates and serialises', () {
    var p = const GymProfile();
    p = p.toggle(Equipment.dumbbells).toggle(Equipment.bench);
    expect(p.available, {Equipment.dumbbells, Equipment.bench});
    p = p.update(
      const EquipmentItem(type: Equipment.bench, location: 'By the window'),
    );
    expect(p.item(Equipment.bench)!.location, 'By the window');
    final back = GymProfile.fromMap(p.toMap());
    expect(back.available, p.available);
    expect(back.item(Equipment.bench)!.location, 'By the window');
    expect(p.toggle(Equipment.bench).available, {Equipment.dumbbells});
  });

  test('coach voice adapts to the result', () {
    expect(CoachVoice.summary(record()), contains('Full session'));
    expect(CoachVoice.summary(record(verified: false)), contains('not'));
    expect(CoachVoice.nextTimeTip(record(skipped: 2)), contains('skipped'));
    expect(
      CoachVoice.greeting(DateTime(2026, 1, 1, 8)),
      startsWith('Good morning'),
    );
  });
}
