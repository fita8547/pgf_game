/// Minimal GLB (binary glTF 2.0) reader: scene graph, world transforms, mesh
/// bounds and vertex positions. Works on raw bytes so the server (file) and
/// the web client (asset bundle / fetch) can share it. No dependencies.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class Glb {
  final Map<String, dynamic> json;
  final ByteData? bin;
  Glb(this.json, this.bin);

  factory Glb.parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 20 || bd.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('not a GLB');
    }
    final jsonLen = bd.getUint32(12, Endian.little);
    final json = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLen))) as Map<String, dynamic>;
    ByteData? bin;
    final binHeader = 20 + jsonLen;
    if (binHeader + 8 <= bytes.length) {
      final binLen = bd.getUint32(binHeader, Endian.little);
      bin = ByteData.sublistView(bytes, binHeader + 8, binHeader + 8 + binLen);
    }
    return Glb(json, bin);
  }

  List get nodes => json['nodes'] as List? ?? const [];
  List get meshes => json['meshes'] as List? ?? const [];
  List get accessors => json['accessors'] as List? ?? const [];
  List get materials => json['materials'] as List? ?? const [];
  List get animations => json['animations'] as List? ?? const [];
  List<int> get sceneRoots =>
      [for (final n in ((json['scenes'] as List)[(json['scene'] ?? 0) as int]['nodes'] as List)) n as int];

  /// Visits every node depth-first with its world matrix and name path.
  void walk(void Function(int index, Map node, Mat4 world, List<String> path) f) {
    void go(int i, Mat4 parent, List<String> path) {
      final n = nodes[i] as Map;
      final w = parent * Mat4.fromNode(n);
      final p = [...path, (n['name'] ?? '') as String];
      f(i, n, w, p);
      for (final c in (n['children'] as List? ?? const [])) {
        go(c as int, w, p);
      }
    }

    for (final r in sceneRoots) {
      go(r, Mat4.identity(), const []);
    }
  }

  /// Local-space bounds of a mesh (union over primitives) and its first
  /// material name.
  (List<double>, List<double>, String)? meshBounds(int mesh) {
    final m = meshes[mesh] as Map;
    List<double>? mn, mx;
    var mat = '';
    for (final pr in m['primitives'] as List) {
      final a = accessors[(pr['attributes'] as Map)['POSITION'] as int] as Map;
      final amn = [for (final v in a['min'] as List) (v as num).toDouble()];
      final amx = [for (final v in a['max'] as List) (v as num).toDouble()];
      mn = mn == null ? amn : [for (var k = 0; k < 3; k++) math.min(mn[k], amn[k])];
      mx = mx == null ? amx : [for (var k = 0; k < 3; k++) math.max(mx[k], amx[k])];
      final mi = pr['material'];
      if (mat.isEmpty && mi is int && mi < materials.length) mat = (materials[mi]['name'] ?? '') as String;
    }
    return mn == null ? null : (mn, mx!, mat);
  }

  /// Local-space vertex positions of a mesh (all primitives), flat xyz.
  Float64List meshPositions(int mesh) {
    final out = <double>[];
    final b = bin;
    if (b == null) return Float64List(0);
    final views = json['bufferViews'] as List;
    for (final pr in (meshes[mesh] as Map)['primitives'] as List) {
      final a = accessors[(pr['attributes'] as Map)['POSITION'] as int] as Map;
      final v = views[a['bufferView'] as int] as Map;
      final off = ((v['byteOffset'] ?? 0) as int) + ((a['byteOffset'] ?? 0) as int);
      final stride = (v['byteStride'] ?? 12) as int;
      final n = a['count'] as int;
      for (var i = 0; i < n; i++) {
        final o = off + i * stride;
        out
          ..add(b.getFloat32(o, Endian.little))
          ..add(b.getFloat32(o + 4, Endian.little))
          ..add(b.getFloat32(o + 8, Endian.little));
      }
    }
    return Float64List.fromList(out);
  }

  /// Duration (s) of each animation clip, by name.
  Map<String, double> clipDurations() {
    final out = <String, double>{};
    for (final a in animations) {
      var len = 0.0;
      for (final s in (a['samplers'] as List)) {
        final acc = accessors[s['input'] as int] as Map;
        final mx = (acc['max'] as List?)?.first;
        if (mx is num && mx > len) len = mx.toDouble();
      }
      out[(a['name'] ?? '') as String] = len;
    }
    return out;
  }
}

