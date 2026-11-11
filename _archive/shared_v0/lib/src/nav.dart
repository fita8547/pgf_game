import 'dart:math' as math;
import 'dart:typed_data';

import 'map_data.dart';
import 'math.dart';

/// 1m navigation grid with A* path finding, generated from map boxes.
class NavGrid {
  final double originX, originZ;
  final int w, h;
  final Uint8List blocked;
  static const double cell = 1.0;

  NavGrid._(this.originX, this.originZ, this.w, this.h, this.blocked);

  factory NavGrid.build(GameMap map, {double clearance = 0.55}) {
    final b = map.bounds;
    final w = ((b.maxX - b.minX) / cell).ceil();
    final h = ((b.maxZ - b.minZ) / cell).ceil();
    final blocked = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final cx = b.minX + (i + 0.5) * cell;
        final cz = b.minZ + (j + 0.5) * cell;
        for (final mb in map.solids) {
          if (mb.box.maxY <= 0.05) continue; // ground
          if (mb.box.containsXZ(cx, cz, clearance)) {
            blocked[j * w + i] = 1;
            break;
          }
        }
      }
    }
    return NavGrid._(b.minX, b.minZ, w, h, blocked);
  }

  int _ix(double x) => ((x - originX) / cell).floor().clamp(0, w - 1);
  int _iz(double z) => ((z - originZ) / cell).floor().clamp(0, h - 1);
  bool isBlocked(int i, int j) => i < 0 || j < 0 || i >= w || j >= h || blocked[j * w + i] == 1;
  bool isBlockedAt(double x, double z) => isBlocked(_ix(x), _iz(z));
  Vec3 _center(int i, int j) => Vec3(originX + (i + 0.5) * cell, 0, originZ + (j + 0.5) * cell);

  /// Nearest walkable cell to (i,j).
  (int, int) _nearestFree(int i, int j) {
    if (!isBlocked(i, j)) return (i, j);
    for (var rad = 1; rad < 8; rad++) {
      for (var dj = -rad; dj <= rad; dj++) {
        for (var di = -rad; di <= rad; di++) {
          if (!isBlocked(i + di, j + dj)) return (i + di, j + dj);
        }
      }
    }
    return (i, j);
  }

  /// A* over an 8-connected grid. Returns smoothed world waypoints or empty.
  List<Vec3> findPath(Vec3 from, Vec3 to) {
    final (si, sj) = _nearestFree(_ix(from.x), _iz(from.z));
    final (gi, gj) = _nearestFree(_ix(to.x), _iz(to.z));
    final start = sj * w + si, goal = gj * w + gi;
    if (start == goal) return [to.copy()..y = 0];
    final n = w * h;
    final g = Float64List(n)..fillRange(0, n, double.infinity);
    final came = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final heap = _Heap();
    g[start] = 0;
    heap.push(start, _heur(si, sj, gi, gj));
    var found = false;
    while (heap.isNotEmpty) {
      final cur = heap.pop();
      if (cur == goal) {
        found = true;
        break;
      }
      if (closed[cur] == 1) continue;
      closed[cur] = 1;
      final ci = cur % w, cj = cur ~/ w;
      for (var dj = -1; dj <= 1; dj++) {
        for (var di = -1; di <= 1; di++) {
          if (di == 0 && dj == 0) continue;
          final ni = ci + di, nj = cj + dj;
          if (isBlocked(ni, nj)) continue;
          if (di != 0 && dj != 0 && (isBlocked(ci + di, cj) || isBlocked(ci, cj + dj))) continue;
          final nIdx = nj * w + ni;
          if (closed[nIdx] == 1) continue;
          final cost = g[cur] + ((di != 0 && dj != 0) ? 1.41421356 : 1.0);
          if (cost < g[nIdx]) {
            g[nIdx] = cost;
            came[nIdx] = cur;
            heap.push(nIdx, cost + _heur(ni, nj, gi, gj));
          }
        }
      }
    }
    if (!found) return [];
    final cells = <int>[];
    for (var c = goal; c != -1; c = came[c]) {
      cells.add(c);
    }
    final pts = cells.reversed.map((c) => _center(c % w, c ~/ w)).toList();
    if (!isBlockedAt(to.x, to.z)) pts.add(to.copy()..y = 0);
    return _smooth(pts);
  }

  double _heur(int a, int b, int c, int d) {
    final dx = (a - c).abs(), dz = (b - d).abs();
    return (dx + dz) + (1.41421356 - 2) * math.min(dx, dz);
  }

  /// Straight-line walkability across grid cells.
  bool walkable(Vec3 a, Vec3 b) {
    final dist = a.distanceXZ(b);
    final steps = (dist / (cell * 0.4)).ceil();
    for (var s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t;
      if (isBlocked(_ix(x), _iz(z))) return false;
    }
    return true;
  }

  List<Vec3> _smooth(List<Vec3> pts) {
    if (pts.length <= 2) return pts;
    final out = <Vec3>[pts.first];
    var anchor = 0;
    for (var i = 2; i < pts.length; i++) {
      if (!walkable(pts[anchor], pts[i])) {
        out.add(pts[i - 1]);
        anchor = i - 1;
      }
    }
    out.add(pts.last);
    return out.sublist(1);
  }

  /// Center of the walkable cell nearest to [p] (y = 0).
  Vec3 nearestFreePoint(Vec3 p) {
    final (i, j) = _nearestFree(_ix(p.x), _iz(p.z));
    return _center(i, j);
  }

  /// Random walkable point within [radius] of [center].
  Vec3 randomPointNear(Vec3 center, double radius, Rng rng) {
    for (var k = 0; k < 24; k++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = math.sqrt(rng.nextDouble()) * radius;
      final p = Vec3(center.x + math.cos(a) * d, 0, center.z + math.sin(a) * d);
      if (!isBlockedAt(p.x, p.z)) return p;
    }
    return center.copy()..y = 0;
  }
}

class _Heap {
  final _items = <int>[];
  final _prio = <double>[];
  bool get isNotEmpty => _items.isNotEmpty;

  void push(int item, double p) {
    _items.add(item);
    _prio.add(p);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_prio[parent] <= _prio[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    final top = _items[0];
    final last = _items.length - 1;
    _swap(0, last);
    _items.removeLast();
    _prio.removeLast();
    var i = 0;
    while (true) {
      final l = i * 2 + 1, rr = l + 1;
      var m = i;
      if (l < _items.length && _prio[l] < _prio[m]) m = l;
      if (rr < _items.length && _prio[rr] < _prio[m]) m = rr;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }

  void _swap(int a, int b) {
    final t = _items[a];
    _items[a] = _items[b];
    _items[b] = t;
    final p = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = p;
  }
}
