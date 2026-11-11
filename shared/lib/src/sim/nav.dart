import 'dart:math' as math;
import 'dart:typed_data';

import '../content/characters.dart';
import '../math.dart';
import '../world/collision.dart';
import '../world/map_loader.dart';
import 'movement.dart';

/// Walkable-cell graph baked at load time from the map colliders (brief §6-12:
/// the GLBs ship without a navmesh). Multi-layer, so floors under bridges,
/// roofs and mezzanines are all represented.
class NavGrid {
  final double cell;
  final double x0, z0;
  final int w, h;

  /// Node positions (feet), flat xyz.
  final Float64List pos;

  /// Column (iz * w + ix) -> node indices on that column.
  final List<Int32List> columns;

  /// Adjacency: node -> neighbour indices.
  final List<Int32List> links;

  /// Bit t set = node is inside team t's spawn room.
  final Uint8List spawnMask;

  NavGrid._(this.cell, this.x0, this.z0, this.w, this.h, this.pos, this.columns, this.links, this.spawnMask);

  int get length => pos.length ~/ 3;
  Vec3 node(int i) => Vec3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]);

  static const double maxUp = 1.05, maxDown = 2.6, jumpUp = 0.45;

  /// Tallest wall a vault link jumps (jump apex is ~1.22 m).
  static const double vaultMax = 1.05;

  factory NavGrid.build(GameMap map, Mover mover, {double cell = 0.75}) {
    final world = map.world;
    final b = map.bounds;
    final x0 = b[0], z0 = b[1];
    final w = ((b[2] - b[0]) / cell).ceil(), h = ((b[3] - b[1]) / cell).ceil();
    var top = -1e9;
    for (final o in world.statics) {
      top = math.max(top, o.maxY);
    }
    top = math.min(top + 1, 30);

    final pts = <double>[];
    final cols = List.generate(w * h, (_) => <int>[]);
    final c = Contact();
    for (var iz = 0; iz < h; iz++) {
      for (var ix = 0; ix < w; ix++) {
        final x = x0 + (ix + 0.5) * cell, z = z0 + (iz + 0.5) * cell;
        var y = top;
        for (var layer = 0; layer < 6; layer++) {
          final hit = world.raycast(Vec3(x, y, z), Vec3(0, -1, 0), y - map.killY, mask: Col.move);
          if (hit == null) break;
          final surf = y - hit.$1;
          if (hit.$1 > 0 && surf > map.killY) {
            c.reset();
            world.sphere(x, surf + playerRadius - 0.06, z, playerRadius - 0.01, Col.move, c);
            // Clearance above step height only: lips the player steps over
            // (spawn floor edges, kerbs) must not cut the graph.
            const lift = Mover.stepHeight * 0.85;
            if (c.maxNy > Mover.walkableNy && mover.capsuleFree(x, surf + lift, z, h: standHeight - lift)) {
              cols[iz * w + ix].add(pts.length ~/ 3);
              pts
                ..add(x)
                ..add(surf)
                ..add(z);
            }
          }
          y = math.min(surf - 0.05, hit.$2.minY - 0.02);
          if (y <= map.killY) break;
        }
      }
    }

    final n = pts.length ~/ 3;
    final links = <Int32List>[];
    for (var i = 0; i < n; i++) {
      final ax = pts[i * 3], ay = pts[i * 3 + 1], az = pts[i * 3 + 2];
      final ix = ((ax - x0) / cell).floor(), iz = ((az - z0) / cell).floor();
      final out = <int>[];
      for (var dz = -1; dz <= 1; dz++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dz == 0) continue;
          final jx = ix + dx, jz = iz + dz;
          if (jx < 0 || jz < 0 || jx >= w || jz >= h) continue;
          for (final j in cols[jz * w + jx]) {
            final bx = pts[j * 3], by = pts[j * 3 + 1], bz = pts[j * 3 + 2];
            final dy = by - ay;
            if (dy > maxUp || dy < -maxDown) continue;
            // Clear above the higher endpoint and no hole in between.
            final hy = math.max(ay, by);
            if (!world.lineClear(Vec3(ax, hy + 0.7, az), Vec3(bx, hy + 0.7, bz), mask: Col.move)) continue;
            if (!world.lineClear(Vec3(ax, hy + 1.4, az), Vec3(bx, hy + 1.4, bz), mask: Col.move)) continue;
            final mg = world.groundBelow((ax + bx) / 2, (az + bz) / 2, hy + 0.6, maxDrop: 4);
            if (mg == null || mg < math.min(ay, by) - 1.0) continue;
            // Diagonals must not cut wall corners.
            if (dx != 0 &&
                dz != 0 &&
                !world.lineClear(Vec3(ax, ay + 0.3 + math.max(0, dy), az), Vec3(bx, by + 0.3, bz), mask: Col.move)) {
              continue;
            }
            out.add(j);
          }
        }
      }
      // Jump links to a node two cells away at about the same height: over a
      // low wall (parapet, crate row) or across a gap/dip.
      for (var dz = -2; dz <= 2; dz += 2) {
        for (var dx = -2; dx <= 2; dx += 2) {
          if (dx == 0 && dz == 0) continue;
          final jx = ix + dx, jz = iz + dz;
          if (jx < 0 || jz < 0 || jx >= w || jz >= h) continue;
          for (final j in cols[jz * w + jx]) {
            final bx = pts[j * 3], by = pts[j * 3 + 1], bz = pts[j * 3 + 2];
            if ((by - ay).abs() > 0.6) continue;
            final hy = math.max(ay, by);
            // Tallest obstacle along the hop (sampled; walls are thin).
            double? top;
            for (final f in const [0.25, 0.375, 0.5, 0.625, 0.75]) {
              final g = world.groundBelow(ax + (bx - ax) * f, az + (bz - az) * f, hy + vaultMax + 0.05,
                  maxDrop: vaultMax + 0.5);
              if (g != null && (top == null || g > top)) top = g;
            }
            if (top != null && top > hy + vaultMax) continue;
            // Either a vault over a low wall, or a hop across a dip/gap.
            final clear = top == null || top < hy + jumpUp ? hy : top;
            if (!world.lineClear(Vec3(ax, clear + 0.45, az), Vec3(bx, clear + 0.45, bz), mask: Col.move)) continue;
            if (!world.lineClear(Vec3(ax, clear + 1.3, az), Vec3(bx, clear + 1.3, bz), mask: Col.move)) continue;
            if (!out.contains(j)) out.add(j);
          }
        }
      }
      links.add(Int32List.fromList(out));
    }

    final mask = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final p = Vec3(pts[i * 3], pts[i * 3 + 1], pts[i * 3 + 2]);
      for (var t = 0; t < 2; t++) {
        if (map.inSpawnRoom(t, p)) mask[i] |= 1 << t;
      }
    }
    return NavGrid._(
        cell, x0, z0, w, h, Float64List.fromList(pts), [for (final l in cols) Int32List.fromList(l)], links, mask);
  }

  /// Nearest node to [p] (searching a few cells around), or null.
  int? nearestIndex(Vec3 p, {int radius = 4}) {
    final ix = ((p.x - x0) / cell).floor(), iz = ((p.z - z0) / cell).floor();
    int? best;
    var bestD = double.infinity;
    for (var dz = -radius; dz <= radius; dz++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final jx = ix + dx, jz = iz + dz;
        if (jx < 0 || jz < 0 || jx >= w || jz >= h) continue;
        for (final j in columns[jz * w + jx]) {
          final ddx = pos[j * 3] - p.x, ddy = pos[j * 3 + 1] - p.y, ddz = pos[j * 3 + 2] - p.z;
          // Prefer same floor: vertical distance counts triple.
          final d = ddx * ddx + ddz * ddz + 9 * ddy * ddy;
          if (d < bestD) {
            bestD = d;
            best = j;
          }
        }
      }
    }
    return best;
  }

  Vec3? nearest(Vec3 p) {
    final i = nearestIndex(p, radius: 8);
    return i == null ? null : node(i);
  }

  /// A* path from [from] to [to] (feet positions). [team] avoids the enemy
  /// spawn room. Returns waypoints (excluding the start) or empty.
  List<Vec3> path(Vec3 from, Vec3 to, {int team = -1, int maxExpand = 40000}) {
    final s = nearestIndex(from), g = nearestIndex(to);
    if (s == null || g == null) return const [];
    if (s == g) return [node(g)];
    final enemyBit = team < 0 ? 0 : 1 << (1 - team);
    final n = length;
    final gScore = Float64List(n)..fillRange(0, n, double.infinity);
    final came = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final heap = _Heap();
    double hdist(int i) {
      final dx = pos[i * 3] - pos[g * 3], dy = pos[i * 3 + 1] - pos[g * 3 + 1], dz = pos[i * 3 + 2] - pos[g * 3 + 2];
      return math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    gScore[s] = 0;
    heap.push(s, hdist(s));
    var expanded = 0;
    while (heap.isNotEmpty && expanded < maxExpand) {
      final cur = heap.pop();
      if (closed[cur] == 1) continue;
      if (cur == g) break;
      closed[cur] = 1;
      expanded++;
      for (final nb in links[cur]) {
        if (closed[nb] == 1 || (spawnMask[nb] & enemyBit) != 0) continue;
        final dx = pos[nb * 3] - pos[cur * 3], dy = pos[nb * 3 + 1] - pos[cur * 3 + 1];
        final dz = pos[nb * 3 + 2] - pos[cur * 3 + 2];
        var cost = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (dy > jumpUp || cost > cell * 1.6) cost += 1.5;
        if (dy > 0.8) cost += 4; // tall climbs only when there is no ramp
        final ng = gScore[cur] + cost;
        if (ng < gScore[nb]) {
          gScore[nb] = ng;
          came[nb] = cur;
          heap.push(nb, ng + hdist(nb));
        }
      }
    }
    if (came[g] == -1) return const [];
    final out = <Vec3>[];
    for (var c = g; c != s && c != -1; c = came[c]) {
      out.add(node(c));
    }
    return out.reversed.toList();
  }

  /// Node indices reachable from [from] (flood fill).
  Set<int> reachable(Vec3 from) {
    final s = nearestIndex(from);
    if (s == null) return const {};
    final seen = <int>{s};
    final stack = [s];
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      for (final j in links[i]) {
        if (seen.add(j)) stack.add(j);
      }
    }
    return seen;
  }

  /// Nodes reachable from [from] (flood fill), for map validation.
  int reachableCount(Vec3 from) {
    final s = nearestIndex(from);
    if (s == null) return 0;
    final seen = Uint8List(length);
    final stack = [s];
    seen[s] = 1;
    var c = 0;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      c++;
      for (final j in links[i]) {
        if (seen[j] == 0) {
          seen[j] = 1;
          stack.add(j);
        }
      }
    }
    return c;
  }
}

class _Heap {
  final List<int> _ids = [];
  final List<double> _keys = [];
  bool get isNotEmpty => _ids.isNotEmpty;

  void push(int id, double key) {
    _ids.add(id);
    _keys.add(key);
    var i = _ids.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_keys[p] <= _keys[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _ids[0];
    final lastId = _ids.removeLast(), lastKey = _keys.removeLast();
    if (_ids.isNotEmpty) {
      _ids[0] = lastId;
      _keys[0] = lastKey;
      var i = 0;
      while (true) {
        final l = i * 2 + 1, r = l + 1;
        var m = i;
        if (l < _ids.length && _keys[l] < _keys[m]) m = l;
        if (r < _ids.length && _keys[r] < _keys[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final ti = _ids[a];
    _ids[a] = _ids[b];
    _ids[b] = ti;
    final tk = _keys[a];
    _keys[a] = _keys[b];
    _keys[b] = tk;
  }
}
