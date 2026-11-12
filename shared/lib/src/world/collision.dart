import 'dart:math' as math;
import 'dart:typed_data';

import '../math.dart';

/// Collision flags.
abstract final class Col {
  /// Blocks player movement.
  static const move = 1;

  /// Blocks bullets, projectiles and line of sight.
  static const shot = 2;
  static const solid = move | shot;

  /// Only bullets hit it (small gadgets like turrets): doesn't block
  /// movement, projectiles or line of sight.
  static const hit = 4;
}

/// Oriented box collider. Map geometry is almost entirely boxes (beveled
/// boxes in the GLBs), so OBBs built from each mesh's local bounds match the
/// visible shape closely; rounded props (barrels, dunes) are approximated.
class Obb {
  final String name;
  final int flags;
  final double cx, cy, cz;
  final double hx, hy, hz;

  /// Unit axes, row-major: u(0..2), v(3..5), w(6..8).
  final Float64List ax;
  final bool aligned;

  /// World AABB (broadphase).
  late final double minX, minY, minZ, maxX, maxY, maxZ;

  Obb(this.name, this.flags, this.cx, this.cy, this.cz, this.hx, this.hy, this.hz, this.ax)
      : aligned = _isIdentity(ax) {
    double ex(int k) => (ax[k] * hx).abs() + (ax[3 + k] * hy).abs() + (ax[6 + k] * hz).abs();
    final ex0 = ex(0), ex1 = ex(1), ex2 = ex(2);
    minX = cx - ex0;
    maxX = cx + ex0;
    minY = cy - ex1;
    maxY = cy + ex1;
    minZ = cz - ex2;
    maxZ = cz + ex2;
  }

  factory Obb.aabb(String name, int flags, double x0, double y0, double z0, double x1, double y1, double z1) => Obb(
      name,
      flags,
      (x0 + x1) / 2,
      (y0 + y1) / 2,
      (z0 + z1) / 2,
      (x1 - x0) / 2,
      (y1 - y0) / 2,
      (z1 - z0) / 2,
      Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]));

  static bool _isIdentity(Float64List a) =>
      (a[0] - 1).abs() < 1e-4 && (a[4] - 1).abs() < 1e-4 && (a[8] - 1).abs() < 1e-4;

  /// Top surface height at (x,z) if that column is inside the box footprint
  /// (exact for aligned boxes, approximate for tilted ramps).
  double get top => maxY;

  /// Closest point on/in the box to p, written into [out]. Returns true if p
  /// is inside.
  bool closest(double px, double py, double pz, List<double> out) {
    final dx = px - cx, dy = py - cy, dz = pz - cz;
    var lu = dx * ax[0] + dy * ax[1] + dz * ax[2];
    var lv = dx * ax[3] + dy * ax[4] + dz * ax[5];
    var lw = dx * ax[6] + dy * ax[7] + dz * ax[8];
    final inside = lu.abs() <= hx && lv.abs() <= hy && lw.abs() <= hz;
    if (inside) {
      // Push out through the nearest face.
      final fu = hx - lu.abs(), fv = hy - lv.abs(), fw = hz - lw.abs();
      if (fu <= fv && fu <= fw) {
        lu = lu >= 0 ? hx : -hx;
      } else if (fv <= fw) {
        lv = lv >= 0 ? hy : -hy;
      } else {
        lw = lw >= 0 ? hz : -hz;
      }
    } else {
      lu = clampD(lu, -hx, hx);
      lv = clampD(lv, -hy, hy);
      lw = clampD(lw, -hz, hz);
    }
    out[0] = cx + lu * ax[0] + lv * ax[3] + lw * ax[6];
    out[1] = cy + lu * ax[1] + lv * ax[4] + lw * ax[7];
    out[2] = cz + lu * ax[2] + lv * ax[5] + lw * ax[8];
    return inside;
  }

  /// Slab test in box space. Distance along normalized ray or null.
  double? rayHit(Vec3 o, Vec3 d, double maxDist) {
    final dx = o.x - cx, dy = o.y - cy, dz = o.z - cz;
    var tmin = 0.0, tmax = maxDist;
    for (var k = 0; k < 3; k++) {
      final a0 = ax[k * 3], a1 = ax[k * 3 + 1], a2 = ax[k * 3 + 2];
      final h = k == 0 ? hx : (k == 1 ? hy : hz);
      final lo = dx * a0 + dy * a1 + dz * a2;
      final ld = d.x * a0 + d.y * a1 + d.z * a2;
      if (ld.abs() < 1e-12) {
        if (lo < -h || lo > h) return null;
      } else {
        final inv = 1 / ld;
        var t1 = (-h - lo) * inv, t2 = (h - lo) * inv;
        if (t1 > t2) {
          final t = t1;
          t1 = t2;
          t2 = t;
        }
        if (t1 > tmin) tmin = t1;
        if (t2 < tmax) tmax = t2;
        if (tmin > tmax) return null;
      }
    }
    return tmin;
  }

  bool containsPoint(double px, double py, double pz, [double pad = 0]) {
    final dx = px - cx, dy = py - cy, dz = pz - cz;
    return (dx * ax[0] + dy * ax[1] + dz * ax[2]).abs() <= hx + pad &&
        (dx * ax[3] + dy * ax[4] + dz * ax[5]).abs() <= hy + pad &&
        (dx * ax[6] + dy * ax[7] + dz * ax[8]).abs() <= hz + pad;
  }

  List<double> toList() => [r(cx), r(cy), r(cz), r(hx), r(hy), r(hz), for (final a in ax) r(a, 5), flags.toDouble()];
}

