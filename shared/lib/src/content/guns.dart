import 'dart:math' as math;

import 'catalog.g.dart';
import 'catalog_types.dart';

const double _deg = math.pi / 180;

enum GunSlot { primary, secondary }

/// Hand-tuned gun numbers. PLACEHOLDER balance (brief §6-8): every value here
/// is a first pass to make the prototype playable; tune with playtests.
class GunStats {
  final GunSlot slot;
  final int cost;

  /// Body damage per bullet/pellet; head = body * [headMult], legs = body * [legMult].
  final double damage;
  final double headMult, legMult;
  final int pellets;

  /// Rounds per second. The fire clip in fp_rigs is only a visual: play it at
  /// speed max(1, clipLength * fireRate) (brief §6-9).
  final double fireRate;
  final bool auto;
  final int mag, reserve;
  final double reloadTime, drawTime;

  /// Cone half-angles (radians): standing, extra at full run, extra in air.
  final double spread, moveSpread, airSpread;

  /// Spread multiplier while aiming down sights (0 = perfect when scoped).
  final double adsSpreadMult;

  /// Time to reach full ADS (FOV lerp, viewmodel move).
  final double adsTime;

  /// Hand authored spray pattern (pitch up, yaw right) in DEGREES per shot;
  /// past the end the last [patternLoop] points repeat.
  final List<(double, double)> pattern;
  final int patternLoop;

  /// Procedural kick used when [pattern] is empty (degrees per shot, cap).
  final double kick, kickMax;

  /// Recoil multiplier while ADS.
  final double adsRecoilMult;

  /// Damage falloff: full until [falloffStart], linear down to [falloffMin]
  /// at [falloffEnd].
  final double falloffStart, falloffEnd, falloffMin;
  final double range;
  final double moveMult;

  /// Projectile weapons (launcher): speed m/s, splash radius / damage.
  final double projectileSpeed, splashRadius, splashDamage, selfDamageMult;

  const GunStats({
    required this.slot,
    required this.cost,
    required this.damage,
    this.headMult = 2,
    this.legMult = 0.85,
    this.pellets = 1,
    required this.fireRate,
    required this.auto,
    required this.mag,
    required this.reserve,
    required this.reloadTime,
    this.drawTime = 0.5,
    required this.spread,
    required this.moveSpread,
    required this.airSpread,
    this.adsSpreadMult = 0.6,
    this.adsTime = 0.18,
    this.pattern = const [],
    this.patternLoop = 4,
    this.kick = 0,
    this.kickMax = 0,
    this.adsRecoilMult = 0.75,
    this.falloffStart = 1e9,
    this.falloffEnd = 1e9,
    this.falloffMin = 1,
    this.range = 150,
    this.moveMult = 1,
    this.projectileSpeed = 0,
    this.splashRadius = 0,
    this.splashDamage = 0,
    this.selfDamageMult = 0.5,
  });

  bool get isProjectile => projectileSpeed > 0;
}

