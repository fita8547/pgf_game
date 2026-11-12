import 'dart:math' as math;
import 'dart:typed_data';

import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';
import 'skills.dart';

// Controllers: 잉크웰 (inkwell), 퀘이크 (quake), 스테이플 (staple).
// PLACEHOLDER numbers throughout - balance pass pending.

// --------------------------------------------------------------- 잉크웰 --

/// Q 먹물 연막: thrown ink bomb; the cloud blocks sight and enemies inside
/// it are blinded (screen goes dark; vision returns 3 s after leaving). 3 charges.
class InkCloud extends SkillImpl {
  const InkCloud();
  static const double blindLinger = 3;
  @override
  int get maxCharges => 3;
  @override
  double get cooldown => 16; // x0.75 controller = 12 s per charge

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'ink_cloud', p.eye + d * 0.5, d * 20, life: 3, gravity: 12);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final o = sim.players[pj.owner];
    if (o == null) return true;
    final g = sim.map.world.groundBelow(at.x, at.z, at.y + 0.5, maxDrop: 30) ?? at.y;
    sim.deploy(o, 'ink_cloud', Vec3(at.x, g + 1.6, at.z), life: 6, radius: 4.5);
    return true;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    final r = smokeRadius(d);
    for (final q in sim.enemiesNear(d.team, d.pos, r + 0.4, los: false)) {
      final c = Vec3(q.pos.x, q.pos.y + q.body.eye, q.pos.z);
      if (c.distanceTo(d.pos) <= r + 0.4) sim.addFx(q, 'blind', blindLinger);
    }
  }

  @override
  double smokeRadius(Deployable d) => d.age < 0.4 ? d.radius * d.age / 0.4 : d.radius;
}

/// E 먹물 웅덩이: puddle that slows and hurts enemies standing in it.
class InkPuddle extends SkillImpl {
  const InkPuddle();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'ink_puddle', p.eye + d * 0.5, d * 18, life: 3, gravity: 12);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final o = sim.players[pj.owner];
    if (o == null) return true;
    final g = sim.map.world.groundBelow(at.x, at.z, at.y + 0.5, maxDrop: 30) ?? at.y;
    sim.deploy(o, 'ink_puddle', Vec3(at.x, g, at.z), life: 7, radius: 4);
    return true;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in [...sim.enemiesNear(d.team, d.pos, d.radius, los: false)]) {
      if ((q.pos.y - d.pos.y).abs() > 1.5) continue;
      sim.addFx(q, 'slow', 0.3, {'slowMul': 0.5});
      sim.applyDamage(q, 10 * dt, sim.players[d.owner], 'ink_puddle', false);
    }
  }
}

/// Shift 먹물 통로: open an ink door at the aimed spot and step through.
class InkPortal extends SkillImpl {
  const InkPortal();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final at = sim.aimPoint(p, 40);
    if (!sim.mover.capsuleFree(at.x, at.y + 0.05, at.z, h: p.height)) return Use.fail;
    if (at.distanceTo(p.pos) < 3) return Use.fail;
    final from = p.pos.copy();
    p.pos.setFrom(at);
    p.vel.set(0, 0, 0);
    sim.mover.placeOnGround(p);
    sim.events.add({'e': 'blink', 'p': p.id, 'a': from.toList(2), 'b': p.pos.toList(2), 'k': 'ink_portal'});
    return Use.spend;
  }
}

/// 궁 대붓 장벽: a long ink wall along your aim that stops bullets (you can
/// walk through it).
class BrushWall extends SkillImpl {
  const BrushWall();
  static const double length = 30;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = Vec3(math.sin(p.yaw), 0, -math.cos(p.yaw));
    final mid = Vec3(p.pos.x + f.x * (2 + length / 2), p.pos.y, p.pos.z + f.z * (2 + length / 2));
    sim.deploy(p, 'brush_wall', mid, yaw: p.yaw, life: 12, radius: length / 2);
    return Use.spend;
  }

  @override
  Obb? collider(Deployable d) {
    final c = math.cos(d.yaw), s = math.sin(d.yaw);
    // Long axis along the facing direction.
    return Obb('dp:${d.id}', Col.shot, d.pos.x, d.pos.y + 3, d.pos.z, 0.3, 4, d.radius,
        Float64List.fromList([c, 0, s, 0, 1, 0, s, 0, -c]));
  }
}

