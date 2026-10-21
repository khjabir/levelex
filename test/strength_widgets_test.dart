import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/pt/models/muscle_group.dart';
import 'package:levelex/features/strength/logic/recovery.dart';
import 'package:levelex/features/strength/widgets/activity_heatmap.dart';
import 'package:levelex/features/strength/widgets/muscle_map.dart';

Widget host(Widget child, {double width = 360, double height = 260}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

final statuses = <MuscleGroup, MuscleStatus>{
  for (final m in MuscleGroup.values) m: MuscleStatus.fresh,
  MuscleGroup.chest: MuscleStatus(
    state: MuscleState.trained,
    fatigue: 0.8,
    lastTrained: DateTime(2026, 10, 12),
  ),
  MuscleGroup.triceps: const MuscleStatus(
    state: MuscleState.recovering,
    fatigue: 0.3,
  ),
};

void main() {
  group('MuscleMap', () {
    testWidgets('renders both figures and the legend', (tester) async {
      await tester.pumpWidget(host(MuscleMap(statuses: statuses)));
      expect(tester.takeException(), isNull);
      expect(find.byType(MuscleMap), findsOneWidget);
      expect(find.text('Fresh'), findsOneWidget);
      expect(find.text('Recovering'), findsOneWidget);
      expect(find.text('Worked'), findsOneWidget);
    });

    testWidgets('survives small and large heights and an empty map', (
      tester,
    ) async {
      for (final h in [160.0, 320.0]) {
        await tester.pumpWidget(
          host(
            MuscleMap(statuses: const {}, height: h),
            height: h,
          ),
        );
        expect(tester.takeException(), isNull);
        final box = tester.getSize(find.byType(MuscleMap));
        expect(box.height, h);
      }
    });

    testWidgets('tapping a region reports its muscle group', (tester) async {
      final taps = <MuscleGroup>[];
      await tester.pumpWidget(
        host(
          MuscleMap(
            statuses: statuses,
            onTap: taps.add,
            highlighted: MuscleGroup.chest,
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final area = find.descendant(
        of: find.byType(MuscleMap),
        matching: find.byType(GestureDetector),
      );
      final origin = tester.getTopLeft(area);
      final layout = MuscleMapLayout(tester.getSize(area));

      final chest = layout.regionCenter(MuscleGroup.chest, front: true)!;
      await tester.tapAt(origin + chest);
      final glutes = layout.regionCenter(MuscleGroup.glutes, front: false)!;
      await tester.tapAt(origin + glutes);
      // Between the figures: nothing.
      await tester.tapAt(origin + Offset(layout.size.width / 2, 4));
      await tester.pump();

      expect(taps, [MuscleGroup.chest, MuscleGroup.glutes]);
      expect(layout.regionCenter(MuscleGroup.chest, front: false), isNull);
      expect(layout.regionCenter(MuscleGroup.cardio, front: true), isNull);
    });
  });

  group('ActivityHeatmap', () {
    final today = DateTime(2026, 10, 14); // a Wednesday

    testWidgets('renders and starts scrolled to the newest week', (
      tester,
    ) async {
      final values = {
        today: 3,
        today.subtract(const Duration(days: 1)): 1,
        DateTime(2026, 9, 1): 5,
        DateTime(2026, 9, 1, 18): 1, // same day, another time
      };
      await tester.pumpWidget(
        host(
          ActivityHeatmap(values: values, today: today),
          height: ActivityHeatmap.height,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ActivityHeatmap), findsOneWidget);
      expect(ActivityHeatmap.height, 116);
      expect(tester.getSize(find.byType(ActivityHeatmap)).height, 116);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.reverse, isTrue);
      expect(scroll.scrollDirection, Axis.horizontal);
    });

    testWidgets('tapping a cell reports its day', (tester) async {
      final taps = <DateTime>[];
      await tester.pumpWidget(
        host(
          ActivityHeatmap(values: const {}, today: today, onTapDay: taps.add),
          height: 140,
        ),
      );
      final grid = find.descendant(
        of: find.byType(ActivityHeatmap),
        matching: find.byType(GestureDetector),
      );
      final origin = tester.getTopLeft(grid);
      const pitch = ActivityHeatmap.cellSize + ActivityHeatmap.gap;
      const half = ActivityHeatmap.cellSize / 2;
      Offset cell(int col, int row) => Offset(
        col * pitch + half,
        ActivityHeatmap.labelHeight + row * pitch + half,
      );

      // Today sits in the last column, on the Wednesday row.
      await tester.tapAt(origin + cell(25, 2));
      // Monday of the same week.
      await tester.tapAt(origin + cell(25, 0));
      // Tomorrow is not drawn and not tappable.
      await tester.tapAt(origin + cell(25, 3));
      // The gap between two cells.
      await tester.tapAt(
        origin +
            Offset(25 * pitch + ActivityHeatmap.cellSize + 1, cell(0, 2).dy),
      );
      await tester.pump();

      expect(taps, [DateTime(2026, 10, 14), DateTime(2026, 10, 12)]);
    });

    test('levels and grid geometry', () {
      expect(ActivityHeatmap.levelFor(0), 0);
      expect(ActivityHeatmap.levelFor(1), 1);
      expect(ActivityHeatmap.levelFor(3), 3);
      expect(ActivityHeatmap.levelFor(9), 4);
      expect(ActivityHeatmap.gridWidthFor(26), 26 * 15 - 3);
      expect(
        ActivityHeatmap.gridStart(today, 26),
        DateTime(2026, 10, 12).subtract(const Duration(days: 25 * 7)),
      );
      final start = ActivityHeatmap.gridStart(today, 26);
      expect(ActivityHeatmap.dayAt(const Offset(6, 20), start, today), start);
      expect(ActivityHeatmap.dayAt(const Offset(6, 4), start, today), isNull);
      expect(ActivityHeatmap.dayAt(const Offset(13, 20), start, today), isNull);
    });
  });
}
