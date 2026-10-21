import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How much memory the device has, from a tiny platform channel.
class DeviceMemory {
  const DeviceMemory({required this.totalMb, required this.lowRamDevice});

  final int totalMb;

  /// Android's low-RAM flag (iOS: under 3 GB).
  final bool lowRamDevice;

  /// Whether the detailed 3D body is a safe default here.
  bool get detailedGuideOk => !lowRamDevice && totalMb >= 2500;

  static const _channel = MethodChannel('levelex/device');

  static Future<DeviceMemory?> read() async {
    try {
      final raw = await _channel.invokeMethod<Map>('memoryInfo');
      if (raw == null) return null;
      return DeviceMemory(
        totalMb: (raw['totalMb'] as num?)?.toInt() ?? 0,
        lowRamDevice: (raw['lowRamDevice'] as bool?) ?? false,
      );
    } catch (e) {
      debugPrint('Device memory unavailable: $e');
      return null;
    }
  }
}

final deviceMemoryProvider = FutureProvider<DeviceMemory?>(
  (ref) => DeviceMemory.read(),
);
