import 'dart:math' as math;
import 'dart:typed_data';

import '../content/maps.dart';
import '../math.dart';
import 'collision.dart';
import 'glb.dart';

/// A spawn point (feet position + facing).
class SpawnPoint {
  final Vec3 pos;
  final double yaw;
  const SpawnPoint(this.pos, this.yaw);
}

/// Everything the simulation needs from a map GLB: colliders, spawn points,
/// spawn rooms, capture zone and kill height. Built at load time from the same
/// GLB the client renders, so collision always matches the art.
class GameMap {
  final MapDef def;
  final CollisionWorld world;

  /// Per team (0 = A at +Z, 1 = B at -Z).
  final List<List<SpawnPoint>> spawns;

  /// Spawn room floor rectangles [x0,z0,x1,z1] per team (shop + protection).
  final List<List<double>> spawnRooms;
  final Vec3 capture;
  final double captureRadius;
  final double killY;
  final List<double> bounds; // x0,z0,x1,z1
  final List<String> skipped;

  GameMap._(this.def, this.world, this.spawns, this.spawnRooms, this.capture, this.captureRadius, this.killY,
      this.bounds, this.skipped);

  bool inSpawnRoom(int team, Vec3 p) {
    final r = spawnRooms[team];
    return p.x >= r[0] && p.x <= r[2] && p.z >= r[1] && p.z <= r[3] && p.y < 6;
  }

  bool inCapture(Vec3 feet) =>
      feet.distanceXZ(capture) <= captureRadius && feet.y > capture.y - 2.0 && feet.y < capture.y + 2.5;

  factory GameMap.fromGlb(MapDef def, Uint8List bytes) => GameMap.build(def, Glb.parse(bytes));

  /// Hand-made map for unit tests.
  factory GameMap.synthetic(List<Obb> colliders,
      {required List<List<SpawnPoint>> spawns,
      required List<List<double>> spawnRooms,
      Vec3? capture,
      double captureRadius = 4,
      double killY = -5}) {
    final world = CollisionWorld(colliders);
    var x0 = double.infinity, z0 = double.infinity, x1 = -double.infinity, z1 = -double.infinity;
    for (final b in colliders) {
      x0 = math.min(x0, b.minX);
      z0 = math.min(z0, b.minZ);
      x1 = math.max(x1, b.maxX);
      z1 = math.max(z1, b.maxZ);
    }
    return GameMap._(const MapDef(id: 'synthetic', name: 'synthetic', file: ''), world, spawns, spawnRooms,
        capture ?? Vec3(0, 0, 0), captureRadius, killY, [x0, z0, x1, z1], const []);
  }