/// Column-major 4x4 matrix (glTF layout).
class Mat4 {
  final Float64List m;
  Mat4(this.m);
  factory Mat4.identity() => Mat4(Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));

  factory Mat4.fromNode(Map n) {
    if (n['matrix'] != null) {
      return Mat4(Float64List.fromList([for (final v in n['matrix'] as List) (v as num).toDouble()]));
    }
    final t = [
      for (final v in (n['translation'] as List? ?? const [0, 0, 0])) (v as num).toDouble()
    ];
    final q = [
      for (final v in (n['rotation'] as List? ?? const [0, 0, 0, 1])) (v as num).toDouble()
    ];
    final s = [
      for (final v in (n['scale'] as List? ?? const [1, 1, 1])) (v as num).toDouble()
    ];
    final x = q[0], y = q[1], z = q[2], w = q[3];
    return Mat4(Float64List.fromList([
      (1 - 2 * (y * y + z * z)) * s[0],
      (2 * (x * y + z * w)) * s[0],
      (2 * (x * z - y * w)) * s[0],
      0,
      (2 * (x * y - z * w)) * s[1],
      (1 - 2 * (x * x + z * z)) * s[1],
      (2 * (y * z + x * w)) * s[1],
      0,
      (2 * (x * z + y * w)) * s[2],
      (2 * (y * z - x * w)) * s[2],
      (1 - 2 * (x * x + y * y)) * s[2],
      0,
      t[0],
      t[1],
      t[2],
      1,
    ]));
  }

  Mat4 operator *(Mat4 o) {
    final r = Float64List(16);
    for (var c = 0; c < 4; c++) {
      for (var row = 0; row < 4; row++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += m[k * 4 + row] * o.m[c * 4 + k];
        }
        r[c * 4 + row] = s;
      }
    }
    return Mat4(r);
  }

  List<double> apply(double x, double y, double z) => [
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
      ];

  List<double> get translation => [m[12], m[13], m[14]];

  /// Yaw (radians, about +Y) of this transform's local +Z axis.
  double get yaw => math.atan2(m[8], m[10]);

  /// True if the rotation maps axes onto axes (0/90/180 degree turns only).
  bool get axisAligned {
    for (var c = 0; c < 3; c++) {
      final l = math.sqrt(m[c * 4] * m[c * 4] + m[c * 4 + 1] * m[c * 4 + 1] + m[c * 4 + 2] * m[c * 4 + 2]);
      if (l < 1e-9) continue;
      var big = 0;
      for (var k = 0; k < 3; k++) {
        final v = (m[c * 4 + k] / l).abs();
        if (v > 1e-3 && v < 1 - 1e-3) return false;
        if (v >= 1 - 1e-3) big++;
      }
      if (big != 1) return false;
    }
    return true;
  }

  /// Column [c] (0 = X axis, 1 = Y, 2 = Z) as a vector, including scale.
  List<double> axis(int c) => [m[c * 4], m[c * 4 + 1], m[c * 4 + 2]];

  /// World AABB of the local box [mn]-[mx].
  (List<double>, List<double>) transformBox(List<double> mn, List<double> mx) {
    final lo = [double.infinity, double.infinity, double.infinity];
    final hi = [-double.infinity, -double.infinity, -double.infinity];
    for (final x in [mn[0], mx[0]]) {
      for (final y in [mn[1], mx[1]]) {
        for (final z in [mn[2], mx[2]]) {
          final p = apply(x, y, z);
          for (var k = 0; k < 3; k++) {
            lo[k] = math.min(lo[k], p[k]);
            hi[k] = math.max(hi[k], p[k]);
          }
        }
      }
    }
    return (lo, hi);
  }
}
