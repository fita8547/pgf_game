import 'dart:math' as math;
import 'dart:typed_data';

import '../content/catalog_types.dart';
import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';
import 'skills.dart';

// Defenders: 볼더 (boulder), 카드보드 (cardboard), 시어 (shear).
// PLACEHOLDER numbers throughout - balance pass pending.

Vec3 _flatForward(Player p) => Vec3(math.sin(p.yaw), 0, -math.cos(p.yaw));

/// Box collider rotated by [yaw] (local x = width, z = depth).
Obb _wall(String name, Vec3 base, double yaw, double width, double height, double depth, int flags) {
  final c = math.cos(yaw), s = math.sin(yaw);
  // Columns: u = right (cos, 0, sin), v = up, w = forward (sin, 0, -cos).
  return Obb(name, flags, base.x, base.y + height / 2, base.z, width / 2, height / 2, depth / 2,
      Float64List.fromList([c, 0, s, 0, 1, 0, s, 0, -c]));
}

// ----------------------------------------------------------------- 볼더 --

/// Q 바위 방벽: big stone wall in front (1200 HP). Press again to recall it.
class RockBulwark extends SkillImpl {
  const RockBulwark();
  @override
  double get cooldown => 8;
  @override
  bool recastable(GameSim sim, Player p) => sim.deployablesOf(p, 'rock_bulwark').isNotEmpty;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final mine = sim.deployablesOf(p, 'rock_bulwark').toList();
    if (mine.isNotEmpty) {
      for (final d in mine) {
        sim.removeDeployable(d);
      }
      sim.startCooldown(p, SkillKey.q, 4);
      return Use.free;
    }
    final f = _flatForward(p);
    final at = Vec3(p.pos.x + f.x * 2.2, p.pos.y, p.pos.z + f.z * 2.2);
    sim.deploy(p, 'rock_bulwark', at, yaw: p.yaw, hp: 1200, life: 60);
    return Use.free; // cooldown starts when it breaks or is recalled
  }

  @override
  Obb? collider(Deployable d) => _wall('dp:${d.id}', d.pos, d.yaw, 4, 2.6, 0.6, Col.solid);

  @override
  void removed(GameSim sim, Deployable d, {required bool destroyed}) {
    final p = sim.players[d.owner];
    if (p != null && destroyed) sim.startCooldown(p, SkillKey.q, 8);
  }
}

/// E 산사태 돌진: charge (WASD direction), grab the first enemy and slam them into a wall.
class LandslideCharge extends SkillImpl {
  const LandslideCharge();
  static const double speed = 13, time = 0.9;

  /// The charge itself is predicted on the client; grabbing/damage is server-side.
  @override
  bool get predictable => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = moveDir(p, inp);
    sim.dash(p, f.x * speed, f.z * speed, time, SkillKey.e);
    return Use.spend;
  }

  @override
  void dashTick(GameSim sim, Player p, double dt) {
    if (!sim.authoritative) return;
    // Carry the victim in front along the charge direction.
    final dx = p.fx['dashVx'] ?? 0, dz = p.fx['dashVz'] ?? 0, dl = math.sqrt(dx * dx + dz * dz);
    final f = dl > 0.1 ? Vec3(dx / dl, 0, dz / dl) : _flatForward(p);
    final held = p.fx['grab'];
    if (held != null) {
      final v = sim.players[held.toInt()];
      if (v == null || !v.alive) {
        p.fx.remove('grab');
      } else {
        v.pos.set(p.pos.x + f.x * 1.1, p.pos.y, p.pos.z + f.z * 1.1);
        v.vel.set(0, 0, 0);
        sim.addFx(v, 'stun', 0.2);
        // Blocked (wall) while carrying -> slam now.
        if (p.vel.lengthXZ < speed * 0.4) {
          p.fx['dash'] = 0.001;
        }
      }
      return;
    }
    for (final q in sim.enemiesNear(p.team, p.pos, 1.4, los: false)) {
      p.fx['grab'] = q.id.toDouble();
      sim.applyDamage(q, 30, p, 'landslide_charge', false);
      break;
    }
  }

  @override
  void dashEnded(GameSim sim, Player p) {
    final held = p.fx.remove('grab');
    if (held == null) return;
    final v = sim.players[held.toInt()];
    if (v == null || !v.alive) return;
    // Slam: more damage if there's a wall right behind them.
    final f = _flatForward(p);
    final wall = sim.map.world.raycast(Vec3(v.pos.x, v.pos.y + 1, v.pos.z), f, 1.2) != null;
    sim.applyDamage(v, wall ? 70 : 30, p, 'landslide_charge', false);
    sim.addFx(v, 'stun', wall ? 1.0 : 0.4);
    sim.events.add({'e': 'slam', 'p': v.pos.toList(2), 'w': wall});
  }
}

