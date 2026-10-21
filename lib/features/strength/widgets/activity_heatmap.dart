import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/date_utils.dart';

/// A GitHub-style year-at-a-glance grid: one column per week (Monday at the
/// top), the newest week on the right. Scrolls horizontally and starts
/// scrolled to today.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({
    super.key,
    required this.values,
    this.weeks = 26,
    this.today,
    this.onTapDay,
  });

  /// Count per day, keyed by local midnight (other times are normalised).
  final Map<DateTime, int> values;
  final int weeks;
  final DateTime? today;
  final ValueChanged<DateTime>? onTapDay;

  static const cellSize = 12.0;
  static const gap = 3.0;
  static const labelHeight = 14.0;
  static const weekdayLabelWidth = 18.0;
  static const _pitch = cellSize + gap;

  /// Total height of the widget.
  static const height = labelHeight + 7 * _pitch - gap;

  static double gridWidthFor(int weeks) => weeks * _pitch - gap;

  /// Colour level 0–4 for a count.
  static int levelFor(int count) => count <= 0 ? 0 : count.clamp(1, 4);

  static Color colorForLevel(int level) => switch (level) {
    0 => AppColors.surface,
    1 => AppColors.primary.withValues(alpha: 0.25),
    2 => AppColors.primary.withValues(alpha: 0.45),
    3 => AppColors.primary.withValues(alpha: 0.7),
    _ => AppColors.primary,
  };

  /// Monday of the first column.
  static DateTime gridStart(DateTime today, int weeks) {
    final end = AppDateUtils.addDays(
      AppDateUtils.dateOnly(today),
      1 - today.weekday,
    );
    return AppDateUtils.addDays(end, -7 * (weeks - 1));
  }

  @override
  Widget build(BuildContext context) {
    final now = AppDateUtils.dateOnly(today ?? DateTime.now());
    final start = gridStart(now, weeks);
    final counts = <int, int>{};
    for (final e in values.entries) {
      final key = AppDateUtils.dateOnly(e.key).millisecondsSinceEpoch;
      counts[key] = (counts[key] ?? 0) + e.value;
    }

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomPaint(
            size: const Size(weekdayLabelWidth, height),
            painter: _WeekdayLabelsPainter(),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onTapDay == null
                    ? null
                    : (details) {
                        final day = dayAt(details.localPosition, start, now);
                        if (day != null) onTapDay!(day);
                      },
                child: CustomPaint(
                  size: Size(gridWidthFor(weeks), height),
                  painter: _HeatmapPainter(
                    start: start,
                    today: now,
                    weeks: weeks,
                    counts: counts,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The day under [point] in grid coordinates, or null between cells or
  /// after [today].
  static DateTime? dayAt(Offset point, DateTime start, DateTime today) {
    final col = (point.dx / _pitch).floor();
    final row = ((point.dy - labelHeight) / _pitch).floor();
    if (col < 0 || row < 0 || row > 6) return null;
    if (point.dx - col * _pitch > cellSize) return null;
    if (point.dy - labelHeight - row * _pitch > cellSize) return null;
    final day = AppDateUtils.addDays(start, col * 7 + row);
    if (day.isAfter(today)) return null;
    return day;
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.start,
    required this.today,
    required this.weeks,
    required this.counts,
  });

  final DateTime start;
  final DateTime today;
  final int weeks;
  final Map<int, int> counts;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = ActivityHeatmap.cellSize + ActivityHeatmap.gap;
    const radius = Radius.circular(2.5);
    final fills = [
      for (var l = 0; l < 5; l++)
        Paint()..color = ActivityHeatmap.colorForLevel(l),
    ];
    final border = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final labelColumns = <int, String>{};
    for (var col = 0; col < weeks; col++) {
      final monday = AppDateUtils.addDays(start, col * 7);
      for (var row = 0; row < 7; row++) {
        final day = AppDateUtils.addDays(monday, row);
        if (day.isAfter(today)) break;
        if (day.day == 1) labelColumns[col] = _months[day.month - 1];
        final level = ActivityHeatmap.levelFor(
          counts[day.millisecondsSinceEpoch] ?? 0,
        );
        final rect = Rect.fromLTWH(
          col * pitch,
          ActivityHeatmap.labelHeight + row * pitch,
          ActivityHeatmap.cellSize,
          ActivityHeatmap.cellSize,
        );
        final rrect = RRect.fromRectAndRadius(rect, radius);
        canvas.drawRRect(rrect, fills[level]);
        if (level == 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(0.5), radius),
            border,
          );
        }
      }
    }
    if (!labelColumns.containsKey(0) &&
        !labelColumns.containsKey(1) &&
        weeks > 0) {
      labelColumns[0] = _months[start.month - 1];
    }

    for (final e in labelColumns.entries) {
      final text = TextPainter(
        text: TextSpan(text: e.value, style: _labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(e.key * pitch, 0));
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.start != start ||
      old.today != today ||
      old.weeks != weeks ||
      old.counts != counts;
}

class _WeekdayLabelsPainter extends CustomPainter {
  static const _labels = {0: 'M', 2: 'W', 4: 'F'};

  @override
  void paint(Canvas canvas, Size size) {
    const pitch = ActivityHeatmap.cellSize + ActivityHeatmap.gap;
    for (final e in _labels.entries) {
      final text = TextPainter(
        text: TextSpan(text: e.value, style: _HeatmapPainter._labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final top =
          ActivityHeatmap.labelHeight +
          e.key * pitch +
          (ActivityHeatmap.cellSize - text.height) / 2;
      text.paint(canvas, Offset(0, top));
    }
  }

  @override
  bool shouldRepaint(_WeekdayLabelsPainter old) => false;
}
