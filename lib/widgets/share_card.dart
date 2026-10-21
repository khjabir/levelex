import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/theme.dart';
import 'brand_mark.dart';

/// One number on a [ShareCard], e.g. label "Reps", value "25".
class ShareStat {
  const ShareStat({required this.label, required this.value});

  final String label;
  final String value;
}

/// Everything a [ShareCard] needs to render. Pure data so screens can build
/// it from any result (a set, a session, a streak, a record).
class ShareCardData {
  const ShareCardData({
    required this.headline,
    required this.title,
    required this.date,
    this.subtitle,
    this.stats = const [],
    this.footnote,
    this.accent = 'primary',
  }) : assert(stats.length <= 4, 'A share card shows at most four stats');

  /// Small uppercase kicker, e.g. "SET COMPLETE".
  final String headline;

  /// The big line, e.g. "25 push-ups".
  final String title;
  final String? subtitle;

  /// Up to four stats, laid out in a 2×2 grid.
  final List<ShareStat> stats;
  final DateTime date;
  final String? footnote;

  /// One of 'primary', 'cyan', 'secondary' or 'warning'.
  final String accent;

  Color get accentColor => accentColorFor(accent);

  static Color accentColorFor(String accent) => switch (accent) {
    'cyan' => AppColors.cyan,
    'secondary' => AppColors.secondary,
    'warning' => AppColors.warning,
    _ => AppColors.primary,
  };
}

/// A fixed-size (360×450 logical px) result card designed to be rasterised
/// and shared. Dark, branded, with a floor-style grid behind the content.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data});

  final ShareCardData data;

  static const width = 360.0;
  static const height = 450.0;
  static const _radius = AppTokens.radiusLarge;

  @override
  Widget build(BuildContext context) {
    final accent = data.accentColor;
    final subtitle = data.subtitle;
    final footnote = data.footnote;
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.background),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _GridPainter(accent: accent)),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 4,
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.brandGradient),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const BrandWordmark(size: 13),
                        const Spacer(),
                        Text(
                          DateFormat.yMMMd().format(data.date),
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Text(
                      data.headline.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          data.title,
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 46,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.6,
                            height: 1.1,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (data.stats.isNotEmpty) _StatGrid(stats: data.stats),
                    const Spacer(),
                    if (footnote != null)
                      Text(
                        footnote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two tiles per row; an odd count leaves the last slot empty.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<ShareStat> stats;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: _gap));
      rows.add(
        Row(
          children: [
            Expanded(child: _StatTile(stat: stats[i])),
            const SizedBox(width: _gap),
            Expanded(
              child: i + 1 < stats.length
                  ? _StatTile(stat: stats[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final ShareStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 26,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                stat.value,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint floor-style grid (same hairline alpha as the app's 3D floor) with
/// an accent glow in the top-right corner, fading out toward the bottom so
/// the stats stay crisp.
class _GridPainter extends CustomPainter {
  const _GridPainter({required this.accent});

  final Color accent;

  static const _step = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = _step; x < size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = _step; y < size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final fade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.background.withValues(alpha: 0),
          AppColors.background.withValues(alpha: 0.9),
        ],
        stops: const [0.25, 1],
      ).createShader(bounds);
    canvas.drawRect(bounds, fade);

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: 0.22),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 0.04),
              radius: size.width * 0.75,
            ),
          );
    canvas.drawRect(bounds, glow);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.accent != accent;
}