const Map<String, GunStats> gunStats = {
  'pistol': GunStats(
    slot: GunSlot.secondary,
    cost: 0,
    damage: 24,
    fireRate: 6.5,
    auto: false,
    mag: 12,
    reserve: 48,
    reloadTime: 1.4,
    drawTime: 0.35,
    spread: 0.35 * _deg,
    moveSpread: 4.5 * _deg,
    airSpread: 4 * _deg,
    pattern: [(0, 0), (0.7, 0.1), (1.4, -0.15), (2.0, 0.2), (2.4, -0.25)],
    patternLoop: 2,
    falloffStart: 20,
    falloffEnd: 40,
    falloffMin: 0.6,
    moveMult: 1.05,
  ),
  'revolver': GunStats(
    slot: GunSlot.secondary,
    cost: 500,
    damage: 55,
    fireRate: 2.2,
    auto: false,
    mag: 6,
    reserve: 30,
    reloadTime: 2.0,
    drawTime: 0.45,
    spread: 0.2 * _deg,
    moveSpread: 6 * _deg,
    airSpread: 5 * _deg,
    pattern: [(0, 0), (2.2, 0.3)],
    patternLoop: 1,
    falloffStart: 25,
    falloffEnd: 50,
    falloffMin: 0.6,
  ),
  'smg': GunStats(
    slot: GunSlot.primary,
    cost: 1200,
    damage: 16,
    headMult: 1.75,
    fireRate: 13,
    auto: true,
    mag: 32,
    reserve: 128,
    reloadTime: 1.6,
    spread: 0.6 * _deg,
    moveSpread: 3 * _deg,
    airSpread: 3 * _deg,
    adsSpreadMult: 0.75,
    pattern: [
      (0, 0),
      (0.2, 0.05),
      (0.45, -0.05),
      (0.7, 0.1),
      (0.95, 0.2),
      (1.2, 0.1),
      (1.45, -0.1),
      (1.7, -0.3),
      (1.9, -0.45),
      (2.05, -0.3),
      (2.15, 0.0),
      (2.2, 0.35),
      (2.2, 0.6),
      (2.25, 0.45),
      (2.25, 0.1),
      (2.25, -0.3),
    ],
    patternLoop: 8,
    falloffStart: 12,
    falloffEnd: 30,
    falloffMin: 0.55,
    moveMult: 1.05,
  ),
  'rifle': GunStats(
    slot: GunSlot.primary,
    cost: 2400,
    damage: 24,
    fireRate: 9.5,
    auto: true,
    mag: 28,
    reserve: 112,
    reloadTime: 2.0,
    drawTime: 0.6,
    spread: 0.2 * _deg,
    moveSpread: 7 * _deg,
    airSpread: 6 * _deg,
    adsSpreadMult: 0.5,
    adsTime: 0.22,
    pattern: [
      (0, 0),
      (0.35, 0.05),
      (0.8, 0.1),
      (1.3, 0.05),
      (1.9, -0.1),
      (2.5, -0.2),
      (3.0, -0.1),
      (3.5, 0.1),
      (3.9, 0.35),
      (4.2, 0.6),
      (4.4, 0.8),
      (4.5, 0.6),
      (4.5, 0.2),
      (4.6, -0.3),
      (4.6, -0.8),
      (4.6, -1.1),
      (4.7, -0.9),
      (4.7, -0.4),
      (4.7, 0.2),
      (4.8, 0.8),
    ],
    patternLoop: 8,
    falloffStart: 35,
    falloffEnd: 70,
    falloffMin: 0.7,
    moveMult: 0.95,
  ),
  'shotgun': GunStats(
    slot: GunSlot.primary,
    cost: 1400,
    damage: 11,
    headMult: 1.5,
    pellets: 10,
    fireRate: 1.1,
    auto: false,
    mag: 6,
    reserve: 30,
    reloadTime: 2.4,
    spread: 4.5 * _deg,
    moveSpread: 3 * _deg,
    airSpread: 1 * _deg,
    adsSpreadMult: 0.8,
    kick: 3,
    kickMax: 3,
    falloffStart: 8,
    falloffEnd: 22,
    falloffMin: 0.3,
    range: 60,
  ),
  'sniper': GunStats(
    slot: GunSlot.primary,
    cost: 3800,
    damage: 1000,
    headMult: 2.5,
    fireRate: 0.75,
    auto: false,
    mag: 5,
    reserve: 20,
    reloadTime: 3.0,
    drawTime: 0.8,
    spread: 5 * _deg,
    moveSpread: 12 * _deg,
    airSpread: 10 * _deg,
    adsSpreadMult: 0,
    adsTime: 0.3,
    kick: 4,
    kickMax: 4,
    adsRecoilMult: 1,
    range: 300,
    moveMult: 0.85,
  ),
  'launcher': GunStats(
    slot: GunSlot.primary,
    cost: 3000,
    damage: 60,
    headMult: 1,
    legMult: 1,
    fireRate: 0.9,
    auto: false,
    mag: 4,
    reserve: 12,
    reloadTime: 2.6,
    drawTime: 0.8,
    spread: 0.3 * _deg,
    moveSpread: 3 * _deg,
    airSpread: 2 * _deg,
    adsSpreadMult: 0.5,
    kick: 3,
    kickMax: 3,
    range: 200,
    moveMult: 0.9,
    projectileSpeed: 35,
    splashRadius: 3.5,
    splashDamage: 200,
  ),
};

/// Catalog info (art, ADS numbers) joined with stats.
class GunDef {
  final GunInfo info;
  final GunStats stats;
  const GunDef(this.info, this.stats);

  String get id => info.id;
  String get name => info.name;
  GunSlot get slot => stats.slot;

  /// Deterministic recoil (pitch, yaw) in radians at spray index [i]
  /// (fractional: it decays between shots).
  (double, double) recoilAt(double i) {
    final s = stats;
    if (i <= 0) return (0, 0);
    if (s.pattern.isNotEmpty) {
      final (p0, y0) = _point(i.floor());
      final (p1, y1) = _point(i.floor() + 1);
      final f = i - i.floor();
      return ((p0 + (p1 - p0) * f) * _deg, (y0 + (y1 - y0) * f) * _deg);
    }
    return (math.min(i * s.kick, s.kickMax) * _deg, 0);
  }

  (double, double) _point(int i) {
    final p = stats.pattern;
    if (i < p.length) return p[i];
    final loop = math.min(stats.patternLoop, p.length);
    return p[p.length - loop + (i - p.length) % loop];
  }

  double falloffAt(double dist) {
    final s = stats;
    if (dist <= s.falloffStart) return 1;
    if (dist >= s.falloffEnd) return s.falloffMin;
    return 1 + (s.falloffMin - 1) * (dist - s.falloffStart) / (s.falloffEnd - s.falloffStart);
  }

  /// Damage of one bullet/pellet on [part] at [dist] (before role counter).
  double damageAt(HitPart part, double dist) {
    final m = switch (part) {
      HitPart.head => stats.headMult,
      HitPart.body => 1.0,
      HitPart.legs => stats.legMult,
    };
    return stats.damage * m * falloffAt(dist);
  }

  /// Bullets to kill [hp] at [dist] on [part] (all pellets landing count as
  /// one shot for shotguns).
  int shotsToKill(double hp, HitPart part, double dist, {double mult = 1}) {
    final d = damageAt(part, dist) * stats.pellets * mult;
    return d <= 0 ? 999 : (hp / d).ceil();
  }
}

enum HitPart { head, body, legs }

final List<GunDef> guns = [for (final g in gunInfos) GunDef(g, gunStats[g.id]!)];
final Map<String, GunDef> _byId = {for (final g in guns) g.id: g};

GunDef gunById(String id) => _byId[id] ?? guns.first;
bool isGun(String id) => _byId.containsKey(id);
