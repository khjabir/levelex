import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/face_crop.dart';
import '../models/face_template.dart';
import 'pose_detection_service.dart';

/// Why a frame produced no usable face sample.
enum FaceSampleFailure {
  /// The service has not finished loading the model.
  notReady,
  noFace,
  tooSmall,
  turnedAway,
}

/// One usable face observation.
class FaceSample {
  const FaceSample({
    required this.embedding,
    required this.faceWidthRatio,
    required this.yaw,
    required this.boxLeft,
    required this.boxTop,
    required this.boxWidth,
    required this.boxHeight,
  });

  /// Unit-normalised embedding.
  final List<double> embedding;

  /// Face width as a fraction of the upright frame width.
  final double faceWidthRatio;
  final double yaw;

  /// Bounding box in normalised upright-frame coordinates (0..1).
  final double boxLeft;
  final double boxTop;
  final double boxWidth;
  final double boxHeight;
}

class FaceAnalysis {
  const FaceAnalysis.success(this.sample) : failure = null;
  const FaceAnalysis.failed(this.failure) : sample = null;

  final FaceSample? sample;
  final FaceSampleFailure? failure;
}

/// On-device face verification: ML Kit finds the face, [FaceCropper] builds
/// an aligned 112×112 crop and a bundled MobileFaceNet (TFLite) turns it into
/// an embedding compared with [FaceTemplate]s. No image ever leaves memory.
class FaceService {
  FaceService();

  mlkit.FaceDetector? _detector;
  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  int _inputSize = FaceCropper.outputSize;
  int _embeddingSize = 0;
  bool _busy = false;
  bool _disposed = false;

  bool get isReady => _isolate != null && _detector != null;
  int get embeddingSize => _embeddingSize;

  /// Loads the detector and the embedding model. Safe to call repeatedly.
  Future<void> initialize() async {
    if (isReady || _disposed) return;
    _detector ??= mlkit.FaceDetector(
      options: mlkit.FaceDetectorOptions(
        performanceMode: mlkit.FaceDetectorMode.fast,
        enableLandmarks: true,
        minFaceSize: 0.1,
      ),
    );
    if (_interpreter == null || _isolate == null) {
      final model = await rootBundle.load(FaceConstants.modelAsset);
      if (_disposed) return;
      final interpreter = Interpreter.fromBuffer(model.buffer.asUint8List());
      try {
        final input = interpreter.getInputTensor(0).shape;
        final output = interpreter.getOutputTensor(0).shape;
        _inputSize = input.length >= 3 ? input[1] : FaceCropper.outputSize;
        _embeddingSize = output.last;
        debugPrint('Face model loaded: input $input, output $output');
        final isolate = await IsolateInterpreter.create(
          address: interpreter.address,
        );
        if (_disposed) {
          // Disposed while loading: nothing may outlive the service.
          await isolate.close();
          interpreter.close();
          return;
        }
        _interpreter?.close();
        _interpreter = interpreter;
        _isolate = isolate;
      } catch (e) {
        // Leave nothing half-built, so the next attempt starts clean instead
        // of reporting "ready" checks forever false.
        interpreter.close();
        rethrow;
      }
    }
  }

  /// Detects the largest face in [frame] and embeds it. Returns a failure
  /// when no usable face is present. Drops frames while a previous one is
  /// still being processed.
  Future<FaceAnalysis?> analyze(CameraFrame frame) async {
    if (!isReady) return const FaceAnalysis.failed(FaceSampleFailure.notReady);
    if (_busy) return null;
    _busy = true;
    try {
      final faces = await _detector!.processImage(frame.input);
      if (faces.isEmpty) {
        return const FaceAnalysis.failed(FaceSampleFailure.noFace);
      }
      faces.sort(
        (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
          a.boundingBox.width * a.boundingBox.height,
        ),
      );
      final face = faces.first;
      final box = face.boundingBox;
      final frameW = frame.uprightSize.width;
      final frameH = frame.uprightSize.height;
      final widthRatio = frameW == 0 ? 0.0 : box.width / frameW;
      if (widthRatio < FaceConstants.minFaceWidthRatio) {
        return const FaceAnalysis.failed(FaceSampleFailure.tooSmall);
      }
      final yaw = face.headEulerAngleY ?? 0;
      if (yaw.abs() > FaceConstants.maxHeadYaw) {
        return const FaceAnalysis.failed(FaceSampleFailure.turnedAway);
      }

      final source = _pixelSource(frame);
      if (source == null) {
        return const FaceAnalysis.failed(FaceSampleFailure.noFace);
      }
      final leftEye = face.landmarks[mlkit.FaceLandmarkType.leftEye]?.position;
      final rightEye =
          face.landmarks[mlkit.FaceLandmarkType.rightEye]?.position;
      final tensor = FaceCropper.crop(
        source,
        boxLeft: box.left,
        boxTop: box.top,
        boxWidth: box.width,
        boxHeight: box.height,
        leftEye: leftEye == null
            ? null
            : (x: leftEye.x.toDouble(), y: leftEye.y.toDouble()),
        rightEye: rightEye == null
            ? null
            : (x: rightEye.x.toDouble(), y: rightEye.y.toDouble()),
        rotationDegrees: Platform.isIOS ? 0 : frame.rotation.rawValue,
      );
      final embedding = await _embed(tensor);
      return FaceAnalysis.success(
        FaceSample(
          embedding: embedding,
          faceWidthRatio: widthRatio,
          yaw: yaw,
          boxLeft: frameW == 0 ? 0 : box.left / frameW,
          boxTop: frameH == 0 ? 0 : box.top / frameH,
          boxWidth: widthRatio,
          boxHeight: frameH == 0 ? 0 : box.height / frameH,
        ),
      );
    } catch (e) {
      debugPrint('Face analysis failed: $e');
      return const FaceAnalysis.failed(FaceSampleFailure.noFace);
    } finally {
      _busy = false;
    }
  }

  Future<List<double>> _embed(Float32List tensor) async {
    final isolate = _isolate!;
    final output = [List<double>.filled(_embeddingSize, 0)];
    if (_inputSize != FaceCropper.outputSize) {
      throw StateError('Unexpected model input size $_inputSize');
    }
    await isolate.run(tensor.buffer, output);
    return FaceMatcher.normalize(output.first);
  }

  PixelSource? _pixelSource(CameraFrame frame) {
    final image = frame.image;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    if (Platform.isAndroid) {
      return Nv21PixelSource(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        rowStride: plane.bytesPerRow,
      );
    }
    return BgraPixelSource(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    final detector = _detector;
    _detector = null;
    try {
      await detector?.close();
    } catch (_) {
      // Already closed.
    }
    final isolate = _isolate;
    _isolate = null;
    try {
      await isolate?.close();
    } catch (_) {
      // Already closed.
    }
    _interpreter?.close();
    _interpreter = null;
  }
}
