import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../pt/models/muscle_group.dart';
import '../logic/recovery.dart';

/// Front and back body silhouettes with each muscle group tinted by its
/// recovery state. Pure vector: crisp at any height.
class MuscleMap extends StatelessWidget {
  const MuscleMap({
    super.key,
    required this.statuses,
    this.onTap,
    this.highlighted,
    this.height = 240,
  });

  final Map<MuscleGroup, MuscleStatus> statuses;
  final ValueChanged<MuscleGroup>? onTap;

  /// Drawn brighter with an outline, e.g. the group the user tapped last.
  final MuscleGroup? highlighted;
  final double height;

  /// Space below the figures taken by the legend (including its gap).
  static const legendHeight = 28.0;

  /// Fill colour for a state; [bright] is the highlighted variant.
  static Color colorFor(MuscleState state, {bool bright = false}) {
    final base = switch (state) {
      MuscleState.fresh => AppColors.textMuted.withValues(alpha: 0.25),
      MuscleState.recovering => AppColors.warning,
      MuscleState.trained => AppColors.primary,
    };
    if (!bright) return base;
    final solid = base.withValues(alpha: math.max(base.a, 0.6));
    return Color.lerp(solid, Colors.white, 0.3)!;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticsLabel(),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  final layout = MuscleMapLayout(size);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: onTap == null
                        ? null
                        : (details) {
                            final group = layout.hitTest(details.localPosition);
                            if (group != null) onTap!(group);
                          },
                    child: CustomPaint(
                      size: size,
                      painter: _MuscleMapPainter(
                        layout: layout,
                        statuses: statuses,
                        highlighted: highlighted,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const _Legend(),
          ],
        ),
      ),
    );
  }

  String _semanticsLabel() {
    final parts = <String>[];
    for (final state in MuscleState.values) {
      final groups = [
        for (final e in statuses.entries)
          if (e.value.state == state &&
              !MuscleRecovery.neverTrained.contains(e.key))
            e.key.label,
      ];
      if (groups.isNotEmpty) parts.add('${state.label}: ${groups.join(', ')}');
    }
    return 'Muscle map. ${parts.join('. ')}';
  }
}

/// One tinted shape on a figure, in figure units (50 wide × 100 tall).
class MuscleRegion {
  const MuscleRegion(this.group, this.rect, {this.radius = 3});

  final MuscleGroup group;
  final Rect rect;
  final double radius;
}

/// Where the two figures and their regions sit inside the paint area.
/// Shared by the painter and the tap hit-test so they always agree.
class MuscleMapLayout {
  MuscleMapLayout(this.size) {
    const captionHeight = 16.0;
    const gap = 18.0;
    final maxByHeight = math.max(0.0, size.height - captionHeight);
    final maxByWidth = math.max(0.0, (size.width - gap) / 2) / aspect;
    final h = math.min(maxByHeight, maxByWidth);
    final w = h * aspect;
    final left = (size.width - (2 * w + gap)) / 2;
    final top = (size.height - captionHeight - h) / 2;
    front = Rect.fromLTWH(left, top, w, h);
    back = Rect.fromLTWH(left + w + gap, top, w, h);
  }

  /// Figure width / height.
  static const aspect = 0.5;

  /// Figure units: 50 wide, 100 tall.
  static const unitWidth = 50.0;
  static const unitHeight = 100.0;

  final Size size;
  late final Rect front;
  late final Rect back;

