import 'dart:math' as math;

/// Small mutable 3D vector. Mutable on purpose: the simulation and renderer
/// run every frame and we want to avoid allocation churn where possible.
class Vec3 {
  double x, y, z;
  Vec3(this.x, this.y, this.z);
  Vec3.zero()
      : x = 0,
        y = 0,
        z = 0;

  Vec3 copy() => Vec3(x, y, z);
  void setFrom(Vec3 o) {
    x = o.x;
    y = o.y;
    z = o.z;
  }

  void set(double nx, double ny, double nz) {
    x = nx;
    y = ny;
    z = nz;
  }

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator -() => Vec3(-x, -y, -z);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  double get lengthXZ => math.sqrt(x * x + z * z);
  double get lengthSq => x * x + y * y + z * z;

  Vec3 normalized() {
    final l = length;
    return l < 1e-9 ? Vec3(0, 0, 0) : Vec3(x / l, y / l, z / l);
  }

  double distanceTo(Vec3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  double distanceXZ(Vec3 o) {
    final dx = x - o.x, dz = z - o.z;
    return math.sqrt(dx * dx + dz * dz);
  }

  static Vec3 lerp(Vec3 a, Vec3 b, double t) =>
      Vec3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

  List<double> toList([int digits = 3]) => [r(x, digits), r(y, digits), r(z, digits)];
  static Vec3 fromList(List l) =>
      Vec3((l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble());

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// Round a double to [digits] decimals (keeps network payloads small).
double r(double v, [int digits = 3]) {
  final m = math.pow(10, digits).toDouble();
  return (v * m).roundToDouble() / m;
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Wrap an angle to (-pi, pi].
double wrapAngle(double a) {
  if (a > -math.pi && a <= math.pi) return a;
  if (!a.isFinite) return 0;
  // O(1) even for absurd inputs (a loop would hang on 1e300).
  final m = (a + math.pi) % (2 * math.pi);
  return m == 0 ? math.pi : m - math.pi;
}

/// Yaw 0 looks toward -Z ("north"); positive yaw turns toward +X.
Vec3 dirFromAngles(double yaw, double pitch) {
  final cp = math.cos(pitch);
  return Vec3(math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp);
}

double yawTo(Vec3 from, Vec3 to) => math.atan2(to.x - from.x, -(to.z - from.z));
double pitchTo(Vec3 from, Vec3 to) {
  final dxz = from.distanceXZ(to);
  return math.atan2(to.y - from.y, dxz);
}

/// Axis aligned bounding box.
class Aabb {
  double minX, minY, minZ, maxX, maxY, maxZ;
  Aabb(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  Vec3 get center => Vec3((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2);
  Vec3 get size => Vec3(maxX - minX, maxY - minY, maxZ - minZ);

  bool overlaps(double aMinX, double aMinY, double aMinZ, double aMaxX,
          double aMaxY, double aMaxZ) =>
      aMinX < maxX && aMaxX > minX && aMinY < maxY && aMaxY > minY && aMinZ < maxZ && aMaxZ > minZ;

  bool containsXZ(double x, double z, [double pad = 0]) =>
      x > minX - pad && x < maxX + pad && z > minZ - pad && z < maxZ + pad;

  /// Slab test. Returns distance along the (normalized) ray or null.
  double? rayHit(Vec3 o, Vec3 d, double maxDist) {
    double tmin = 0, tmax = maxDist;
    // X
    if (d.x.abs() < 1e-12) {
      if (o.x < minX || o.x > maxX) return null;
    } else {
      final inv = 1 / d.x;
      var t1 = (minX - o.x) * inv, t2 = (maxX - o.x) * inv;
      if (t1 > t2) {
        final t = t1;
        t1 = t2;
        t2 = t;
      }
      if (t1 > tmin) tmin = t1;
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return null;
    }
    // Y
    if (d.y.abs() < 1e-12) {
      if (o.y < minY || o.y > maxY) return null;
    } else {
      final inv = 1 / d.y;
      var t1 = (minY - o.y) * inv, t2 = (maxY - o.y) * inv;
      if (t1 > t2) {
        final t = t1;
        t1 = t2;
        t2 = t;
      }
      if (t1 > tmin) tmin = t1;
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return null;
    }
    // Z
    if (d.z.abs() < 1e-12) {
      if (o.z < minZ || o.z > maxZ) return null;
    } else {
      final inv = 1 / d.z;
      var t1 = (minZ - o.z) * inv, t2 = (maxZ - o.z) * inv;
      if (t1 > t2) {
        final t = t1;
        t1 = t2;
        t2 = t;
      }
      if (t1 > tmin) tmin = t1;
      if (t2 < tmax) tmax = t2;
      if (tmin > tmax) return null;
    }
    return tmin;
  }

  List<double> toList() => [minX, minY, minZ, maxX, maxY, maxZ].map((v) => r(v, 2)).toList();
  static Aabb fromList(List l) => Aabb(
        (l[0] as num).toDouble(),
        (l[1] as num).toDouble(),
        (l[2] as num).toDouble(),
        (l[3] as num).toDouble(),
        (l[4] as num).toDouble(),
        (l[5] as num).toDouble(),
      );
}

/// Ray / sphere test; returns entry distance or null.
double? raySphere(Vec3 o, Vec3 d, Vec3 c, double radius, double maxDist) {
  final ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  final b = ox * d.x + oy * d.y + oz * d.z;
  final cc = ox * ox + oy * oy + oz * oz - radius * radius;
  if (cc <= 0) return 0; // inside
  final disc = b * b - cc;
  if (disc < 0) return null;
  final t = -b - math.sqrt(disc);
  if (t < 0 || t > maxDist) return null;
  return t;
}

/// Deterministic Park-Miller RNG. Every intermediate product stays below
/// 2^53 so it yields identical sequences on the Dart VM (server) and when
/// compiled to JavaScript (Flutter web client) — needed for shot prediction.
class Rng {
  int _s;
  Rng(int seed) : _s = (seed.abs() % 2147483646) + 1;
  int nextInt() => _s = (_s * 48271) % 2147483647;
  double nextDouble() => (nextInt() - 1) / 2147483646;
  double range(double a, double b) => a + (b - a) * nextDouble();
}