/// Shift 용암 투척: slow lava ball that passes through enemies, hurting each once.
class MagmaSlug extends SkillImpl {
  const MagmaSlug();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'magma_slug', p.eye + d * 0.6, d * 26, life: 3, gravity: 3);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    if (hit == null) {
      sim.events.add({'e': 'explode', 'g': 'magma_slug', 'p': at.toList(2), 'r': 1.2});
      return true;
    }
    final key = 'hit${hit.id}';
    if (!pj.hits.contains(key)) {
      pj.hits.add(key);
      sim.applyDamage(hit, 120, sim.players[pj.owner], 'magma_slug', false);
    }
    // Keep flying through the target.
    pj.pos.setFrom(at + pj.vel.normalized() * 0.9);
    return false;
  }
}

/// 궁 대지 균열: hammer slam knocking down every enemy in a 70 degree cone.
class EarthRift extends SkillImpl {
  const EarthRift();
  static const double range = 11;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = _flatForward(p);
    for (final q in [...sim.players.values]) {
      if (!q.alive || q.team == p.team) continue;
      final d = q.pos - p.pos;
      final dist = d.lengthXZ;
      if (dist > range || dist < 0.01) continue;
      if ((d.x * f.x + d.z * f.z) / dist < math.cos(35 * math.pi / 180)) continue;
      if ((q.pos.y - p.pos.y).abs() > 3) continue;
      sim.applyDamage(q, 55, p, 'earth_rift', false);
      sim.addFx(q, 'stun', 1.6);
    }
    sim.events.add({'e': 'cone', 'k': 'earth_rift', 'p': p.pos.toList(2), 'y': r(p.yaw, 3), 'r': range});
    return Use.spend;
  }
}

// -------------------------------------------------------------- 카드보드 --

/// Q 상자 요새: thrown box that unfolds into a dome; bullets can't cross it.
class BoxFort extends SkillImpl {
  const BoxFort();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'box_fort', p.eye + d * 0.5, d * 16, life: 3, gravity: 14);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final owner = sim.players[pj.owner];
    if (owner == null) return true;
    final g = sim.map.world.groundBelow(at.x, at.z, at.y + 0.5) ?? at.y;
    sim.deploy(owner, 'box_fort', Vec3(at.x, g, at.z), hp: 900, life: 6, radius: 3.6);
    return true;
  }

  @override
  double domeRadius(Deployable d) => d.radius;
}

/// E 상자 구르기: toggle a fast rolling ball; can't shoot while rolling, but
/// takes much less damage and knocks enemies over on contact.
class CrateRoll extends SkillImpl {
  const CrateRoll();

  /// Move speed x1.9 and 50% less damage taken while rolling.
  static const double speedMult = 1.9, damageReduction = 0.5;