  static const frontRegions = <MuscleRegion>[
    MuscleRegion(MuscleGroup.chest, Rect.fromLTRB(15.5, 20, 24.5, 28)),
    MuscleRegion(MuscleGroup.chest, Rect.fromLTRB(25.5, 20, 34.5, 28)),
    MuscleRegion(MuscleGroup.shoulders, Rect.fromLTRB(7.5, 19.5, 14, 26.5)),
    MuscleRegion(MuscleGroup.shoulders, Rect.fromLTRB(36, 19.5, 42.5, 26.5)),
    MuscleRegion(
      MuscleGroup.biceps,
      Rect.fromLTRB(7.5, 28, 13, 41),
      radius: 2.5,
    ),
    MuscleRegion(
      MuscleGroup.biceps,
      Rect.fromLTRB(37, 28, 42.5, 41),
      radius: 2.5,
    ),
    MuscleRegion(MuscleGroup.core, Rect.fromLTRB(18.5, 30, 31.5, 48)),
    MuscleRegion(MuscleGroup.quads, Rect.fromLTRB(16, 51, 24, 73)),
    MuscleRegion(MuscleGroup.quads, Rect.fromLTRB(26, 51, 34, 73)),
    MuscleRegion(
      MuscleGroup.calves,
      Rect.fromLTRB(17, 77, 23.5, 95),
      radius: 2.5,
    ),
    MuscleRegion(
      MuscleGroup.calves,
      Rect.fromLTRB(26.5, 77, 33, 95),
      radius: 2.5,
    ),
  ];

  static const backRegions = <MuscleRegion>[
    MuscleRegion(MuscleGroup.back, Rect.fromLTRB(17, 19.5, 33, 27)),
    MuscleRegion(MuscleGroup.back, Rect.fromLTRB(15.5, 28, 34.5, 42)),
    MuscleRegion(MuscleGroup.shoulders, Rect.fromLTRB(7.5, 19.5, 14, 26.5)),
    MuscleRegion(MuscleGroup.shoulders, Rect.fromLTRB(36, 19.5, 42.5, 26.5)),
    MuscleRegion(
      MuscleGroup.triceps,
      Rect.fromLTRB(7.5, 28, 13, 41),
      radius: 2.5,
    ),
    MuscleRegion(
      MuscleGroup.triceps,
      Rect.fromLTRB(37, 28, 42.5, 41),
      radius: 2.5,
    ),
    MuscleRegion(MuscleGroup.glutes, Rect.fromLTRB(15.5, 44, 24.5, 54)),
    MuscleRegion(MuscleGroup.glutes, Rect.fromLTRB(25.5, 44, 34.5, 54)),
    MuscleRegion(MuscleGroup.hamstrings, Rect.fromLTRB(16, 56, 24, 74)),
    MuscleRegion(MuscleGroup.hamstrings, Rect.fromLTRB(26, 56, 34, 74)),
    MuscleRegion(
      MuscleGroup.calves,
      Rect.fromLTRB(17, 77, 23.5, 95),
      radius: 2.5,
    ),
    MuscleRegion(
      MuscleGroup.calves,
      Rect.fromLTRB(26.5, 77, 33, 95),
      radius: 2.5,
    ),
  ];

  /// A region rect in paint coordinates.
  static Rect toCanvas(Rect figure, Rect unit) {
    final s = figure.height / unitHeight;
    return Rect.fromLTWH(
      figure.left + unit.left * s,
      figure.top + unit.top * s,
      unit.width * s,
      unit.height * s,
    );
  }

  /// The group under [point], or null.
  MuscleGroup? hitTest(Offset point) {
    for (final (figure, regions) in [
      (front, frontRegions),
      (back, backRegions),
    ]) {
      if (!figure.contains(point)) continue;
      for (final region in regions) {
        if (toCanvas(figure, region.rect).contains(point)) return region.group;
      }
    }
    return null;
  }

  /// Centre of the first region of [group] on one figure, or null when the
  /// group is not drawn there.
  Offset? regionCenter(MuscleGroup group, {required bool front}) {
    final figure = front ? this.front : back;
    for (final region in front ? frontRegions : backRegions) {
      if (region.group == group) return toCanvas(figure, region.rect).center;
    }
    return null;
  }
}

class _MuscleMapPainter extends CustomPainter {
  _MuscleMapPainter({
    required this.layout,
    required this.statuses,
    required this.highlighted,
  });

