import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mannequin_clips.dart';
import 'mannequin_painter.dart';
import 'rig.dart';

/// Animated 3D figure demonstrating a movement. Rendered with a software
/// perspective projection and depth-sorted shaded capsules, so it needs no
/// model files. Drag to orbit, double-tap to reset.
class Mannequin3D extends StatefulWidget {
  const Mannequin3D({
    super.key,
    required this.clipId,
    this.size,
    this.playing = true,
    this.interactive = true,
    this.autoRotate = true,
    this.initialYaw = -38,
    this.initialPitch = 14,
    this.highlight = const {},
    this.showFloor = true,
    this.compact = false,
  });

  final String clipId;
  final double? size;
  final bool playing;
  final bool interactive;
  final bool autoRotate;
  final double initialYaw;
  final double initialPitch;

  /// Bone parts drawn in the warning colour (e.g. {'hips'}).
  final Set<String> highlight;
  final bool showFloor;

  /// Smaller figure for picture-in-picture use.
  final bool compact;

  @override
  State<Mannequin3D> createState() => _Mannequin3DState();
}

class _Mannequin3DState extends State<Mannequin3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late MannequinClip _clip;
  late MannequinFrame _frame;
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;
  DateTime? _lastDrag;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _clip = MannequinClips.clip(widget.clipId);
    _frame = MannequinFrame.ofClip(_clip);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant Mannequin3D old) {
    super.didUpdateWidget(old);
    if (old.clipId != widget.clipId) {
      _clip = MannequinClips.clip(widget.clipId);
      _frame = MannequinFrame.ofClip(_clip);
      _epoch = _controller.lastElapsedDuration?.inMilliseconds ?? 0;
    }
    if (old.playing != widget.playing) {
      widget.playing ? _controller.repeat() : _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _elapsedMs => (_controller.lastElapsedDuration?.inMilliseconds ?? 0);

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final ms = _elapsedMs - _epoch;
        final idleFor = _lastDrag == null
            ? 1e9
            : DateTime.now().difference(_lastDrag!).inMilliseconds.toDouble();
        final yaw = widget.autoRotate && idleFor > 2500
            ? _yaw + math.sin(ms / 4200) * 22
            : _yaw;
        return CustomPaint(
          painter: MannequinPainter(
            pose: _clip.at(ms < 0 ? 0 : ms),
            yaw: yaw,
            pitch: _pitch,
            highlight: {...widget.highlight, ..._clip.highlight},
            showFloor: widget.showFloor,
            compact: widget.compact,
            frame: _frame,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
    final sized = widget.size == null
        ? body
        : SizedBox(width: widget.size, height: widget.size, child: body);
    if (!widget.interactive) return sized;
    return Semantics(
      label: '3D guide for the movement. Drag to rotate.',
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _yaw -= d.delta.dx * 0.6;
          _pitch = (_pitch + d.delta.dy * 0.4).clamp(-10.0, 60.0);
          _lastDrag = DateTime.now();
        }),
        onDoubleTap: () => setState(() {
          _yaw = widget.initialYaw;
          _pitch = widget.initialPitch;
          _lastDrag = null;
        }),
        child: sized,
      ),
    );
  }
}