  factory GameMap.build(MapDef def, Glb g) {
    final raw = <Obb>[];
    final skipped = <String>[];
    final pads = <int, List<(double, double, double)>>{0: [], 1: []};
    final rooms = <int, List<double>>{};
    final stairs = <String, List<(List<double>, List<double>)>>{};

    g.walk((i, node, w, path) {
      final name = node['name'] as String? ?? '';
      final mesh = node['mesh'];
      if (mesh is! int) return;
      final (mn, mx, mat) = g.meshBounds(mesh)!;
      final (lo, hi) = w.transformBox(mn, mx);

      final pad = RegExp(r'^spawn_([AB])_pad_\d+$').firstMatch(name);
      if (pad != null) {
        pads[pad.group(1) == 'A' ? 0 : 1]!.add(((lo[0] + hi[0]) / 2, hi[1], (lo[2] + hi[2]) / 2));
      }
      final floor = RegExp(r'^spawn_([AB])_floor$').firstMatch(name);
      if (floor != null) rooms[floor.group(1) == 'A' ? 0 : 1] = [lo[0], lo[2], hi[0], hi[2]];

      final flags = _flagsFor(name, mat, lo, hi);
      if (flags == 0) {
        skipped.add(name);
        return;
      }
      if (_mound.hasMatch(name)) {
        raw.addAll(_tiers(name, flags, g.meshPositions(mesh), w));
        return;
      }
      final tread = _stairTread.firstMatch(name);
      if (tread != null) {
        // Visible treads still stop bullets; players walk on a ramp instead.
        stairs.putIfAbsent(tread.group(1)!, () => []).add((lo, hi));
        raw.add(_obbFrom(name, Col.shot, mn, mx, w));
        return;
      }
      raw.add(_obbFrom(name, flags, mn, mx, w));
    });
    if (stairs.isNotEmpty) {
      final solids = CollisionWorld([
        for (final b in raw)
          if (b.flags & Col.move != 0) b
      ]);
      for (final e in stairs.entries) {
        raw.addAll(_stairRamp(e.key, e.value, solids));
      }
    }

    // Drop trim pieces fully inside a larger aligned collider (crate bands,
    // barrel rings, container ribs, snow caps): same shape, fewer tests.
    final kept = <Obb>[];
    final order = [...raw]..sort((a, b) => _vol(b).compareTo(_vol(a)));
    for (final b in order) {
      final redundant = kept.any((k) =>
          k.aligned &&
          k.flags & b.flags == b.flags &&
          b.minX >= k.minX - 0.1 &&
          b.maxX <= k.maxX + 0.1 &&
          b.minY >= k.minY - 0.1 &&
          b.maxY <= k.maxY + 0.1 &&
          b.minZ >= k.minZ - 0.1 &&
          b.maxZ <= k.maxZ + 0.1);
      if (redundant) {
        skipped.add('${b.name}(inside)');
      } else {
        kept.add(b);
      }
    }

    final world = CollisionWorld(kept);
    var x0 = double.infinity, z0 = double.infinity, x1 = -double.infinity, z1 = -double.infinity;
    var minY = double.infinity;
    for (final b in kept) {
      x0 = math.min(x0, b.minX);
      z0 = math.min(z0, b.minZ);
      x1 = math.max(x1, b.maxX);
      z1 = math.max(z1, b.maxZ);
      minY = math.min(minY, b.minY);
    }

    final spawns = <List<SpawnPoint>>[];
    for (var t = 0; t < 2; t++) {
      final list = pads[t]!..sort((a, b) => a.$1.compareTo(b.$1));
      // Team A (z+) faces -Z (yaw 0); team B faces +Z.
      final yaw = t == 0 ? 0.0 : math.pi;
      final pts = <SpawnPoint>[];
      for (final (x, y, z) in list) {
        // Pads are flat discs (no collision); feet stand on the floor below.
        final gy = world.groundBelow(x, z, y + 1.0) ?? y;
        pts.add(SpawnPoint(Vec3(x, gy, z), yaw));
      }
      if (pts.isEmpty) throw StateError('${def.id}: no spawn pads for team $t');
      spawns.add(pts);
    }

    final cap = def.capture;
    final capY = def.captureY ?? world.groundBelow(cap.$1, cap.$2, 40) ?? 0;
    return GameMap._(
      def,
      world,
      spawns,
      [rooms[0] ?? _roomAround(spawns[0]), rooms[1] ?? _roomAround(spawns[1])],
      Vec3(cap.$1, capY, cap.$2),
      def.captureRadius,
      def.killY ?? (minY - 2),
      [x0, z0, x1, z1],
      skipped,
    );
  }

  static List<double> _roomAround(List<SpawnPoint> s) {
    var x0 = double.infinity, z0 = double.infinity, x1 = -double.infinity, z1 = -double.infinity;
    for (final p in s) {
      x0 = math.min(x0, p.pos.x);
      z0 = math.min(z0, p.pos.z);
      x1 = math.max(x1, p.pos.x);
      z1 = math.max(z1, p.pos.z);
    }
    return [x0 - 4, z0 - 4, x1 + 4, z1 + 4];
  }

  static double _vol(Obb b) => b.hx * b.hy * b.hz;

  // ------------------------------------------------------------- rules --

  /// No collision at all: see-through materials (glass, water, glowing pads,
  /// effects) and foliage/decor the brief says must not collide.
  static final _alpha = RegExp(r'_a0\.\d+|_glass');
  static final _decor =
      RegExp(r'canopy|fern|leaf|leaves|vine|moss|rope|cable|banner|flag|lane_strip|door_light|_light\b|light_|lamp|'
          r'sign_glow|neon|smoke|steam|cloud|bird|grass|petal|wire|antenna|window|glow');
  static final _mound = RegExp(r'^(dune|snow_drift|mound)');
  static final _stairTread = RegExp(r'^(.*stair.*?)_(\d+)$');

