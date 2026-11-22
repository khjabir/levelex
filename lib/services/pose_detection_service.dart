import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;
import 'package:sensors_plus/sensors_plus.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/geometry.dart';
import '../core/utils/gravity.dart';
import '../models/pose_result.dart';

/// Why pose detection could not run.
enum PoseDetectionErrorKind {
  permissionDenied,
  noCamera,
  cameraUnavailable,
  detectorFailed,
}

class PoseDetectionException implements Exception {
  const PoseDetectionException(this.kind, this.message);

  final PoseDetectionErrorKind kind;
  final String message;

  /// Friendly text for the UI.
  String get userMessage => switch (kind) {
    PoseDetectionErrorKind.permissionDenied =>
      'Camera access is needed to count your push-ups.',
    PoseDetectionErrorKind.noCamera => 'No camera was found on this device.',
    PoseDetectionErrorKind.cameraUnavailable =>
      'The camera is not available right now. It may be in use by another '
          'app or interrupted by a call.',
    PoseDetectionErrorKind.detectorFailed =>
      'Pose detection stopped working. Please try again.',
  };

  @override
  String toString() => 'PoseDetectionException($kind): $message';
}

/// A camera frame plus everything needed to interpret it, handed to
/// secondary consumers such as face verification at a low rate.
class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.input,
    required this.rotation,
    required this.uprightSize,
    required this.lensDirection,
    required this.timestamp,
  });

  final CameraImage image;
  final mlkit.InputImage input;

  /// Rotation ML Kit applies to make the image upright (Android only).
  final mlkit.InputImageRotation rotation;

  /// Size of the upright image: the coordinate space of ML Kit results.
  final Size uprightSize;
  final CameraLensDirection lensDirection;
  final DateTime timestamp;
}

/// Owns the camera and the ML Kit pose detector.
///
/// Responsibilities: initialise the front camera, stream frames, throttle and
/// run on-device pose detection, convert ML Kit landmarks into normalised
/// [PoseResult]s, and release everything on [dispose]. Frames never leave the
/// device and are never stored.
class PoseDetectionService {
  PoseDetectionService({
    this.minFrameInterval = CameraConstants.minFrameInterval,
    this.preferredLens = CameraLensDirection.front,
    this.frameHookInterval = CameraConstants.faceCheckInterval,
    this.detectPoses = true,
  });

  /// When false the camera streams frames to [onFrame] only (used by face
  /// registration, which needs no pose detector).
  final bool detectPoses;

  /// Minimum spacing between two inferences (throttling).
  final Duration minFrameInterval;

  /// Minimum spacing between two [onFrame] deliveries.
  final Duration frameHookInterval;

  /// Lens to open next; flipped by [switchCamera].
  CameraLensDirection preferredLens;

  /// Optional low-rate consumer of raw frames (e.g. face verification).
  void Function(CameraFrame frame)? onFrame;
  DateTime? _lastHookAt;

  CameraController? _controller;
  CameraDescription? _camera;
  mlkit.PoseDetector? _detector;

  bool _busy = false;
  bool _streaming = false;
  bool _disposed = false;
  DateTime? _lastProcessedAt;
  int _consecutiveFailures = 0;
  mlkit.InputImageRotation _rotation = mlkit.InputImageRotation.rotation0deg;
  DeviceOrientation _orientation = DeviceOrientation.portraitUp;

  // Low-pass filtered accelerometer reading (device frame, m/s²).
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  Vec3? _accel;
  bool _accelUnavailable = false;

  void Function(PoseResult result)? _onPose;
  void Function(PoseDetectionException error)? _onError;

  static const _failureThreshold = 15;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _streaming;

  /// Lens of the camera currently open (or requested).
  CameraLensDirection get lensDirection =>
      _camera?.lensDirection ?? preferredLens;

  /// Whether another camera with a different lens exists on this device.
  Future<bool> hasOtherCamera() async {
    try {
      final cameras = await availableCameras();
      return cameras.any((c) => c.lensDirection != lensDirection);
    } catch (_) {
      return false;
    }
  }