// --------------------------------------------------------------- 퀘이크 --

/// Q 바위 포탑: rock turret that shoots the closest visible enemy.
class RockTurret extends SkillImpl {
  const RockTurret();

  @override
  bool get diesWithOwner => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    for (final old in [...sim.deployablesOf(p, 'rock_turret')]) {
      sim.removeDeployable(old);
    }
    sim.deploy(p, 'rock_turret', sim.aimPoint(p, 8), hp: 250, life: 25, radius: 25);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    _autoShoot(sim, d, dt, damage: 12, interval: 0.25, slow: 0);
  }
}

/// E 지진 덫: trap that roots the first enemy who steps on it for 1.5 s.
class QuakeTrap extends SkillImpl {
  const QuakeTrap();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'quake_trap', sim.aimPoint(p, 8), hp: 60, life: 45, radius: 2);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    if (d.age < 1) return;
    final hit = sim.enemiesNear(d.team, d.pos, d.radius, los: false).toList();
    if (hit.isEmpty) return;
    for (final q in hit) {
      sim.addFx(q, 'root', 1.5);
      q.revealed = math.max(q.revealed, 3);
      sim.applyDamage(q, 20, sim.players[d.owner], 'quake_trap', false);
    }
    sim.events.add({'e': 'explode', 'g': 'quake_trap', 'p': d.pos.toList(2), 'r': d.radius});
    d.life = 0;
  }
}

/// Shift 과열 용광로: 5 s of +25% speed and fire rate, -25% damage taken.
class Overheat extends SkillImpl {
  const Overheat();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.addFx(p, 'haste', 5);
    sim.addFx(p, 'prot', 5, {'protMul': 0.25});
    sim.events.add({'e': 'buff', 'p': p.id, 'k': 'overheat'});
    return Use.spend;
  }
}

/// 궁 용암 분출: lava pool around you that burns enemies.
class LavaFlow extends SkillImpl {
  const LavaFlow();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'lava_flow', p.pos.copy(), life: 6, radius: 7);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in [...sim.enemiesNear(d.team, d.pos, d.radius, los: false)]) {
      if ((q.pos.y - d.pos.y).abs() < 2) sim.applyDamage(q, 40 * dt, sim.players[d.owner], 'lava_flow', false);
    }
  }
}

// -------------------------------------------------------------- 스테이플 --

/// Q 철심 감시포: small sentry that slows and plinks enemies. 2 charges.
class StapleSentry extends SkillImpl {
  const StapleSentry();
  @override
  int get maxCharges => 2;
  @override
  double get cooldown => 15;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final mine = sim.deployablesOf(p, 'staple_sentry').toList();
    if (mine.length >= 2) sim.removeDeployable(mine.first);
    sim.deploy(p, 'staple_sentry', sim.aimPoint(p, 15, ground: false), hp: 120, life: 30, radius: 15);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    _autoShoot(sim, d, dt, damage: 8, interval: 0.3, slow: 0.7);
  }
}

/// E 철사 덫: trip wire; the enemy who crosses it is rooted and revealed.
class WireSnare extends SkillImpl {
  const WireSnare();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'wire_snare', sim.aimPoint(p, 10), yaw: p.yaw, hp: 40, life: 60, radius: 2.2);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    if (d.age < 1) return;
    final hit = sim.enemiesNear(d.team, d.pos, d.radius, los: false).firstOrNull;
    if (hit == null) return;
    sim.addFx(hit, 'root', 1.2);
    hit.revealed = math.max(hit.revealed, 4);
    sim.events.add({'e': 'reveal', 'p': hit.pos.toList(2), 'r': 1.0, 't': d.team, 'ids': [hit.id]});
    d.life = 0;
  }
}