  final MuscleMapLayout layout;
  final Map<MuscleGroup, MuscleStatus> statuses;
  final MuscleGroup? highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.front.height <= 0) return;
    _paintFigure(canvas, layout.front, MuscleMapLayout.frontRegions, 'Front');
    _paintFigure(canvas, layout.back, MuscleMapLayout.backRegions, 'Back');
  }

  void _paintFigure(
    Canvas canvas,
    Rect figure,
    List<MuscleRegion> regions,
    String caption,
  ) {
    final silhouette = _silhouette(figure);
    canvas.drawPath(silhouette, Paint()..color = AppColors.cardElevated);

    for (final region in regions) {
      final status = statuses[region.group];
      final state = status?.state ?? MuscleState.fresh;
      final bright = region.group == highlighted;
      final rect = MuscleMapLayout.toCanvas(figure, region.rect);
      final radius = Radius.circular(
        region.radius * figure.height / MuscleMapLayout.unitHeight,
      );
      final rrect = RRect.fromRectAndRadius(rect, radius);
      canvas.drawRRect(
        rrect,
        Paint()..color = MuscleMap.colorFor(state, bright: bright),
      );
      if (bright) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = AppColors.textPrimary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    canvas.drawPath(
      silhouette,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );

    final text = TextPainter(
      text: TextSpan(
        text: caption,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
          letterSpacing: 0.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      Offset(figure.center.dx - text.width / 2, figure.bottom + 3),
    );
  }

  /// Head, neck, torso, arms and legs merged into one outline.
  static Path _silhouette(Rect figure) {
    final s = figure.height / MuscleMapLayout.unitHeight;
    Offset p(double x, double y) =>
        Offset(figure.left + x * s, figure.top + y * s);
    RRect part(double l, double t, double r, double b, double radius) =>
        RRect.fromRectAndRadius(
          Rect.fromPoints(p(l, t), p(r, b)),
          Radius.circular(radius * s),
        );

    var path = Path()
      ..addOval(Rect.fromCircle(center: p(25, 8), radius: 6.5 * s));
    final parts = <Path>[
      Path()..addRRect(part(22, 13, 28, 19, 1.5)),
      Path()
        ..moveTo(p(13.5, 18.5).dx, p(13.5, 18.5).dy)
        ..lineTo(p(36.5, 18.5).dx, p(36.5, 18.5).dy)
        ..quadraticBezierTo(
          p(37, 35).dx,
          p(37, 35).dy,
          p(35, 51).dx,
          p(35, 51).dy,
        )
        ..lineTo(p(15, 51).dx, p(15, 51).dy)
        ..quadraticBezierTo(
          p(13, 35).dx,
          p(13, 35).dy,
          p(13.5, 18.5).dx,
          p(13.5, 18.5).dy,
        )
        ..close(),
      Path()..addRRect(part(6.5, 18.5, 13.5, 43, 3)),
      Path()..addRRect(part(36.5, 18.5, 43.5, 43, 3)),
      Path()..addRRect(part(5.5, 42, 12, 63, 2.5)),
      Path()..addRRect(part(38, 42, 44.5, 63, 2.5)),
      Path()..addRRect(part(15, 49, 24.5, 76, 3)),
      Path()..addRRect(part(25.5, 49, 35, 76, 3)),
      Path()..addRRect(part(16, 75, 24, 98, 3)),
      Path()..addRRect(part(26, 75, 34, 98, 3)),
    ];
    for (final part in parts) {
      path = Path.combine(PathOperation.union, path, part);
    }
    return path;
  }

  @override
  bool shouldRepaint(_MuscleMapPainter old) =>
      old.statuses != statuses ||
      old.highlighted != highlighted ||
      old.layout.size != layout.size;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MuscleMap.legendHeight - 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final state in MuscleState.values) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: MuscleMap.colorFor(state),
                borderRadius: BorderRadius.circular(3),
                border: state == MuscleState.fresh
                    ? Border.all(color: AppColors.outline)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              state.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            if (state != MuscleState.values.last) const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }
}