/// Result of a sphere push-out query.
class Contact {
  double px = 0, py = 0, pz = 0;

  /// Largest upward component among contact normals (ground detection).
  double maxNy = -1;
  int count = 0;
  void reset() {
    px = py = pz = 0;
    maxNy = -1;
    count = 0;
  }
}

/// Static map colliders plus dynamic ones (skill barriers), with a uniform
/// XZ grid broadphase.
class CollisionWorld {
  final List<Obb> statics;
  final double cell;
  late final double gx0, gz0;
  late final int gw, gh;
  late final List<Int32List> _cells;
  final Map<int, Obb> dynamics = {};
  int _nextDyn = 1;

  final List<int> _stamp;
  int _stampId = 0;
  final List<double> _tmp = [0, 0, 0];

  CollisionWorld(this.statics, {this.cell = 2}) : _stamp = List.filled(statics.length, 0) {
    var x0 = double.infinity, z0 = double.infinity, x1 = -double.infinity, z1 = -double.infinity;
    for (final b in statics) {
      x0 = math.min(x0, b.minX);
      z0 = math.min(z0, b.minZ);
      x1 = math.max(x1, b.maxX);
      z1 = math.max(z1, b.maxZ);
    }
    if (statics.isEmpty) x0 = z0 = x1 = z1 = 0;
    gx0 = x0 - cell;
    gz0 = z0 - cell;
    gw = ((x1 - gx0) / cell).ceil() + 2;
    gh = ((z1 - gz0) / cell).ceil() + 2;
    final tmp = List.generate(gw * gh, (_) => <int>[]);
    for (var i = 0; i < statics.length; i++) {
      final b = statics[i];
      for (var cz = _cz(b.minZ); cz <= _cz(b.maxZ); cz++) {
        for (var cx = _cx(b.minX); cx <= _cx(b.maxX); cx++) {
          tmp[cz * gw + cx].add(i);
        }
      }
    }
    _cells = [for (final l in tmp) Int32List.fromList(l)];
  }

  int _cx(double x) => ((x - gx0) / cell).floor().clamp(0, gw - 1);
  int _cz(double z) => ((z - gz0) / cell).floor().clamp(0, gh - 1);

  int addDynamic(Obb b) {
    final id = _nextDyn++;
    dynamics[id] = b;
    return id;
  }

  void removeDynamic(int id) => dynamics.remove(id);

  /// Every collider whose AABB overlaps the XZ rectangle (deduplicated).
  void forEachNear(double x0, double z0, double x1, double z1, int mask, void Function(Obb b) f) {
    _stampId++;
    for (var cz = _cz(z0); cz <= _cz(z1); cz++) {
      for (var cx = _cx(x0); cx <= _cx(x1); cx++) {
        for (final i in _cells[cz * gw + cx]) {
          if (_stamp[i] == _stampId) continue;
          _stamp[i] = _stampId;
          final b = statics[i];
          if (b.flags & mask != 0) f(b);
        }
      }
    }
    for (final b in dynamics.values) {
      if (b.flags & mask != 0 && b.maxX >= x0 && b.minX <= x1 && b.maxZ >= z0 && b.minZ <= z1) f(b);
    }
  }

  /// Sums the push needed to move a sphere out of all overlapping colliders.
  void sphere(double x, double y, double z, double rad, int mask, Contact c) {
    sphereEach(x, y, z, rad, mask, (nx, ny, nz, depth) {
      c.px += nx * depth;
      c.py += ny * depth;
      c.pz += nz * depth;
      if (ny > c.maxNy) c.maxNy = ny;
      c.count++;
    });
  }

