import 'dart:math' as math;

/// Small mutable 3D vector (m, Y-up). Mutable on purpose: the sim runs every
/// tick and we want to avoid allocation churn on hot paths.
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
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
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
  static Vec3 fromList(List l) => Vec3((l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble());

  @override
  String toString() => 'Vec3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// Round [v] to [digits] decimals (keeps network payloads small).
double r(double v, [int digits = 3]) {
  final m = math.pow(10, digits).toDouble();
  return (v * m).roundToDouble() / m;
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Wrap an angle to (-pi, pi]. O(1) even for absurd inputs.
double wrapAngle(double a) {
  if (a > -math.pi && a <= math.pi) return a;
  if (!a.isFinite) return 0;
  final m = (a + math.pi) % (2 * math.pi);
  return m == 0 ? math.pi : m - math.pi;
}

/// View direction. Yaw 0 looks toward -Z (team A's spawn is at +Z and looks
/// at the map centre); positive yaw turns toward +X.
Vec3 dirFromAngles(double yaw, double pitch) {
  final cp = math.cos(pitch);
  return Vec3(math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp);
}

double yawTo(Vec3 from, Vec3 to) => math.atan2(to.x - from.x, -(to.z - from.z));
double pitchTo(Vec3 from, Vec3 to) => math.atan2(to.y - from.y, from.distanceXZ(to));

/// Ray / sphere test; returns entry distance (0 if [o] is inside) or null.
double? raySphere(Vec3 o, Vec3 d, Vec3 c, double radius, double maxDist) {
  final ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  final b = ox * d.x + oy * d.y + oz * d.z;
  final cc = ox * ox + oy * oy + oz * oz - radius * radius;
  if (cc <= 0) return 0;
  final disc = b * b - cc;
  if (disc < 0) return null;
  final t = -b - math.sqrt(disc);
  if (t < 0 || t > maxDist) return null;
  return t;
}

/// Ray / vertical capsule (segment [y0]..[y1] at x,z, radius [rad]). Returns
/// entry distance or null. Used for hitboxes.
double? rayCapsule(Vec3 o, Vec3 d, double cx, double y0, double y1, double cz, double rad, double maxDist) {
  // Infinite cylinder first, then clamp to the segment and test end caps.
  final ox = o.x - cx, oz = o.z - cz;
  final a = d.x * d.x + d.z * d.z;
  double? best;
  if (a > 1e-12) {
    final b = ox * d.x + oz * d.z;
    final c = ox * ox + oz * oz - rad * rad;
    final disc = b * b - a * c;
    if (disc >= 0) {
      final t = (-b - math.sqrt(disc)) / a;
      if (t >= 0 && t <= maxDist) {
        final y = o.y + d.y * t;
        if (y >= y0 && y <= y1) best = t;
      } else if (c <= 0) {
        final y = o.y;
        if (y >= y0 && y <= y1) return 0;
      }
    }
  }
  for (final cy in [y0, y1]) {
    final t = raySphere(o, d, Vec3(cx, cy, cz), rad, best ?? maxDist);
    if (t != null && (best == null || t < best)) best = t;
  }
  return best;
}

/// Deterministic Park-Miller RNG. Every intermediate product stays below 2^53
/// so it yields identical sequences on the Dart VM (server) and on the web
/// (client prediction).
class Rng {
  int _s;
  Rng(int seed) : _s = (seed.abs() % 2147483646) + 1;
  int nextInt() => _s = (_s * 48271) % 2147483647;
  double nextDouble() => (nextInt() - 1) / 2147483646;
  double range(double a, double b) => a + (b - a) * nextDouble();
}
