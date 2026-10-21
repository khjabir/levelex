import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../models/user_settings.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/primary_button.dart';
import '../../../widgets/section_header.dart';
import '../logic/body_weight_stats.dart';
import '../models/lift_log.dart';
import '../strength_providers.dart';
import '../widgets/photo_compare.dart';

/// Body weight with a goal line, weekly means and progress photos with a
/// before/after slider. Everything stays on the phone.
class BodyScreen extends ConsumerStatefulWidget {
  const BodyScreen({super.key});

  @override
  ConsumerState<BodyScreen> createState() => _BodyScreenState();
}

class _BodyScreenState extends ConsumerState<BodyScreen> {
  final _picker = ImagePicker();
  final Set<String> _compare = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = ref.watch(bodyWeightProvider);
    final goal = ref.watch(bodyGoalProvider);
    final unit = ref.watch(weightUnitProvider);
    final photos = ref.watch(progressPhotosProvider);
    final latest = BodyWeightStats.latest(entries);
    final change30 = BodyWeightStats.change(entries, days: 30);
    final trend = BodyWeightStats.trendKgPerWeek(entries);
    final toGoal = goal == null ? null : BodyWeightStats.toGoal(entries, goal);
    final selected = [
      for (final p in photos)
        if (_compare.contains(p.id)) p,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Body'),
        actions: [
          IconButton(
            tooltip: 'Set a goal weight',
            onPressed: () => _editGoal(goal, unit),
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children:
            [
                  AppCard(
                    glow: true,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CURRENT',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: AppColors.textMuted,
                                  letterSpacing: 1.6,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                latest == null ? '—' : unit.format(latest.kg),
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                latest == null
                                    ? 'Log your first weigh-in'
                                    : DateFormat.MMMEd().format(latest.date),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Stat(
                              label: '30 days',
                              value: change30 == null
                                  ? '—'
                                  : '${change30 >= 0 ? '+' : '−'}${unit.format(change30.abs())}',
                              color: AppColors.cyan,
                            ),
                            const SizedBox(height: 6),
                            _Stat(
                              label: 'per week',
                              value: trend == null
                                  ? '—'
                                  : '${trend >= 0 ? '+' : '−'}${unit.format(trend.abs())}',
                              color: AppColors.secondary,
                            ),
                            if (toGoal != null) ...[
                              const SizedBox(height: 6),
                              _Stat(
                                label: 'to goal',
                                value: unit.format(toGoal.abs()),
                                color: AppColors.warning,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: 'LOG WEIGH-IN',
                    icon: Icons.monitor_weight_outlined,
                    onPressed: () => _logWeight(latest?.kg, unit),
                  ),
                  const SizedBox(height: 20),
                  if (entries.length >= 2) ...[
                    const SectionHeader('Trend'),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                      child: SizedBox(
                        height: 190,
                        child: _WeightChart(
                          entries: entries,
                          goalKg: goal,
                          unit: unit,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Day to day the scale moves with water and meals; the '
                      'weekly mean is the number to follow.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                  ],
                  SectionHeader(
                    'Progress photos',
                    trailing: TextButton.icon(
                      onPressed: _addPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Add'),
                    ),
                  ),
                  if (selected.length == 2) ...[
                    SizedBox(
                      height: 360,
                      child: PhotoCompare(
                        before: selected.first,
                        after: selected.last,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (photos.isEmpty)
                    AppCard(
                      child: Text(
                        'Take a photo every few weeks in the same spot and '
                        'light. Pick any two to slide between before and '
                        'after. Photos never leave this phone.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  else ...[
                    Text(
                      selected.length == 2
                          ? 'Drag the handle to compare. Tap a photo to swap it.'
                          : 'Tap two photos to compare them.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 0.78,
                          ),
                      itemCount: photos.length,
                      itemBuilder: (context, i) {
                        final p = photos[photos.length - 1 - i];
                        final on = _compare.contains(p.id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (on) {
                              _compare.remove(p.id);
                            } else {
                              if (_compare.length == 2) {
                                _compare.remove(_compare.first);
                              }
                              _compare.add(p.id);
                            }
                          }),
                          onLongPress: () => _deletePhoto(p),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(p.path), fit: BoxFit.cover),
                                if (on)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 4,
                                    ),
                                    color: Colors.black54,
                                    child: Text(
                                      '${DateFormat.MMMd().format(p.date)} · ${p.pose.label}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (entries.isNotEmpty) ...[
                    const SectionHeader('Weigh-ins'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (
                            var i = entries.length - 1;
                            i >= 0 && i >= entries.length - 14;
                            i--
                          ) ...[
                            if (i != entries.length - 1)
                              const Divider(indent: 16, endIndent: 16),
                            Dismissible(
                              key: ValueKey(entries[i].key),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: AppColors.danger.withValues(alpha: 0.3),
                                child: const Icon(Icons.delete_outline),
                              ),
                              onDismissed: (_) => ref
                                  .read(bodyWeightProvider.notifier)
                                  .remove(entries[i].date),
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  DateFormat.yMMMEd().format(entries[i].date),
                                ),
                                subtitle: entries[i].note == null
                                    ? null
                                    : Text(entries[i].note!),
                                trailing: Text(
                                  unit.format(entries[i].kg),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                onTap: () => _logWeight(
                                  entries[i].kg,
                                  unit,
                                  day: entries[i].date,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ]
                .animate(interval: 40.ms)
                .fadeIn(duration: 260.ms)
                .slideY(begin: 0.04, end: 0, curve: AppTokens.curve),
      ),
    );
  }

  Future<void> _logWeight(
    double? currentKg,
    WeightUnit unit, {
    DateTime? day,
  }) async {
    final controller = TextEditingController(
      text: currentKg == null ? '' : unit.format(currentKg, withUnit: false),
    );
    var date = day ?? DateTime.now();
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Weigh-in'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(suffixText: unit.label),
                onSubmitted: (v) =>
                    Navigator.of(context)
                        .pop(double.tryParse(v.replaceAll(',', '.'))),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => date = picked);
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(DateFormat.yMMMEd().format(date)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(double.tryParse(controller.text.replaceAll(',', '.'))),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result > 0) {
      await ref
          .read(bodyWeightProvider.notifier)
          .log(unit.toKg(result), day: date);
    }
  }

  Future<void> _editGoal(double? goalKg, WeightUnit unit) async {
    final controller = TextEditingController(
      text: goalKg == null ? '' : unit.format(goalKg, withUnit: false),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Goal weight'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: unit.label,
            hintText: 'Leave empty for no goal',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final parsed = double.tryParse(result.replaceAll(',', '.'));
    await ref
        .read(bodyGoalProvider.notifier)
        .set(parsed == null || parsed <= 0 ? null : unit.toKg(parsed));
  }

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 88,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the camera: $e')),
        );
      }
      return;
    }
    if (file == null || !mounted) return;
    final pose = await showDialog<PhotoPose>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Which view?'),
        children: [
          for (final p in PhotoPose.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: Text(p.label),
            ),
        ],
      ),
    );
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/progress_photos');
    if (!await folder.exists()) await folder.create(recursive: true);
    final id = const Uuid().v4();
    final target = File('${folder.path}/$id.jpg');
    await File(file.path).copy(target.path);
    await ref
        .read(progressPhotosProvider.notifier)
        .add(
          ProgressPhoto(
            id: id,
            date: DateTime.now(),
            path: target.path,
            pose: pose ?? PhotoPose.front,
          ),
        );
  }

  Future<void> _deletePhoto(ProgressPhoto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _compare.remove(p.id));
    await ref.read(progressPhotosProvider.notifier).remove(p.id);
    try {
      await File(p.path).delete();
    } catch (_) {}
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({
    required this.entries,
    required this.goalKg,
    required this.unit,
  });

  final List<BodyWeightEntry> entries;
  final double? goalKg;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cutoff = DateTime.now().subtract(const Duration(days: 120));
    var shown = [
      for (final e in entries)
        if (e.date.isAfter(cutoff)) e,
    ];
    if (shown.length < 2) shown = entries;
    final first = shown.first.date;
    double x(DateTime d) => d.difference(first).inHours / 24;
    final spots = [for (final e in shown) FlSpot(x(e.date), unit.fromKg(e.kg))];
    final weekly = BodyWeightStats.weeklyMeans(shown);
    final weeklySpots = [
      for (final w in weekly)
        FlSpot(
          x(w.weekStart.add(const Duration(days: 3))),
          unit.fromKg(w.mean),
        ),
    ];
    var minY = spots.fold<double>(double.infinity, (m, s) => s.y < m ? s.y : m);
    var maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    if (goalKg != null) {
      final g = unit.fromKg(goalKg!);
      if (g < minY) minY = g;
      if (g > maxY) maxY = g;
    }
    final pad = ((maxY - minY) * 0.2).clamp(1.0, 10.0);
    return LineChart(
      LineChartData(
        minY: (minY - pad).floorToDouble(),
        maxY: (maxY + pad).ceilToDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: AppColors.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(0),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (spots.last.x / 4).clamp(1, 400).ceilToDouble(),
              getTitlesWidget: (v, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  DateFormat.MMMd().format(
                    first.add(Duration(days: v.round())),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        extraLinesData: goalKg == null
            ? null
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: unit.fromKg(goalKg!),
                    color: AppColors.warning,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      labelResolver: (_) => 'Goal ${unit.format(goalKg!)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.cardElevated,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.y.toStringAsFixed(1)} ${unit.label}',
                  const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppColors.cyan.withValues(alpha: 0.6),
            barWidth: 1.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 2.5,
                color: AppColors.cyan,
                strokeWidth: 0,
              ),
            ),
          ),
          if (weeklySpots.length >= 2)
            LineChartBarData(
              spots: weeklySpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
    );
  }
}