  /// Closes the current camera and opens the one facing the other way.
  /// Restores the image stream if it was running. Throws on failure.
  Future<void> switchCamera() async {
    final wasStreaming = _streaming;
    final onPose = _onPose;
    final onError = _onError;
    preferredLens = lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    await releaseCamera();
    await initialize();
    if (wasStreaming && onPose != null && onError != null) {
      await startStream(onPose: onPose, onError: onError);
    }
  }

  /// True when the preview is shown mirrored (selfie style), in which case
  /// landmark x coordinates must be flipped when drawn over the preview.
  bool get mirrorPreview {
    final camera = _camera;
    if (camera == null) return false;
    if (Platform.isAndroid) {
      return switch (_rotation) {
        mlkit.InputImageRotation.rotation270deg => true,
        mlkit.InputImageRotation.rotation90deg => false,
        _ => camera.lensDirection == CameraLensDirection.front,
      };
    }
    return switch (_rotation) {
      mlkit.InputImageRotation.rotation90deg ||
      mlkit.InputImageRotation.rotation270deg => false,
      _ => camera.lensDirection == CameraLensDirection.front,
    };
  }

  /// In-flight [initialize], so overlapping calls share it and a release
  /// that arrives meanwhile waits for it instead of missing the camera.
  Future<void>? _initializing;

