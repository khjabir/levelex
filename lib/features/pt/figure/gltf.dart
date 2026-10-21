import 'dart:convert';
import 'dart:typed_data';

/// A minimal glTF 2.0 / GLB reader: enough for a skinned, animated body
/// (positions, normals, joints, weights, indices, materials, skins and
/// TRS animations). No textures, no morph targets, no extensions.
class Gltf {
  Gltf._(this.json, this._bin);

  final Map<String, dynamic> json;
  final ByteData? _bin;

  static const _magic = 0x46546C67; // 'glTF'

  /// Parses a `.glb` container (JSON chunk + one BIN chunk).
  factory Gltf.fromGlb(ByteData data) {
    if (data.lengthInBytes < 20 || data.getUint32(0, Endian.little) != _magic) {
      throw const FormatException('Not a GLB file');
    }
    final length = data.getUint32(8, Endian.little);
    var offset = 12;
    Map<String, dynamic>? json;
    ByteData? bin;
    while (offset + 8 <= length) {
      final chunkLength = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      if (chunkType == 0x4E4F534A) {
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes + start,
          chunkLength,
        );
        json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } else if (chunkType == 0x004E4942) {
        bin = ByteData.view(
          data.buffer,
          data.offsetInBytes + start,
          chunkLength,
        );
      }
      offset = start + chunkLength;
    }
    if (json == null) throw const FormatException('GLB without a JSON chunk');
    return Gltf._(json, bin);
  }

  List<dynamic> _list(String key) => (json[key] as List?) ?? const [];

  List<dynamic> get nodes => _list('nodes');
  List<dynamic> get meshes => _list('meshes');
  List<dynamic> get skins => _list('skins');
  List<dynamic> get animations => _list('animations');
  List<dynamic> get materials => _list('materials');
  List<dynamic> get accessors => _list('accessors');
  List<dynamic> get bufferViews => _list('bufferViews');

  /// Scene root node indices.
  List<int> get rootNodes {
    final scenes = _list('scenes');
    if (scenes.isEmpty) return [for (var i = 0; i < nodes.length; i++) i];
    final scene = scenes[(json['scene'] as int?) ?? 0] as Map;
    return [for (final n in (scene['nodes'] as List? ?? const [])) n as int];
  }

  static int _componentSize(int componentType) => switch (componentType) {
    5120 || 5121 => 1,
    5122 || 5123 => 2,
    5125 || 5126 => 4,
    _ => throw FormatException('Unknown componentType $componentType'),
  };

  static int _typeCount(String type) => switch (type) {
    'SCALAR' => 1,
    'VEC2' => 2,
    'VEC3' => 3,
    'VEC4' => 4,
    'MAT4' => 16,
    'MAT3' => 9,
    'MAT2' => 4,
    _ => throw FormatException('Unknown accessor type $type'),
  };

  /// Reads accessor [index] as doubles (normalized integer types are
  /// scaled to 0..1 / −1..1 as the spec requires).
  Float32List readFloats(int index) {
    final acc = accessors[index] as Map;
    final count = acc['count'] as int;
    final components = _typeCount(acc['type'] as String);
    final out = Float32List(count * components);
    _forEachComponent(acc, (i, v) => out[i] = v);
    return out;
  }

  /// Reads an integer accessor (indices, joints).
  Int32List readInts(int index) {
    final acc = accessors[index] as Map;
    final count = acc['count'] as int;
    final components = _typeCount(acc['type'] as String);
    final out = Int32List(count * components);
    _forEachComponent(acc, (i, v) => out[i] = v.toInt(), raw: true);
    return out;
  }

  int accessorCount(int index) => (accessors[index] as Map)['count'] as int;

  void _forEachComponent(
    Map acc,
    void Function(int i, double v) sink, {
    bool raw = false,
  }) {
    final bin = _bin;
    if (bin == null) throw const FormatException('GLB without a BIN chunk');
    final viewIndex = acc['bufferView'] as int?;
    final count = acc['count'] as int;
    final components = _typeCount(acc['type'] as String);
    final componentType = acc['componentType'] as int;
    final normalized = (acc['normalized'] as bool?) ?? false;
    if (viewIndex == null) {
      for (var i = 0; i < count * components; i++) {
        sink(i, 0);
      }
      return;
    }
    final view = bufferViews[viewIndex] as Map;
    final size = _componentSize(componentType);
    final elementSize = size * components;
    final stride = (view['byteStride'] as int?) ?? elementSize;
    final base =
        bin.offsetInBytes +
        ((view['byteOffset'] as int?) ?? 0) +
        ((acc['byteOffset'] as int?) ?? 0);
    final data = ByteData.view(bin.buffer, base);
    var k = 0;
    for (var e = 0; e < count; e++) {
      final start = e * stride;
      for (var c = 0; c < components; c++) {
        final o = start + c * size;
        double v;
        switch (componentType) {
          case 5126:
            v = data.getFloat32(o, Endian.little);
          case 5125:
            v = data.getUint32(o, Endian.little).toDouble();
          case 5123:
            final u = data.getUint16(o, Endian.little);
            v = normalized && !raw ? u / 65535 : u.toDouble();
          case 5122:
            final s = data.getInt16(o, Endian.little);
            v = normalized && !raw ? (s / 32767).clamp(-1, 1) : s.toDouble();
          case 5121:
            final u = data.getUint8(o);
            v = normalized && !raw ? u / 255 : u.toDouble();
          case 5120:
            final s = data.getInt8(o);
            v = normalized && !raw ? (s / 127).clamp(-1, 1) : s.toDouble();
          default:
            throw FormatException('Unknown componentType $componentType');
        }
        sink(k++, v);
      }
    }
  }
}
