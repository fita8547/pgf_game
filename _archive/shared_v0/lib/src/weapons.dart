import 'dart:math' as math;

/// Original weapon roster.
enum WeaponId { knife, sidearm, hound, hornet, talon, lancer }

enum WeaponSlot { primary, secondary, melee }

const double _deg = math.pi / 180;

class WeaponDef {
  final WeaponId id;
  final String name;
  final String kind;
  final WeaponSlot slot;
  final int cost;
  final double headDmg, bodyDmg, legDmg;

  /// Rounds per second.
  final double fireRate;
  final int mag;
  final int reserve;
  final double reloadTime;
  final double equipTime;
  final bool auto;

  /// Spread (radians): standing still, full running, airborne, spraying.
  final double baseSpread, moveSpread, airSpread, spraySpread;

  /// Right click: zoom factor (1 = none) and spread multiplier while zoomed.
  final double zoom;
  final double zoomSpreadMult;

  /// Vertical kick per shot and horizontal sway (radians).
  final double recoilKick, recoilMax, recoilSway;
  final double range;
  final double falloffStart, falloffMult;

  /// Hand-authored spray pattern: (pitch up, yaw right) in DEGREES for shot
  /// 0, 1, 2... Empty = procedural kick/sway. Past the end, the last
  /// [patternLoop] points repeat so long sprays keep dancing.
  final List<(double, double)> pattern;
  final int patternLoop;

  /// Damage falloff steps: (from distance m, multiplier). Empty = legacy
  /// single step [falloffStart]/[falloffMult].
  final List<(double, double)> falloff;
  final double moveSpeedMult;

  const WeaponDef({
    required this.id,
    required this.name,
    required this.kind,
    required this.slot,
    required this.cost,
    required this.headDmg,
    required this.bodyDmg,
    required this.legDmg,
    required this.fireRate,
    required this.mag,
    required this.reserve,
    required this.reloadTime,
    this.equipTime = 0.75,
    required this.auto,
    required this.baseSpread,
    required this.moveSpread,
    required this.airSpread,
    this.spraySpread = 0,
    this.zoom = 1,
    this.zoomSpreadMult = 1,
    this.recoilKick = 0,
    this.recoilMax = 0,
    this.recoilSway = 0,
    this.range = 120,
    this.falloffStart = 1000,
    this.falloffMult = 1,
    this.pattern = const [],
    this.patternLoop = 6,
    this.falloff = const [],
    this.moveSpeedMult = 1,
  });

  bool get isMelee => slot == WeaponSlot.melee;

  /// Deterministic recoil offset (pitch, yaw) in radians for the given
  /// (possibly fractional, it decays between shots) spray index.
  (double, double) recoilAt(double index) {
    if (index <= 0) return (0, 0);
    if (pattern.isNotEmpty) {
      final (p0, y0) = _patternPoint(index.floor());
      final (p1, y1) = _patternPoint(index.floor() + 1);
      final f = index - index.floor();
      return ((p0 + (p1 - p0) * f) * _deg, (y0 + (y1 - y0) * f) * _deg);
    }
    if (recoilKick == 0) return (0, 0);
    final pitch = math.min(index * recoilKick, recoilMax);
    final over = math.max(0.0, index * recoilKick - recoilMax) / recoilKick;
    final yaw = over > 0 ? math.sin(index * 0.55) * recoilSway * math.min(1.0, over / 4) : 0.0;
    return (pitch, yaw);
  }

  (double, double) _patternPoint(int i) {
    if (i < pattern.length) return pattern[i];
    final loop = math.min(patternLoop, pattern.length);
    return pattern[pattern.length - loop + (i - pattern.length) % loop];
  }

  /// Damage multiplier at [dist] meters.
  double falloffAt(double dist) {
    if (falloff.isEmpty) return dist > falloffStart ? falloffMult : 1;
    var m = 1.0;
    for (final (from, mult) in falloff) {
      if (dist >= from) m = mult;
    }
    return m;
  }

  /// Damage for a hit on [part] (0 head, 1 body, 2 legs) at [dist] meters.
  double damageAt(int part, double dist) =>
      (part == 0 ? headDmg : (part == 1 ? bodyDmg : legDmg)) * falloffAt(dist);

  /// Shots needed to kill a target with [hp] + [shield] (66% shield absorb).
  int shotsToKill(int part, double dist, {double hp = 100, double shield = 0}) {
    final d = damageAt(part, dist);
    var h = hp, s = shield, n = 0;
    while (h > 0 && n < 99) {
      final sp = math.min(s, d * 0.66);
      s -= sp;
      h -= d - sp;
      n++;
    }
    return n;
  }
}