  /// Landing from a jump while rolling hits enemies around you (flat damage).
  static const double slamDamage = 40, slamRadius = 3, minAirTime = 0.25;
  @override
  double get cooldown => 6;
  @override
  bool recastable(GameSim sim, Player p) => p.mode == 'roll';

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    if (p.mode == 'roll') {
      sim.endMode(p);
      return Use.free;
    }
    sim.setMode(p, 'roll', 6, SkillKey.e);
    return Use.free; // cooldown starts when the roll ends
  }

  @override
  bool modeFire(GameSim sim, Player p, PlayerInput inp, int pressed, double dt,
      {required bool predict, required bool replay}) {
    if (!sim.authoritative || predict) return true;
    // Jump while rolling: landing slams the ground.
    if (!p.onGround) {
      p.fx['rollAir'] = (p.fx['rollAir'] ?? 0) + dt;
    } else if ((p.fx.remove('rollAir') ?? 0) >= minAirTime) {
      sim.splash(p.pos, slamRadius, slamDamage, p, p.team, 'crate_roll', minFrac: 1, selfMult: 0);
    }
    for (final q in sim.enemiesNear(p.team, p.pos, 1.3, los: false)) {
      final key = 'bump${q.id}';
      if ((p.fx[key] ?? 0) > sim.time) continue;
      p.fx[key] = sim.time + 1;
      sim.applyDamage(q, 40, p, 'crate_roll', false);
      final dir = (q.pos - p.pos).normalized();
      q.vel.set(dir.x * 9, 4, dir.z * 9);
      q.onGround = false;
      sim.addFx(q, 'stun', 0.4);
    }
    return true;
  }

  @override
  void modeEnded(GameSim sim, Player p) {
    p.fx.removeWhere((k, _) => k.startsWith('bump') || k == 'rollAir');
    sim.startCooldown(p, SkillKey.e, 6);
  }
}

/// Shift 테이프 갈고리: tape hook that yanks the first enemy hit to you.
class TapeHook extends SkillImpl {
  const TapeHook();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'tape_hook', p.eye + d * 0.5, d * 45, life: 0.5);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final o = sim.players[pj.owner];
    if (hit == null || o == null) return true;
    final f = _flatForward(o);
    var to = Vec3(o.pos.x + f.x * 1.8, o.pos.y, o.pos.z + f.z * 1.8);
    if (!sim.mover.capsuleFree(to.x, to.y + 0.05, to.z, h: hit.height)) to = o.pos.copy();
    final from = hit.pos.copy();
    hit.pos.setFrom(to);
    hit.vel.set(0, 0, 0);
    sim.mover.placeOnGround(hit);
    sim.applyDamage(hit, 20, o, 'tape_hook', false);
    sim.addFx(hit, 'stun', 0.5);
    sim.events.add({'e': 'pull', 'a': from.toList(2), 'b': hit.pos.toList(2)});
    return true;
  }
}

/// 궁 택배 폭격: scatter parcel mines around you.
class ParcelDrop extends SkillImpl {
  const ParcelDrop();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    for (var i = 0; i < 8; i++) {
      final a = i / 8 * math.pi * 2 + p.yaw;
      final dist = i.isEven ? 3.5 : 6.5;
      final x = p.pos.x + math.sin(a) * dist, z = p.pos.z - math.cos(a) * dist;
      final g = sim.map.world.groundBelow(x, z, p.pos.y + 2, maxDrop: 6);
      if (g == null) continue;
      sim.deploy(p, 'parcel_drop', Vec3(x, g, z), hp: 40, life: 20, radius: 1.3);
    }
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    if (d.age < 0.6) return;
    if (sim.enemiesNear(d.team, d.pos, d.radius, los: false).isNotEmpty) d.life = 0;
  }

  @override
  void removed(GameSim sim, Deployable d, {required bool destroyed}) {
    if (d.age < 0.6) return;
    sim.splash(Vec3(d.pos.x, d.pos.y + 0.3, d.pos.z), 2.8, 85, sim.players[d.owner], d.team, 'parcel_drop',
        minFrac: 0.4, selfMult: 0);
  }
}

// ----------------------------------------------------------------- 시어 --

