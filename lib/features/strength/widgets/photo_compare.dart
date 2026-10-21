import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../models/lift_log.dart';

/// Before/after slider: drag the handle to reveal more of either photo.
class PhotoCompare extends StatefulWidget {
  const PhotoCompare({super.key, required this.before, required this.after});

  final ProgressPhoto before;
  final ProgressPhoto after;

  @override
  State<PhotoCompare> createState() => _PhotoCompareState();
}

class _PhotoCompareState extends State<PhotoCompare> {
  double _split = 0.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragUpdate: (d) => setState(
            () => _split = (d.localPosition.dx / w).clamp(0.02, 0.98),
          ),
          onTapDown: (d) => setState(
            () => _split = (d.localPosition.dx / w).clamp(0.02, 0.98),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusLarge),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(widget.after.path), fit: BoxFit.cover),
                ClipRect(
                  clipper: _LeftClipper(_split),
                  child: Image.file(
                    File(widget.before.path),
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  left: w * _split - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
                Positioned(
                  left: w * _split - 18,
                  top: constraints.maxHeight / 2 - 18,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _Tag(
                    DateFormat.yMMMd().format(widget.before.date),
                    theme,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: _Tag(
                    DateFormat.yMMMd().format(widget.after.date),
                    theme,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  const _LeftClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper old) => old.fraction != fraction;
}