  /// Staircases in the art are floating treads with tall risers (up to
  /// 0.6 m), sometimes half buried in the block they climb. Movement uses one
  /// sloped slab over the treads instead, like most shooters do for stairs.
  static List<Obb> _stairRamp(String name, List<(List<double>, List<double>)> treads, CollisionWorld solids) {
    if (treads.length < 2) return const [];
    treads.sort((a, b) => a.$2[1].compareTo(b.$2[1]));
    final (lo0, hi0) = treads.first;
    final (lo1, hi1) = treads.last;
    final c0x = (lo0[0] + hi0[0]) / 2, c0z = (lo0[2] + hi0[2]) / 2;
    final c1x = (lo1[0] + hi1[0]) / 2, c1z = (lo1[2] + hi1[2]) / 2;
    var dx = c1x - c0x, dz = c1z - c0z;
    final dl = math.sqrt(dx * dx + dz * dz);
    if (dl < 1e-6) return const [];
    dx /= dl;
    dz /= dl;
    final depth = (hi0[0] - lo0[0]) * dx.abs() + (hi0[2] - lo0[2]) * dz.abs();
    final width = (hi0[0] - lo0[0]) * dz.abs() + (hi0[2] - lo0[2]) * dx.abs();
    // Ramp on the nosing line (front-top edge of every tread), continued over
    // the last tread. Staying on top of the treads keeps it above the blocks
    // the art embeds the stairs in (ziggurat / temple tiers).
    final run = dl / (treads.length - 1);
    final rise = (hi1[1] - hi0[1]) / (treads.length - 1);
    final slope = rise / run;
    var sx = c0x - dx * depth / 2, sz = c0z - dz * depth / 2, sy = hi0[1];
    final ex = c1x + dx * depth / 2, ez = c1z + dz * depth / 2;
    var ey = hi1[1] + slope * depth;

    // Raise the slope until no block along it sticks up more than a small
    // lip, then extend the foot back down to the floor it starts from.
    final len = math.sqrt((ex - sx) * (ex - sx) + (ez - sz) * (ez - sz));
    var deficit = 0.0;
    for (var t = 0.0; t <= len; t += 0.1) {
      for (final off in [-width * 0.4, 0.0, width * 0.4]) {
        final x = sx + dx * t - dz * off, z = sz + dz * t + dx * off;
        final lineY = sy + slope * t;
        // Only blocks poking up to 1 m through the slope count; anything
        // higher is overhead structure (roofs), not a buried stair.
        final from = lineY + 1.0;
        final hit = solids.raycast(Vec3(x, from, z), Vec3(0, -1, 0), 1.5, mask: Col.move);
        if (hit != null && hit.$1 > 0) deficit = math.max(deficit, from - hit.$1 - lineY);
      }
    }
    const lip = 0.15;
    if (deficit > lip) {
      final raise = deficit - lip;
      final floor = solids.groundBelow(sx - dx * 0.05, sz - dz * 0.05, sy + 0.01, maxDrop: 3) ?? sy - rise;
      final back = (sy + raise - floor) / slope;
      sx -= dx * back;
      sz -= dz * back;
      sy = floor;
      ey += raise;
    }
    var ux = ex - sx, uy = ey - sy, uz = ez - sz;
    final ul = math.sqrt(ux * ux + uy * uy + uz * uz);
    ux /= ul;
    uy /= ul;
    uz /= ul;
    // w = horizontal perpendicular, v = u x w flipped to point up.
    final wx = -dz, wz = dx;
    var vx = uy * wz, vy = uz * wx - ux * wz, vz = -uy * wx;
    if (vy < 0) {
      vx = -vx;
      vy = -vy;
      vz = -vz;
    }
    const half = 0.15;
    final ramp = Obb('${name}_ramp', Col.move, (sx + ex) / 2 - vx * half, (sy + ey) / 2 - vy * half,
        (sz + ez) / 2 - vz * half, ul / 2, half, width / 2, Float64List.fromList([ux, uy, uz, vx, vy, vz, wx, 0, wz]));
    // Flat landing past the top: the art sometimes leaves a gap between the
    // last tread and the floor it leads to, wider than the capsule spans.
    const land = 0.8;
    final lx0 = math.min(ex, ex + dx * land), lx1 = math.max(ex, ex + dx * land);
    final lz0 = math.min(ez, ez + dz * land), lz1 = math.max(ez, ez + dz * land);
    final hw = width / 2;
    final landing = Obb.aabb('${name}_landing', Col.move, lx0 - hw * dz.abs(), ey - 2 * half, lz0 - hw * dx.abs(),
        lx1 + hw * dz.abs(), ey, lz1 + hw * dx.abs());
    return [ramp, landing];
  }

