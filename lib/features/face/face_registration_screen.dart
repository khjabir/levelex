import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/permissions/permission_service.dart';
import '../../services/face_service.dart';
import '../../services/pose_detection_service.dart';
import '../../widgets/primary_button.dart';
import '../workout/widgets/camera_preview_fill.dart';
import 'face_providers.dart';

/// One-time face enrolment. Captures a few embeddings of the user's face and
/// stores their average on the device. No image is saved.
class FaceRegistrationScreen extends ConsumerStatefulWidget {
  const FaceRegistrationScreen({super.key});

  @override
  ConsumerState<FaceRegistrationScreen> createState() =>
      _FaceRegistrationScreenState();
}

enum _Step { intro, starting, capturing, saving, done, error }

class _FaceRegistrationScreenState extends ConsumerState<FaceRegistrationScreen>
    with WidgetsBindingObserver {
  final _camera = PoseDetectionService(
    preferredLens: CameraLensDirection.front,
    detectPoses: false,
  );
  final _face = FaceService();
  final List<List<double>> _samples = [];
  _Step _step = _Step.intro;
  String _hint = 'Look straight at the camera';
  String? _error;
  bool _permanentlyDenied = false;
  FaceSample? _lastSample;
  DateTime? _lastAcceptedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    _face.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _error != null &&
        _permanentlyDenied) {
      // Back from the settings app: if the camera was allowed there, start
      // the scan instead of leaving "Open settings" as the only way out.
      ref.read(permissionServiceProvider).cameraStatus().then((status) {
        if (mounted && status == CameraPermissionResult.granted) _start();
      });
      return;
    }
    if (state != AppLifecycleState.resumed && _step == _Step.capturing) {
      _camera.releaseCamera();
      if (mounted) {
        setState(() {
          _step = _Step.intro;
          _samples.clear();
        });
      }
    }
  }

  Future<void> _start() async {
    setState(() {
      _step = _Step.starting;
      _error = null;
      _samples.clear();
      _lastSample = null;
    });
    final permission = await ref
        .read(permissionServiceProvider)
        .requestCamera();
    if (!mounted) return;
    if (permission != CameraPermissionResult.granted) {
      setState(() {
        _step = _Step.error;
        _permanentlyDenied =
            permission == CameraPermissionResult.permanentlyDenied;
        _error = 'Camera access is needed to register your face.';
      });
      return;
    }
    try {
      await _face.initialize();
      await _camera.initialize();
      await _camera.startStream(
        onPose: (_) {},
        onError: (e) => _failWith(e.userMessage),
      );
      _camera.onFrame = _onFrame;
      if (!mounted) return;
      setState(() => _step = _Step.capturing);
    } on PoseDetectionException catch (e) {
      _failWith(e.userMessage);
    } catch (e) {
      _failWith('Could not start the camera or load the face model.');
      debugPrint('Face registration start failed: $e');
    }
  }

  void _failWith(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.error;
      _error = message;
    });
    _camera.releaseCamera();
  }

  Future<void> _onFrame(CameraFrame frame) async {
    if (_step != _Step.capturing) return;
    final analysis = await _face.analyze(frame);
    if (analysis == null || !mounted || _step != _Step.capturing) return;
    final sample = analysis.sample;
    if (sample == null) {
      setState(() {
        _lastSample = null;
        _hint = switch (analysis.failure) {
          FaceSampleFailure.tooSmall => 'Move closer to the camera',
          FaceSampleFailure.turnedAway => 'Look straight at the camera',
          FaceSampleFailure.notReady => 'Preparing…',
          _ => 'Center your face in the frame',
        };
      });
      return;
    }
    final now = frame.timestamp;
    final last = _lastAcceptedAt;
    // Space the samples out so they cover slightly different moments.
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 600)) {
      setState(() => _lastSample = sample);
      return;
    }
    _lastAcceptedAt = now;
    _samples.add(sample.embedding);
    setState(() {
      _lastSample = sample;
      _hint =
          'Hold still… ${_samples.length}/${FaceConstants.registrationSamples}';
    });
    if (_samples.length >= FaceConstants.registrationSamples) {
      await _save();
    }
  }

  Future<void> _save() async {
    setState(() => _step = _Step.saving);
    _camera.onFrame = null;
    await _camera.releaseCamera();
    try {
      await ref.read(faceTemplateProvider.notifier).register(_samples);
      if (!mounted) return;
      setState(() => _step = _Step.done);
    } catch (e) {
      _failWith('Saving your face failed. Please try again.');
      debugPrint('Face save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alreadyRegistered = ref.watch(faceRegisteredProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Register your face')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: switch (_step) {
            _Step.intro => _Intro(
              alreadyRegistered: alreadyRegistered,
              onStart: _start,
            ),
            _Step.starting => const Center(child: CircularProgressIndicator()),
            _Step.capturing || _Step.saving => Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_camera.controller != null)
                          CameraPreviewFill(
                            controller: _camera.controller!,
                            overlay: CustomPaint(
                              painter: _FaceBoxPainter(
                                sample: _lastSample,
                                mirror: _camera.mirrorPreview,
                              ),
                            ),
                          )
                        else
                          const ColoredBox(color: Colors.black),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 16,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _step == _Step.saving ? 'Saving…' : _hint,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _samples.length / FaceConstants.registrationSamples,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your face is turned into a short numeric signature and '
                  'stored only on this phone. No photo is kept.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            _Step.done => _Done(onDone: () => context.pop()),
            _Step.error => _ErrorView(
              message: _error ?? 'Something went wrong.',
              permanentlyDenied: _permanentlyDenied,
              onRetry: _start,
              onOpenSettings: () =>
                  ref.read(permissionServiceProvider).openSettings(),
            ),
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.alreadyRegistered, required this.onStart});

  final bool alreadyRegistered;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls at large text sizes so the button never ends up off screen.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: _content(context, theme)),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Icon(
          Icons.face_retouching_natural,
          size: 72,
          color: AppColors.secondary,
        ),
        const SizedBox(height: 20),
        Text(
          alreadyRegistered ? 'Face already registered' : 'One-time setup',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          alreadyRegistered
              ? 'Only one face can be registered. To change it, erase your '
                    'face data in Settings; this also erases your score.'
              : 'Before every set the camera checks that it is really you, so '
                    'nobody else can rack up your push-ups. Look straight at '
                    'the camera in good light; it takes a few seconds.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const Spacer(),
        const SizedBox(height: 16),
        if (!alreadyRegistered)
          PrimaryButton(
            label: 'START FACE SCAN',
            icon: Icons.videocam_outlined,
            onPressed: onStart,
          )
        else
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('BACK'),
          ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.verified, size: 80, color: AppColors.primary),
        const SizedBox(height: 20),
        Text(
          'Face registered',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        Text(
          "From now on, sets only count when it's you in front of the camera.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        PrimaryButton(label: 'DONE', icon: Icons.check, onPressed: onDone),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.permanentlyDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String message;
  final bool permanentlyDenied;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const Spacer(),
        if (permanentlyDenied)
          PrimaryButton(
            label: 'OPEN SETTINGS',
            icon: Icons.settings,
            onPressed: onOpenSettings,
          )
        else
          PrimaryButton(
            label: 'TRY AGAIN',
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
      ],
    );
  }
}

/// Draws the detected face box over the preview.
class _FaceBoxPainter extends CustomPainter {
  _FaceBoxPainter({required this.sample, required this.mirror});

  final FaceSample? sample;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    final s = sample;
    if (s == null) return;
    final left = mirror ? 1 - s.boxLeft - s.boxWidth : s.boxLeft;
    final rect = Rect.fromLTWH(
      left * size.width,
      s.boxTop * size.height,
      s.boxWidth * size.width,
      s.boxHeight * size.height,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter old) =>
      old.sample != sample || old.mirror != mirror;
}
