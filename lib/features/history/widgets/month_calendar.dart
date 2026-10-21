import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/utils/date_utils.dart';
import '../../strength/widgets/activity_heatmap.dart';

/// One month of workout days, Monday first. Cells are tinted by workout
/// count (same levels as [ActivityHeatmap]), starred days mark a completed
/// daily challenge, empty rest weekdays show a dot and future days are
/// dimmed and inert.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    this.intensity = const {},
    this.starred = const {},
    this.restWeekdays = const {},
    this.today,
    this.onTapDay,
    this.onMonthChanged,
    this.compact = false,
  });

  /// Any day inside the month to show.
  final DateTime month;

  /// Workout count per day, keyed by local midnight (other times are
  /// normalised).
  final Map<DateTime, int> intensity;

  /// Days on which the daily challenge was completed.
  final Set<DateTime> starred;

  /// Weekdays ([DateTime.monday]..[DateTime.sunday]) planned as rest days.
  final Set<int> restWeekdays;

  /// Defaults to now. Days after this are dimmed and not tappable.
  final DateTime? today;
  final void Function(DateTime day)? onTapDay;

  /// Called with the first day of the newly selected month. Omit to hide
  /// the month arrows' behaviour (they render disabled).
  final void Function(DateTime month)? onMonthChanged;
  final bool compact;

  static const weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// First day of the month containing [day].
  static DateTime monthStart(DateTime day) => DateTime(day.year, day.month);

  /// Accessibility description of one cell, e.g.
  /// "Oct 21: 2 workouts, challenge done".
  static String semanticLabelFor({
    required DateTime day,
    required int count,
    bool starred = false,
    bool rest = false,
    bool today = false,
    bool future = false,
  }) {
    final b = StringBuffer(DateFormat.MMMd().format(day))
      ..write(': ')
      ..write(count == 1 ? '1 workout' : '$count workouts');
    if (starred) b.write(', challenge done');
    if (rest && count == 0) b.write(', rest day');
    if (today) b.write(', today');
    if (future) b.write(', upcoming');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final todayDate = AppDateUtils.dateOnly(today ?? DateTime.now());
    final first = monthStart(month);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final leading = first.weekday - DateTime.monday;
    final rows = ((leading + daysInMonth) / 7).ceil().clamp(1, 6);
    final nextMonth = DateTime(first.year, first.month + 1);
    final canGoNext =
        onMonthChanged != null && !nextMonth.isAfter(monthStart(todayDate));

    final counts = <int, int>{};
    for (final e in intensity.entries) {
      final key = AppDateUtils.dateOnly(e.key).millisecondsSinceEpoch;
      counts[key] = (counts[key] ?? 0) + e.value;
    }
    final stars = {
      for (final d in starred) AppDateUtils.dateOnly(d).millisecondsSinceEpoch,
    };

    final gap = compact ? 3.0 : 5.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.hasBoundedWidth
            ? ((constraints.maxWidth - gap * 6) / 7).floorToDouble().clamp(
                16.0,
                compact ? 40.0 : 56.0,
              )
            : (compact ? 32.0 : 44.0);
        final gridWidth = cell * 7 + gap * 6;

        final weekRows = <Widget>[];
        for (var r = 0; r < rows; r++) {
          final cells = <Widget>[];
          for (var c = 0; c < 7; c++) {
            if (c > 0) cells.add(SizedBox(width: gap));
            final index = r * 7 + c - leading;
            if (index < 0 || index >= daysInMonth) {
              cells.add(SizedBox(width: cell, height: cell));
              continue;
            }
            final day = DateTime(first.year, first.month, index + 1);
            final count = counts[day.millisecondsSinceEpoch] ?? 0;
            cells.add(
              _DayCell(
                day: day,
                size: cell,
                count: count,
                starred: stars.contains(day.millisecondsSinceEpoch),
                rest: restWeekdays.contains(day.weekday),
                isToday: AppDateUtils.isSameDay(day, todayDate),
                future: day.isAfter(todayDate),
                compact: compact,
                onTap: onTapDay,
              ),
            );
          }
          if (r > 0) weekRows.add(SizedBox(height: gap));
          weekRows.add(Row(mainAxisSize: MainAxisSize.min, children: cells));
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : gridWidth,
              child: _Header(
                month: first,
                compact: compact,
                onPrevious: onMonthChanged == null
                    ? null
                    : () => onMonthChanged!(
                        DateTime(first.year, first.month - 1),
                      ),
                onNext: canGoNext ? () => onMonthChanged!(nextMonth) : null,
              ),
            ),
            SizedBox(height: compact ? 4 : 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(
                    width: cell,
                    child: Text(
                      weekdayInitials[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: restWeekdays.contains(i + 1)
                            ? AppColors.textMuted.withValues(alpha: 0.7)
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: compact ? 4 : 8),
            ...weekRows,
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.month,
    required this.compact,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final bool compact;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final density = compact ? VisualDensity.compact : VisualDensity.standard;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          visualDensity: density,
          iconSize: compact ? 20 : 24,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM().format(month),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          visualDensity: density,
          iconSize: compact ? 20 : 24,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.size,
    required this.count,
    required this.starred,
    required this.rest,
    required this.isToday,
    required this.future,
    required this.compact,
    required this.onTap,
  });

  final DateTime day;
  final double size;
  final int count;
  final bool starred;
  final bool rest;
  final bool isToday;
  final bool future;
  final bool compact;
  final void Function(DateTime day)? onTap;

  @override
  Widget build(BuildContext context) {
    final level = ActivityHeatmap.levelFor(count);
    final bright = level >= 3;
    final radius = BorderRadius.circular(compact ? 6 : 9);
    final textColor = future
        ? AppColors.textMuted
        : bright
        ? AppColors.onPrimary
        : level > 0
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    final decoration = BoxDecoration(
      color: ActivityHeatmap.colorForLevel(level),
      borderRadius: radius,
      border: isToday
          ? Border.all(color: AppColors.primary, width: 1.5)
          : level == 0
          ? Border.all(color: AppColors.divider)
          : null,
    );
    final content = Stack(
      children: [
        Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: compact ? 11 : 13,
              fontWeight: isToday || bright ? FontWeight.w800 : FontWeight.w600,
              color: textColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (starred)
          Positioned(
            top: compact ? 1 : 2,
            right: compact ? 1 : 2,
            child: Icon(
              Icons.star_rounded,
              size: compact ? 8 : 10,
              color: bright ? AppColors.onPrimary : AppColors.warning,
            ),
          ),
        if (rest && count == 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: compact ? 2 : 4,
            child: Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
      ],
    );

    final tappable = onTap != null && !future;
    Widget box = tappable
        ? Material(
            color: Colors.transparent,
            child: Ink(
              decoration: decoration,
              child: InkWell(
                borderRadius: radius,
                onTap: () => onTap!(day),
                child: content,
              ),
            ),
          )
        : DecoratedBox(decoration: decoration, child: content);
    if (future) box = Opacity(opacity: 0.35, child: box);

    return Semantics(
      label: MonthCalendar.semanticLabelFor(
        day: day,
        count: count,
        starred: starred,
        rest: rest,
        today: isToday,
        future: future,
      ),
      button: tappable,
      excludeSemantics: true,
      child: SizedBox(width: size, height: size, child: box),
    );
  }
}