  static int _flagsFor(String name, String mat, List<double> lo, List<double> hi) {
    if (_alpha.hasMatch(mat)) return 0;
    if (_decor.hasMatch(name)) return 0;
    final sx = hi[0] - lo[0], sy = hi[1] - lo[1], sz = hi[2] - lo[2];
    if (math.max(sx, math.max(sy, sz)) < 0.25) return 0; // tiny props
    return Col.solid;
  }

  static Obb _obbFrom(String name, int flags, List<double> mn, List<double> mx, Mat4 w) {
    final c = w.apply((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, (mn[2] + mx[2]) / 2);
    final axes = Float64List(9);
    final half = <double>[];
    for (var k = 0; k < 3; k++) {
      final a = w.axis(k);
      final l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
      final s = l < 1e-12 ? 0.0 : 1 / l;
      // Snap near-cardinal axes so slightly-off art doesn't create seams.
      for (var j = 0; j < 3; j++) {
        var v = a[j] * s;
        if ((v.abs() - 1).abs() < 1e-5) v = v.sign;
        if (v.abs() < 1e-5) v = 0;
        axes[k * 3 + j] = v;
      }
      half.add((mx[k] - mn[k]) / 2 * l);
    }
    // Express as identity-axis box when the rotation only permutes axes.
    final perm = [for (var k = 0; k < 9; k++) axes[k].abs()];
    final isPerm = perm.every((v) => v == 0 || v == 1);
    if (isPerm) {
      final ex = [0.0, 0.0, 0.0];
      for (var k = 0; k < 3; k++) {
        for (var j = 0; j < 3; j++) {
          ex[j] += perm[k * 3 + j] * half[k];
        }
      }
      return Obb.aabb(name, flags, c[0] - ex[0], c[1] - ex[1], c[2] - ex[2], c[0] + ex[0], c[1] + ex[1], c[2] + ex[2]);
    }
    return Obb(name, flags, c[0], c[1], c[2], half[0], half[1], half[2], axes);
  }

  /// Rounded mounds (dunes, snow drifts) become stacked boxes with steps
  /// under the auto step height, so players walk over them.
  static List<Obb> _tiers(String name, int flags, Float64List p, Mat4 w) {
    final pts = <List<double>>[];
    for (var i = 0; i + 2 < p.length; i += 3) {
      pts.add(w.apply(p[i], p[i + 1], p[i + 2]));
    }
    if (pts.isEmpty) return const [];
    final y0 = pts.map((e) => e[1]).reduce(math.min);
    final y1 = pts.map((e) => e[1]).reduce(math.max);
    final n = math.max(1, ((y1 - y0) / 0.3).ceil());
    final out = <Obb>[];
    for (var k = 0; k < n; k++) {
      final base = y0 + (y1 - y0) * k / n;
      final top = y0 + (y1 - y0) * (k + 1) / n;
      final sel = pts.where((e) => e[1] >= base - 1e-6).toList();
      if (sel.isEmpty) continue;
      var x0 = sel.map((e) => e[0]).reduce(math.min), x1 = sel.map((e) => e[0]).reduce(math.max);
      var z0 = sel.map((e) => e[2]).reduce(math.min), z1 = sel.map((e) => e[2]).reduce(math.max);
      // Bounding rectangle of an elliptic slice overshoots; pull in a bit.
      final sx = (x1 - x0) * 0.08, sz = (z1 - z0) * 0.08;
      x0 += sx;
      x1 -= sx;
      z0 += sz;
      z1 -= sz;
      if (x1 - x0 < 0.2 || z1 - z0 < 0.2) continue;
      out.add(Obb.aabb('${name}_t$k', flags, x0, y0, z0, x1, top, z1));
    }
    return out;
  }
}
