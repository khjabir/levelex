import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    this.emphasis = const {},
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

  /// Bone parts that do the work (torso, hips, arms, legs): drawn in the
  /// brand colour while the rest of the body goes neutral. Empty keeps the
  /// whole figure in the brand colour.
  final Set<String> emphasis;
  final bool showFloor;

  /// Smaller figure for picture-in-picture use.
  final bool compact;

  /// How long a change of movement cross-fades between the two poses.
  static const crossFadeMs = 420;

  @override
  State<Mannequin3D> createState() => _Mannequin3DState();
}

class _Mannequin3DState extends State<Mannequin3D>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _clock = ValueNotifier<int>(0);
  late MannequinClip _clip;
  late MannequinFrame _frame;
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;
  DateTime? _lastDrag;
  int _epoch = 0;
  MannequinClip? _fromClip;
  int _fromEpoch = 0;
  int _switchMs = -100000;

  @override
  void initState() {
    super.initState();
    _clip = MannequinClips.clip(widget.clipId);
    _frame = MannequinFrame.ofClip(_clip);
    _ticker = createTicker((elapsed) {
      _clock.value = elapsed.inMilliseconds;
    });
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant Mannequin3D old) {
    super.didUpdateWidget(old);
    if (old.clipId != widget.clipId) {
      _fromClip = _clip;
      _fromEpoch = _epoch;
      _switchMs = _clock.value;
      _clip = MannequinClips.clip(widget.clipId);
      _frame = MannequinFrame.ofClip(_clip);
      _epoch = _clock.value;
    }
    if (old.playing != widget.playing) {
      if (widget.playing) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final now = _clock.value;
        final ms = math.max(0, now - _epoch);
        final idleFor = _lastDrag == null
            ? 1e9
            : DateTime.now().difference(_lastDrag!).inMilliseconds.toDouble();
        final yaw = widget.autoRotate && idleFor > 2500
            ? _yaw + math.sin(now / 4200) * 22
            : _yaw;
        final at = widget.playing ? ms : 0;
        var pose = _clip.at(at);
        var offset = _clip.offsetAt(at);
        final sinceSwitch = now - _switchMs;
        if (_fromClip != null && sinceSwitch < Mannequin3D.crossFadeMs) {
          final u = (sinceSwitch / Mannequin3D.crossFadeMs).clamp(0.0, 1.0);
          final k = u * u * (3 - 2 * u);
          final fromMs = math.max(0, now - _fromEpoch);
          pose = RigPose.lerp(_fromClip!.at(fromMs), pose, k);
          final fromOffset = _fromClip!.offsetAt(fromMs);
          offset = fromOffset + (offset - fromOffset) * k;
        }
        return CustomPaint(
          painter: MannequinPainter(
            pose: pose,
            yaw: yaw,
            pitch: _pitch,
            highlight: {...widget.highlight, ..._clip.highlight},
            emphasis: widget.emphasis,
            showFloor: widget.showFloor,
            compact: widget.compact,
            frame: _frame,
            offset: offset,
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