/// Q 가시 방패: hold up a shield (toggle, max 4 s): frontal damage -75%,
/// every blocked hit fires a spike back at the attacker.
class SpikeGuard extends SkillImpl {
  const SpikeGuard();
  @override
  double get cooldown => 6;
  @override
  bool recastable(GameSim sim, Player p) => p.mode == 'guard';

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    if (p.mode == 'guard') {
      sim.endMode(p);
      return Use.free;
    }
    sim.setMode(p, 'guard', 4, SkillKey.q);
    return Use.free;
  }

  @override
  double modeDamaged(GameSim sim, Player victim, Player attacker, double amount, String weapon) {
    final to = attacker.pos - victim.pos;
    final l = to.lengthXZ;
    if (l < 0.01) return amount;
    final f = _flatForward(victim);
    if ((to.x * f.x + to.z * f.z) / l < 0.3) return amount; // from behind/side
    if (weapon != 'spike_guard') sim.applyDamage(attacker, 12, victim, 'spike_guard', false);
    return amount * 0.25;
  }

  @override
  void modeEnded(GameSim sim, Player p) => sim.startCooldown(p, SkillKey.q, 6);
}

/// E 절단 도약: leap (WASD direction) and cleave where you land.
class CleaveLeap extends SkillImpl {
  const CleaveLeap();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = moveDir(p, inp);
    sim.leap(p, 7.5, f.x * 10, f.z * 10, SkillKey.e);
    return Use.spend;
  }

  /// Leap predicted on the client; the landing cleave is server-side.
  @override
  bool get predictable => true;

  @override
  void landed(GameSim sim, Player p) {
    for (final q in [...sim.enemiesNear(p.team, p.pos, 3.5)]) {
      sim.applyDamage(q, 65, p, 'cleave_leap', false);
      sim.addFx(q, 'slow', 1.5, {'slowMul': 0.5});
    }
    sim.events.add({'e': 'explode', 'g': 'cleave_leap', 'p': p.pos.toList(2), 'r': 3.5});
  }
}

/// Shift 칼날 울타리: blade wall that blocks and shoves enemies who touch it.
class BladeFence extends SkillImpl {
  const BladeFence();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = _flatForward(p);
    final at = Vec3(p.pos.x + f.x * 3, p.pos.y, p.pos.z + f.z * 3);
    sim.deploy(p, 'blade_fence', at, yaw: p.yaw, hp: 600, life: 7, radius: 3.2);
    return Use.spend;
  }

  @override
  Obb? collider(Deployable d) => _wall('dp:${d.id}', d.pos, d.yaw, 6, 1.6, 0.4, Col.move);

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    final f = Vec3(math.sin(d.yaw), 0, -math.cos(d.yaw));
    for (final q in sim.enemiesNear(d.team, d.pos, d.radius, los: false)) {
      final rel = q.pos - d.pos;
      final along = rel.x * f.x + rel.z * f.z; // distance in front of the wall
      if (along.abs() > 1.0) continue;
      final side = along >= 0 ? 1.0 : -1.0;
      q.vel.set(f.x * side * 8, 3, f.z * side * 8);
      q.onGround = false;
      sim.applyDamage(q, 25 * dt, sim.players[d.owner], 'blade_fence', false);
    }
  }
}

/// 궁 칼날 폭우: blades rain on the aimed area, rooting everyone inside.
class BladeRain extends SkillImpl {
  const BladeRain();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final at = sim.aimPoint(p, 35);
    sim.deploy(p, 'blade_rain', at, life: 1.0, radius: 6.5);
    return Use.spend;
  }

  @override
  void removed(GameSim sim, Deployable d, {required bool destroyed}) {
    for (final q in [...sim.enemiesNear(d.team, d.pos, d.radius, los: false)]) {
      sim.applyDamage(q, 60, sim.players[d.owner], 'blade_rain', false);
      sim.addFx(q, 'root', 2.2);
    }
    sim.events.add({'e': 'explode', 'g': 'blade_rain', 'p': d.pos.toList(2), 'r': d.radius});
  }
}