/// Shift 알람봇: little robot that chases the closest enemy and tags
/// everyone near them: +25% damage taken for 4 s.
class AlarmBot extends SkillImpl {
  const AlarmBot();
  @override
  double get cooldown => 10;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    for (final old in [...sim.deployablesOf(p, 'alarm_bot')]) {
      sim.removeDeployable(old);
    }
    final f = Vec3(math.sin(p.yaw), 0, -math.cos(p.yaw));
    sim.deploy(p, 'alarm_bot', Vec3(p.pos.x + f.x, p.pos.y, p.pos.z + f.z), hp: 80, life: 12, radius: 15);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    Player? best;
    var bd = d.radius;
    for (final q in sim.enemiesNear(d.team, d.pos, d.radius)) {
      final dist = q.pos.distanceTo(d.pos);
      if (dist < bd) {
        bd = dist;
        best = q;
      }
    }
    if (best == null) return;
    if (bd < 1.5) {
      for (final q in sim.enemiesNear(d.team, d.pos, 4, los: false)) {
        sim.addFx(q, 'vuln', 4, {'vulnMul': 0.25});
      }
      sim.events.add({'e': 'explode', 'g': 'alarm_bot', 'p': d.pos.toList(2), 'r': 4});
      d.life = 0;
      return;
    }
    final dir = (best.pos - d.pos).normalized();
    final nx = d.pos.x + dir.x * 4.5 * dt, nz = d.pos.z + dir.z * 4.5 * dt;
    final g = sim.map.world.groundBelow(nx, nz, d.pos.y + 0.6, maxDrop: 2);
    if (g != null) {
      d.pos.set(nx, g, nz);
      d.yaw = math.atan2(dir.x, -dir.z);
    }
  }
}

/// 궁 강철 봉쇄: device that, after a short warm-up, roots every enemy in a
/// wide radius for 3 s (destroy it to stop it).
class SteelLockdown extends SkillImpl {
  const SteelLockdown();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'steel_lockdown', sim.aimPoint(p, 10), hp: 300, life: 3.5, radius: 13);
    return Use.spend;
  }

  @override
  void removed(GameSim sim, Deployable d, {required bool destroyed}) {
    if (destroyed) return;
    for (final q in [...sim.enemiesNear(d.team, d.pos, d.radius, los: false)]) {
      sim.addFx(q, 'root', 3);
    }
    sim.events.add({'e': 'explode', 'g': 'steel_lockdown', 'p': d.pos.toList(2), 'r': d.radius});
  }
}

// ------------------------------------------------------------- helpers --

/// Turret behaviour: hitscan at the closest visible enemy in range.
void _autoShoot(GameSim sim, Deployable d, double dt, {required double damage, required double interval, required double slow}) {
  final cd = (d.data['cd'] ?? 0) - dt;
  d.data['cd'] = cd;
  if (cd > 0) return;
  final eye = Vec3(d.pos.x, d.pos.y + 0.9, d.pos.z);
  Player? best;
  var bd = d.radius;
  for (final q in sim.players.values) {
    if (!q.alive || q.team == d.team) continue;
    final c = Vec3(q.pos.x, q.pos.y + 1.1, q.pos.z);
    final dist = c.distanceTo(eye);
    if (dist < bd && sim.map.world.lineClear(eye, c) && !sim.smokeBlocks(eye, c)) {
      bd = dist;
      best = q;
    }
  }
  if (best == null) return;
  d.data['cd'] = interval;
  final c = Vec3(best.pos.x, best.pos.y + 1.1, best.pos.z);
  d.yaw = math.atan2(c.x - eye.x, -(c.z - eye.z));
  sim.events.add({'e': 'shot', 's': -d.id, 'g': d.kind, 'o': eye.toList(2), 'h': [[...c.toList(2), 1]]});
  sim.applyDamage(best, damage, sim.players[d.owner], d.kind, false);
  if (slow > 0) sim.addFx(best, 'slow', 0.6, {'slowMul': slow});
}