  /// Calls [f] with (unit normal, depth) for every collider the sphere
  /// penetrates.
  void sphereEach(double x, double y, double z, double rad, int mask,
      void Function(double nx, double ny, double nz, double depth) f) {
    final t = _tmp;
    forEachNear(x - rad, z - rad, x + rad, z + rad, mask, (b) {
      if (y + rad < b.minY || y - rad > b.maxY) return;
      final inside = b.closest(x, y, z, t);
      var nx = x - t[0], ny = y - t[1], nz = z - t[2];
      final d = math.sqrt(nx * nx + ny * ny + nz * nz);
      double depth;
      if (inside) {
        // Centre is inside: the normal points from centre to the exit face.
        if (d < 1e-9) return;
        nx = -nx / d;
        ny = -ny / d;
        nz = -nz / d;
        depth = d + rad;
      } else {
        if (d >= rad) return;
        if (d < 1e-9) {
          nx = 0;
          ny = 1;
          nz = 0;
        } else {
          nx /= d;
          ny /= d;
          nz /= d;
        }
        depth = rad - d;
      }
      f(nx, ny, nz, depth);
    });
  }

  /// True if a sphere overlaps anything.
  bool sphereHits(double x, double y, double z, double rad, int mask) {
    var hit = false;
    final t = _tmp;
    forEachNear(x - rad, z - rad, x + rad, z + rad, mask, (b) {
      if (hit || y + rad < b.minY || y - rad > b.maxY) return;
      if (b.closest(x, y, z, t)) {
        hit = true;
        return;
      }
      final dx = x - t[0], dy = y - t[1], dz = z - t[2];
      if (dx * dx + dy * dy + dz * dz < rad * rad) hit = true;
    });
    return hit;
  }

  /// First hit along a normalized ray. Returns (distance, collider) or null.
  (double, Obb)? raycast(Vec3 o, Vec3 d, double maxDist, {int mask = Col.shot}) {
    // March the grid in XZ; boxes in visited cells are tested once each.
    double best = maxDist;
    Obb? hit;
    _stampId++;
    void testCell(int cx, int cz) {
      for (final i in _cells[cz * gw + cx]) {
        if (_stamp[i] == _stampId) continue;
        _stamp[i] = _stampId;
        final b = statics[i];
        if (b.flags & mask == 0) continue;
        final t = b.rayHit(o, d, best);
        if (t != null && t < best) {
          best = t;
          hit = b;
        }
      }
    }

    final ex = o.x + d.x * maxDist, ez = o.z + d.z * maxDist;
    var cx = _cx(o.x), cz = _cz(o.z);
    final tx = _cx(ex), tz = _cz(ez);
    final stepX = d.x > 0 ? 1 : -1, stepZ = d.z > 0 ? 1 : -1;
    final tdx = d.x.abs() < 1e-12 ? double.infinity : cell / d.x.abs();
    final tdz = d.z.abs() < 1e-12 ? double.infinity : cell / d.z.abs();
    double nextBound(double g0, int c, int step) => g0 + (c + (step > 0 ? 1 : 0)) * cell;
    var tmx = d.x.abs() < 1e-12 ? double.infinity : (nextBound(gx0, cx, stepX) - o.x) / d.x;
    var tmz = d.z.abs() < 1e-12 ? double.infinity : (nextBound(gz0, cz, stepZ) - o.z) / d.z;
    for (var guard = 0; guard < gw + gh + 4; guard++) {
      testCell(cx, cz);
      final tCell = math.min(tmx, tmz);
      if (best <= tCell || (cx == tx && cz == tz)) break;
      if (tmx < tmz) {
        cx += stepX;
        tmx += tdx;
      } else {
        cz += stepZ;
        tmz += tdz;
      }
      if (cx < 0 || cx >= gw || cz < 0 || cz >= gh) break;
    }
    for (final b in dynamics.values) {
      if (b.flags & mask == 0) continue;
      final t = b.rayHit(o, d, best);
      if (t != null && t < best) {
        best = t;
        hit = b;
      }
    }
    return hit == null ? null : (best, hit!);
  }

  /// Highest walkable surface under (x,z) below [fromY], or null.
  double? groundBelow(double x, double z, double fromY, {double maxDrop = 100}) {
    final h = raycast(Vec3(x, fromY, z), Vec3(0, -1, 0), maxDrop, mask: Col.move);
    return h == null ? null : fromY - h.$1;
  }

  bool lineClear(Vec3 a, Vec3 b, {int mask = Col.shot}) {
    final diff = b - a;
    final len = diff.length;
    if (len < 1e-6) return true;
    final h = raycast(a, diff * (1 / len), len, mask: mask);
    return h == null || h.$1 >= len - 0.02;
  }
}
