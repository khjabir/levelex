import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelex/features/history/widgets/month_calendar.dart';
import 'package:levelex/widgets/badge_tile.dart';
import 'package:levelex/widgets/progress_ring.dart';
import 'package:levelex/widgets/share_card.dart';
import 'package:levelex/widgets/share_sheet.dart';

/// Hosts [child] centred in a MaterialApp; [width]/[height] bound it.
Widget host(Widget child, {double? width, double? height}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: width == null && height == null
          ? child
          : SizedBox(width: width, height: height, child: child),
    ),
  ),
);

const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

final fullCard = ShareCardData(
  headline: 'Set complete',
  title: 'A really long title that must shrink to fit the card width',
  subtitle: 'Push-ups · Level 4 · New personal best for a single set today',
  stats: const [
    ShareStat(label: 'Reps', value: '25'),
    ShareStat(label: 'Time', value: '1:42'),
    ShareStat(label: 'Streak', value: '12 days running'),
    ShareStat(label: 'Form', value: '96%'),
  ],
  date: DateTime(2026, 10, 21),
  footnote: 'Counted on-device by Levelex. No cloud, no account.',
  accent: 'cyan',
);

void main() {
  group('ShareCard', () {
    testWidgets('renders four stats and a long title at 360x450', (
      tester,
    ) async {
      await tester.pumpWidget(host(ShareCard(data: fullCard)));
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ShareCard)), const Size(360, 450));
      expect(find.text('SET COMPLETE'), findsOneWidget);
      expect(find.text(fullCard.title), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('REPS'), findsOneWidget);
      expect(find.text('12 days running'), findsOneWidget);
      expect(find.text('FORM'), findsOneWidget);
      expect(find.text('Oct 21, 2026'), findsOneWidget);
      expect(find.text(fullCard.footnote!), findsOneWidget);
    });

    testWidgets('renders the minimal variant and odd stat counts', (
      tester,
    ) async {
      final minimal = ShareCardData(
        headline: 'Streak',
        title: '7 days',
        date: DateTime(2026, 10, 21),
      );
      await tester.pumpWidget(host(ShareCard(data: minimal)));
      expect(tester.takeException(), isNull);
      expect(find.text('7 days'), findsOneWidget);

      final three = ShareCardData(
        headline: 'Session',
        title: '120 reps',
        stats: const [
          ShareStat(label: 'Sets', value: '5'),
          ShareStat(label: 'Volume', value: '1,250 kg'),
          ShareStat(label: 'Duration', value: '18:04'),
        ],
        date: DateTime(2026, 10, 21),
        accent: 'warning',
      );
      await tester.pumpWidget(host(ShareCard(data: three)));
      expect(tester.takeException(), isNull);
      expect(find.text('DURATION'), findsOneWidget);
    });

    test('accent names map to palette colours', () {
      expect(ShareCardData.accentColorFor('cyan'), const Color(0xFF38E5FF));
      expect(
        ShareCardData.accentColorFor('secondary'),
        const Color(0xFF8B6CFF),
      );
      expect(ShareCardData.accentColorFor('warning'), const Color(0xFFFFB020));
      expect(ShareCardData.accentColorFor('anything'), const Color(0xFF39FF88));
    });
  });

  group('MonthCalendar', () {
    final today = DateTime(2026, 10, 21, 15, 30);
    final intensity = {
      DateTime(2026, 10, 5): 1,
      DateTime(2026, 10, 6, 18, 30): 2,
      DateTime(2026, 10, 7): 3,
      DateTime(2026, 10, 8): 5,
    };
    final starred = {DateTime(2026, 10, 6, 9)};

    testWidgets('renders the month with semantics and tap behaviour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final taps = <DateTime>[];
      final months = <DateTime>[];
      await tester.pumpWidget(
        host(
          MonthCalendar(
            month: DateTime(2026, 10, 14),
            intensity: intensity,
            starred: starred,
            restWeekdays: const {DateTime.sunday},
            today: today,
            onTapDay: taps.add,
            onMonthChanged: months.add,
          ),
          width: 360,
          height: 420,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Oct 6: 2 workouts, challenge done'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Oct 5: 1 workout'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Oct 4: 0 workouts, rest day'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Oct 21: 0 workouts, today'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Oct 28: 0 workouts, upcoming'),
        findsOneWidget,
      );

      // Past day: tappable.
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(taps, [DateTime(2026, 10, 5)]);

      // Future day: inert.
      await tester.tap(find.text('28'), warnIfMissed: false);
      await tester.pump();
      expect(taps, hasLength(1));

      // Current month: next is disabled, previous works.
      final next = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next month'),
          matching: find.byType(IconButton),
        ),
      );
      expect(next.onPressed, isNull);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pump();
      expect(months, [DateTime(2026, 9)]);
      handle.dispose();
    });

    testWidgets('next arrow works for an earlier month', (tester) async {
      final months = <DateTime>[];
      await tester.pumpWidget(
        host(
          MonthCalendar(
            month: DateTime(2026, 8, 3),
            today: today,
            onMonthChanged: months.add,
          ),
          width: 360,
          height: 420,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('August 2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      expect(months, [DateTime(2026, 9)]);
    });

    testWidgets('compact variant fits a narrow width', (tester) async {
      await tester.pumpWidget(
        host(
          MonthCalendar(
            month: DateTime(2026, 3),
            today: today,
            compact: true,
            intensity: {DateTime(2026, 3, 1): 4},
          ),
          width: 240,
          height: 300,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('March 2026'), findsOneWidget);
    });

    test('semantic label wording', () {
      expect(
        MonthCalendar.semanticLabelFor(
          day: DateTime(2026, 10, 21),
          count: 2,
          starred: true,
        ),
        'Oct 21: 2 workouts, challenge done',
      );
    });
  });

  group('BadgeTile', () {
    testWidgets('earned and locked tiles fit a 3-column grid', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: GridView.count(
                crossAxisCount: 3,
                childAspectRatio: 0.8,
                shrinkWrap: true,
                children: [
                  BadgeTile(
                    title: 'First Flame',
                    icon: 'flame',
                    tier: 'gold',
                    earned: true,
                    subtitle: 'Oct 2026',
                    onTap: () => taps++,
                  ),
                  const BadgeTile(
                    title: 'Thirty-day streak champion',
                    icon: 'calendar',
                    tier: 'silver',
                    progress: 0.4,
                    subtitle: '12 / 30',
                  ),
                  const BadgeTile(
                    title: 'Mystery',
                    icon: 'not-a-key',
                    tier: 'bronze',
                    earned: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('First Flame'), findsOneWidget);
      expect(find.text('12 / 30'), findsOneWidget);
      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);

      await tester.tap(find.text('First Flame'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('large variant renders without overflow', (tester) async {
      await tester.pumpWidget(
        host(
          const BadgeTile(
            title: 'Century',
            icon: 'trophy',
            tier: 'gold',
            earned: true,
            large: true,
            subtitle: '100 reps in a set',
          ),
          width: 160,
          height: 200,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Century'), findsOneWidget);
    });

    test('tier colours and icon keys', () {
      expect(BadgeTile.tierColor('gold'), const Color(0xFFFFC53D));
      expect(BadgeTile.tierColor('silver'), const Color(0xFFB8C2CC));
      expect(BadgeTile.tierColor('bronze'), const Color(0xFFCD7F32));
      expect(BadgeTile.icons.length, 17);
      expect(BadgeTile.iconFor('dumbbell'), Icons.fitness_center_rounded);
    });
  });

  group('share sheet', () {
    testWidgets('captureShareCard returns PNG bytes', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: ShareCard(data: fullCard),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      Uint8List? bytes;
      await tester.runAsync(() async {
        final pending = captureShareCard(key);
        // endOfFrame resolves after the next frame; drive it.
        await tester.pump();
        bytes = await pending;
      });
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(pngSignature.length));
      expect(bytes!.sublist(0, pngSignature.length), pngSignature);
    });

    testWidgets('captureShareCard returns null without a boundary', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(host(SizedBox(key: key)));
      Uint8List? bytes;
      await tester.runAsync(() async {
        final pending = captureShareCard(key);
        await tester.pump();
        bytes = await pending;
      });
      expect(bytes, isNull);
    });

    testWidgets('showShareSheet previews the card with a share button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showShareSheet(context, fullCard),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ShareCard), findsOneWidget);
      expect(find.text('SHARE'), findsOneWidget);
      expect(find.textContaining('Save Image'), findsOneWidget);
    });
  });
}