const Map<WeaponId, WeaponDef> weapons = {
  WeaponId.knife: WeaponDef(
    id: WeaponId.knife,
    name: 'Edge',
    kind: 'Melee',
    slot: WeaponSlot.melee,
    cost: 0,
    headDmg: 50,
    bodyDmg: 50,
    legDmg: 50,
    fireRate: 2,
    mag: 1,
    reserve: 0,
    reloadTime: 0,
    equipTime: 0.4,
    auto: true,
    baseSpread: 0,
    moveSpread: 0,
    airSpread: 0,
    range: 2.4,
    moveSpeedMult: 1.1,
  ),
  WeaponId.sidearm: WeaponDef(
    id: WeaponId.sidearm,
    name: 'P-9 Sidearm',
    kind: 'Pistol',
    slot: WeaponSlot.secondary,
    cost: 0,
    headDmg: 78,
    bodyDmg: 26,
    legDmg: 22,
    fireRate: 6.75,
    mag: 12,
    reserve: 36,
    reloadTime: 1.75,
    auto: false,
    baseSpread: 0.4 * _deg,
    moveSpread: 3.0 * _deg,
    airSpread: 5 * _deg,
    spraySpread: 2.5 * _deg,
    recoilKick: 0.5 * _deg,
    recoilMax: 3 * _deg,
    recoilSway: 1 * _deg,
    falloff: [(0, 1), (30, 0.85)],
    pattern: [(0, 0), (0.6, 0.1), (1.3, -0.15), (2.0, 0.25), (2.6, -0.3), (3.0, 0.35), (3.2, -0.4)],
    patternLoop: 2,
  ),
  WeaponId.hound: WeaponDef(
    id: WeaponId.hound,
    name: 'Hound .50',
    kind: 'Heavy Pistol',
    slot: WeaponSlot.secondary,
    cost: 800,
    headDmg: 159,
    bodyDmg: 55,
    legDmg: 46,
    fireRate: 4,
    mag: 6,
    reserve: 24,
    reloadTime: 2.25,
    auto: false,
    baseSpread: 0.25 * _deg,
    moveSpread: 4.0 * _deg,
    airSpread: 6 * _deg,
    spraySpread: 3 * _deg,
    recoilKick: 1.6 * _deg,
    recoilMax: 6 * _deg,
    recoilSway: 1.5 * _deg,
    falloff: [(0, 1), (30, 0.8)],
    pattern: [(0, 0), (2.4, 0.3), (4.2, -0.4), (5.6, 0.6), (6.2, -0.8)],
    patternLoop: 2,
  ),
  WeaponId.hornet: WeaponDef(
    id: WeaponId.hornet,
    name: 'Hornet SMG',
    kind: 'SMG',
    slot: WeaponSlot.primary,
    cost: 1600,
    headDmg: 78,
    bodyDmg: 26,
    legDmg: 22,
    fireRate: 13.3,
    mag: 30,
    reserve: 90,
    reloadTime: 2.25,
    auto: true,
    baseSpread: 0.35 * _deg,
    moveSpread: 1.2 * _deg,
    airSpread: 4 * _deg,
    spraySpread: 2.0 * _deg,
    zoom: 1.15,
    zoomSpreadMult: 0.7,
    recoilKick: 0.18 * _deg,
    recoilMax: 2.2 * _deg,
    recoilSway: 1.4 * _deg,
    moveSpeedMult: 1.0,
    falloff: [(0, 1), (15, 0.8), (30, 0.65)],
    pattern: [
      (0, 0), (0.2, 0.05), (0.45, -0.05), (0.7, 0.1), (0.95, 0.2), (1.2, 0.1), (1.45, -0.1), (1.7, -0.3),
      (1.9, -0.45), (2.05, -0.3), (2.15, 0.0), (2.2, 0.35), (2.2, 0.6), (2.25, 0.45), (2.25, 0.1), (2.25, -0.3),
      (2.3, -0.6), (2.3, -0.4),
    ],
    patternLoop: 8,
  ),
  WeaponId.talon: WeaponDef(
    id: WeaponId.talon,
    name: 'Talon AR',
    kind: 'Rifle',
    slot: WeaponSlot.primary,
    cost: 2900,
    headDmg: 156,
    bodyDmg: 39,
    legDmg: 33,
    fireRate: 9.75,
    mag: 25,
    reserve: 75,
    reloadTime: 2.4,
    equipTime: 1.0,
    auto: true,
    baseSpread: 0.22 * _deg,
    moveSpread: 5.5 * _deg,
    airSpread: 8 * _deg,
    spraySpread: 1.6 * _deg,
    zoom: 1.25,
    zoomSpreadMult: 0.8,
    recoilKick: 0.45 * _deg,
    recoilMax: 4.5 * _deg,
    recoilSway: 1.8 * _deg,
    moveSpeedMult: 0.95,
    falloff: [(0, 1), (50, 0.85)],
    pattern: [
      (0, 0), (0.35, 0.05), (0.8, 0.1), (1.3, 0.05), (1.9, -0.1), (2.5, -0.2), (3.0, -0.1), (3.5, 0.1),
      (3.9, 0.35), (4.2, 0.6), (4.4, 0.8), (4.5, 0.6), (4.5, 0.2), (4.6, -0.3), (4.6, -0.8), (4.6, -1.1),
      (4.7, -0.9), (4.7, -0.4), (4.7, 0.2), (4.8, 0.8), (4.8, 1.1),
    ],
    patternLoop: 8,
  ),
  WeaponId.lancer: WeaponDef(
    id: WeaponId.lancer,
    name: 'Lancer',
    kind: 'Sniper',
    slot: WeaponSlot.primary,
    cost: 4700,
    headDmg: 255,
    bodyDmg: 150,
    legDmg: 127,
    fireRate: 0.75,
    mag: 5,
    reserve: 10,
    reloadTime: 3.4,
    equipTime: 1.2,
    auto: false,
    baseSpread: 4.0 * _deg,
    moveSpread: 9 * _deg,
    airSpread: 12 * _deg,
    zoom: 2.6,
    zoomSpreadMult: 0.0,
    recoilKick: 3 * _deg,
    recoilMax: 3 * _deg,
    moveSpeedMult: 0.85,
    pattern: [(0, 0), (3.0, 0.2)],
    patternLoop: 1,
  ),
};

/// Shields (purchasable armor).
const int lightShieldCost = 400, lightShieldValue = 25;
const int heavyShieldCost = 1000, heavyShieldValue = 50;
