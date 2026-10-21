import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../mannequin/mannequin_3d.dart';
import '../mannequin/mannequin_clips.dart';
import '../mannequin/rig.dart';
import 'figure_assets.dart';
import 'figure_model.dart';
import 'figure_painter.dart';

/// The detailed guide: a skinned human body playing the movement's clip,
/// with the working muscles lit. Same contract as [Mannequin3D]; falls
/// back to it while the body loads or if the asset is unavailable.
class Figure3D extends StatefulWidget {
  const Figure3D({
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

  /// Mannequin parts to flag (hips, torso, arms, legs): mapped to muscle
  /// groups drawn in the warning colour.
  final Set<String> highlight;

  /// Muscle groups to light up (material name → 0..1).
  final MuscleEmphasis emphasis;
  final bool showFloor;
  final bool compact;

  /// Mannequin "parts" → body materials for form warnings.
  static const partMaterials = {
    'hips': {'glutes', 'core'},
    'torso': {'core', 'back', 'chest'},
    'arms': {'biceps', 'triceps', 'shoulders'},
    'legs': {'quads', 'hamstrings', 'calves'},
  };

  /// How long a change of movement cross-fades between the two poses.
  static const crossFadeMs = 420;

  @override
  State<Figure3D> createState() => _Figure3DState();
}

class _Figure3DState extends State<Figure3D>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _clock = ValueNotifier<int>(0);
  late MannequinClip _clip;
  late MannequinFrame _frame;
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;
  DateTime? _lastDrag;
  int _epoch = 0;
  FigureModel? _model;
  int _lastPaintMs = -1000;

  // Cross-fade from the previous movement.
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
    _model = FigureAssets.modelIfLoaded;
    if (_model == null) {
      FigureAssets.load().then((m) {
        if (mounted && m != null) setState(() => _model = m);
      });
    }
  }

  @override
  void didUpdateWidget(covariant Figure3D old) {
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
    final model = _model;
    if (model == null) {
      return Mannequin3D(
        clipId: widget.clipId,
        size: widget.size,
        playing: widget.playing,
        interactive: widget.interactive,
        autoRotate: widget.autoRotate,
        initialYaw: widget.initialYaw,
        initialPitch: widget.initialPitch,
        highlight: widget.highlight,
        showFloor: widget.showFloor,
        compact: widget.compact,
      );
    }
    final animation = model.animations[widget.clipId];
    final warn = <String>{
      for (final part in {...widget.highlight, ..._clip.highlight})
        ...?Figure3D.partMaterials[part],
    };
    final body = AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        var now = _clock.value;
        // Picture-in-picture runs at 30 fps to leave the CPU to the camera.
        if (widget.compact && widget.playing) {
          if (now - _lastPaintMs < 33 && _lastPaintMs >= 0) {
            now = _lastPaintMs;
          } else {
            _lastPaintMs = now;
          }
        }
        final ms = math.max(0, now - _epoch);
        final idleFor = _lastDrag == null
            ? 1e9
            : DateTime.now().difference(_lastDrag!).inMilliseconds.toDouble();
        final yaw = widget.autoRotate && idleFor > 2500
            ? _yaw + math.sin(now / 4200) * 22
            : _yaw;
        final time = widget.playing ? _clip.framePosition(ms) : 0.0;
        final sinceSwitch = now - _switchMs;
        final fading = _fromClip != null && sinceSwitch < Figure3D.crossFadeMs;
        final blendU = fading
            ? (sinceSwitch / Figure3D.crossFadeMs).clamp(0.0, 1.0)
            : 1.0;
        // Smooth-step the fade so neither pose snaps.
        final blend = blendU * blendU * (3 - 2 * blendU);
        return RepaintBoundary(
          child: CustomPaint(
            painter: FigurePainter(
              model: model,
              animation: animation,
              time: time,
              yaw: yaw,
              pitch: _pitch,
              showFloor: widget.showFloor,
              compact: widget.compact,
              frame: _frame,
              emphasis: widget.emphasis,
              warn: warn,
              fromAnimation: fading ? model.animations[_fromClip!.id] : null,
              fromTime: fading
                  ? _fromClip!.framePosition(math.max(0, now - _fromEpoch))
                  : 0,
              blend: blend,
              // Idle life is strongest on big cards; the picture-in-picture
              // keeps a hint so it never looks frozen.
              lifeTime: widget.playing ? now / 1000 : null,
              lifeAmount: widget.compact ? 0.5 : 1,
            ),
            child: const SizedBox.expand(),
          ),
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