  /// Opens the camera. Throws [PoseDetectionException] on failure.
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(StateError('PoseDetectionService was disposed'));
    }
    if (isInitialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw _mapCameraException(e);
    }
    if (cameras.isEmpty) {
      throw const PoseDetectionException(
        PoseDetectionErrorKind.noCamera,
        'availableCameras() returned nothing',
      );
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == preferredLens,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      // ML Kit expects NV21 on Android and BGRA8888 on iOS; both give a single
      // plane we can hand over without copying.
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw _mapCameraException(e);
    } catch (e) {
      await controller.dispose();
      throw PoseDetectionException(
        PoseDetectionErrorKind.cameraUnavailable,
        e.toString(),
      );
    }

    _camera = camera;
    _controller = controller;
    _rotation = _computeRotation(camera, controller);
    _orientation = controller.value.deviceOrientation;
    controller.addListener(_onCameraValueChanged);
    _startAccelerometer();

    if (!detectPoses) return;
    try {
      _detector ??= mlkit.PoseDetector(
        options: mlkit.PoseDetectorOptions(
          mode: mlkit.PoseDetectionMode.stream,
          model: mlkit.PoseDetectionModel.base,
        ),
      );
    } catch (e) {
      throw PoseDetectionException(
        PoseDetectionErrorKind.detectorFailed,
        e.toString(),
      );
    }
  }

  /// Starts delivering [PoseResult]s. Safe to call repeatedly.
  Future<void> startStream({
    required void Function(PoseResult result) onPose,
    required void Function(PoseDetectionException error) onError,
  }) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const PoseDetectionException(
        PoseDetectionErrorKind.cameraUnavailable,
        'startStream called before initialize',
      );
    }
    _onPose = onPose;
    _onError = onError;
    if (_streaming) return;
    try {
      await controller.startImageStream(_handleFrame);
      _streaming = true;
    } on CameraException catch (e) {
      throw _mapCameraException(e);
    }
  }

  /// Stops frame delivery but keeps the camera open.
  Future<void> stopStream() async {
    final controller = _controller;
    _streaming = false;
    if (controller == null) return;
    if (controller.value.isInitialized && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (e) {
        debugPrint('stopImageStream failed: $e');
      }
    }
  }

  /// Releases the camera (e.g. when the app goes to background) while keeping
  /// the detector so [initialize] can resume quickly.
  Future<void> releaseCamera() async {
    final pending = _initializing;
    if (pending != null) {
      // Opening right now (e.g. the app was backgrounded while returning):
      // let it finish, then release what it opened.
      try {
        await pending;
      } catch (_) {}
    }
    await stopStream();
    await _accelSubscription?.cancel();
    _accelSubscription = null;
    final controller = _controller;
    _controller = null;
    _camera = null;
    if (controller != null) {
      controller.removeListener(_onCameraValueChanged);
      try {
        await controller.dispose();
      } catch (e) {
        debugPrint('Camera dispose failed: $e');
      }
    }
  }

  /// Releases every native resource. The service cannot be reused afterwards.
  Future<void> dispose() async {
    _disposed = true;
    await releaseCamera();
    final detector = _detector;
    _detector = null;
    _onPose = null;
    _onError = null;
    onFrame = null;
    if (detector != null) {
      try {
        await detector.close();
      } catch (e) {
        debugPrint('Pose detector close failed: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Gravity (which way is down, in image coordinates)
  // ---------------------------------------------------------------------------

  void _startAccelerometer() {
    if (_accelSubscription != null || _accelUnavailable) return;
    try {
      _accelSubscription =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval,
          ).listen(
            (event) {
              final sample = Vec3(event.x, event.y, event.z);
              final previous = _accel;
              // Exponential smoothing removes the shake of a hand-held phone.
              _accel = previous == null
                  ? sample
                  : previous * 0.85 + sample * 0.15;
            },
            onError: (Object e) {
              debugPrint('Accelerometer unavailable: $e');
              _accelUnavailable = true;
            },
            cancelOnError: true,
          );
    } catch (e) {
      debugPrint('Accelerometer unavailable: $e');
      _accelUnavailable = true;
    }
  }

  /// Gravity direction in the upright image frame, or null without a sensor.
  Vec3? get gravity {
    final a = _accel;
    final camera = _camera;
    if (a == null || camera == null) return null;
    return GravityEstimator.gravityInImageFrame(
      ax: a.x,
      ay: a.y,
      az: a.z,
      orientation: _orientation,
      frontCamera: camera.lensDirection == CameraLensDirection.front,
    );
  }

  /// A small integer that changes whenever the frame rotation or camera
  /// changes, so downstream consumers can drop stale comparisons.
  int get orientationTag =>
      _rotation.index * 10 +
      _orientation.index * 2 +
      (_camera?.lensDirection == CameraLensDirection.front ? 1 : 0);

  // ---------------------------------------------------------------------------
  // Frame pipeline
  // ---------------------------------------------------------------------------

  void _onCameraValueChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.hasError) {
      _onError?.call(
        PoseDetectionException(
          PoseDetectionErrorKind.cameraUnavailable,
          controller.value.errorDescription ?? 'camera error',
        ),
      );
    }
  }

  void _handleFrame(CameraImage image) {
    if (!_streaming) return;
    final now = DateTime.now();
    final camera = _camera;
    final controller = _controller;
    if (camera != null && controller != null) {
      // The phone may be turned between portrait and landscape mid-session.
      _rotation = _computeRotation(camera, controller);
      _orientation = controller.value.deviceOrientation;
    }

    final hook = onFrame;
    final lastHook = _lastHookAt;
    if (hook != null &&
        (lastHook == null || now.difference(lastHook) >= frameHookInterval)) {
      final input = _toInputImage(image);
      if (input != null && camera != null) {
        _lastHookAt = now;
        hook(
          CameraFrame(
            image: image,
            input: input,
            rotation: _rotation,
            uprightSize: _uprightSize(image),
            lensDirection: camera.lensDirection,
            timestamp: now,
          ),
        );
      }
    }

    if (!detectPoses || _busy) return;
    final last = _lastProcessedAt;
    if (last != null && now.difference(last) < minFrameInterval) return;
    _busy = true;
    _lastProcessedAt = now;
    _process(image, now).whenComplete(() => _busy = false);
  }

  Future<void> _process(CameraImage image, DateTime timestamp) async {
    final detector = _detector;
    if (detector == null || !_streaming) return;
    final input = _toInputImage(image);
    if (input == null) return;

    try {
      final poses = await detector.processImage(input);
      _consecutiveFailures = 0;
      if (!_streaming) return;
      final uprightSize = _uprightSize(image);
      final g = gravity;
      final tag = orientationTag;
      final result = poses.isEmpty
          ? PoseResult.empty(timestamp, gravity: g, orientationTag: tag)
          : _toPoseResult(poses.first, uprightSize, timestamp, g, tag);
      _onPose?.call(result);
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures == 1) debugPrint('Pose inference failed: $e');
      if (_consecutiveFailures >= _failureThreshold) {
        _consecutiveFailures = 0;
        _onError?.call(
          PoseDetectionException(
            PoseDetectionErrorKind.detectorFailed,
            e.toString(),
          ),
        );
      }
    }
  }

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Rotation ML Kit must apply so the image is upright. Mirrors the logic in
  /// the google_ml_kit_flutter example app.
  mlkit.InputImageRotation _computeRotation(
    CameraDescription camera,
    CameraController controller,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) {
      return mlkit.InputImageRotationValue.fromRawValue(sensorOrientation) ??
          mlkit.InputImageRotation.rotation0deg;
    }
    final deviceOrientation = controller.value.deviceOrientation;
    final compensation = _orientations[deviceOrientation] ?? 0;
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
    return mlkit.InputImageRotationValue.fromRawValue(degrees) ??
        mlkit.InputImageRotation.rotation0deg;
  }

  mlkit.InputImage? _toInputImage(CameraImage image) {
    final format = mlkit.InputImageFormatValue.fromRawValue(
      image.format.raw as int,
    );
    if (format == null) return null;
    if (Platform.isAndroid && format != mlkit.InputImageFormat.nv21) {
      return null;
    }
    if (Platform.isIOS && format != mlkit.InputImageFormat.bgra8888) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Size of the image after ML Kit's rotation, i.e. the coordinate space of
  /// the returned landmarks.
  /// Public for frame consumers that need to map ML Kit coordinates back to
  /// the raw buffer.
  static Size uprightSizeFor(
    CameraImage image,
    mlkit.InputImageRotation rotation,
  ) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    if (Platform.isAndroid &&
        (rotation == mlkit.InputImageRotation.rotation90deg ||
            rotation == mlkit.InputImageRotation.rotation270deg)) {
      return Size(h, w);
    }
    return Size(w, h);
  }

  Size _uprightSize(CameraImage image) => uprightSizeFor(image, _rotation);

  static const _typeMap = {
    mlkit.PoseLandmarkType.nose: LandmarkType.nose,
    mlkit.PoseLandmarkType.leftShoulder: LandmarkType.leftShoulder,
    mlkit.PoseLandmarkType.rightShoulder: LandmarkType.rightShoulder,
    mlkit.PoseLandmarkType.leftElbow: LandmarkType.leftElbow,
    mlkit.PoseLandmarkType.rightElbow: LandmarkType.rightElbow,
    mlkit.PoseLandmarkType.leftWrist: LandmarkType.leftWrist,
    mlkit.PoseLandmarkType.rightWrist: LandmarkType.rightWrist,
    mlkit.PoseLandmarkType.leftHip: LandmarkType.leftHip,
    mlkit.PoseLandmarkType.rightHip: LandmarkType.rightHip,
    mlkit.PoseLandmarkType.leftKnee: LandmarkType.leftKnee,
    mlkit.PoseLandmarkType.rightKnee: LandmarkType.rightKnee,
    mlkit.PoseLandmarkType.leftAnkle: LandmarkType.leftAnkle,
    mlkit.PoseLandmarkType.rightAnkle: LandmarkType.rightAnkle,
  };

  PoseResult _toPoseResult(
    mlkit.Pose pose,
    Size size,
    DateTime timestamp,
    Vec3? gravity,
    int orientationTag,
  ) {
    final landmarks = <LandmarkType, PoseLandmark>{};
    // One scale for all three axes keeps angles and distances undistorted;
    // ML Kit's z shares the pixel scale of x and y.
    final uniform = size.longestSide == 0 ? 1.0 : size.longestSide;
    for (final entry in _typeMap.entries) {
      final lm = pose.landmarks[entry.key];
      if (lm == null) continue;
      landmarks[entry.value] = PoseLandmark(
        type: entry.value,
        x: size.width == 0 ? 0 : lm.x / size.width,
        y: size.height == 0 ? 0 : lm.y / size.height,
        position: Vec3(lm.x / uniform, lm.y / uniform, lm.z / uniform),
        likelihood: lm.likelihood.clamp(0.0, 1.0),
      );
    }
    return PoseResult(
      landmarks: landmarks,
      timestamp: timestamp,
      gravity: gravity,
      orientationTag: orientationTag,
    );
  }

  PoseDetectionException _mapCameraException(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('denied') || code.contains('permission')) {
      return PoseDetectionException(
        PoseDetectionErrorKind.permissionDenied,
        e.description ?? e.code,
      );
    }
    return PoseDetectionException(
      PoseDetectionErrorKind.cameraUnavailable,
      e.description ?? e.code,
    );
  }
}
