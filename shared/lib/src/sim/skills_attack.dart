import 'dart:math' as math;

import '../content/catalog_types.dart';
import '../content/guns.dart';
import '../math.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';
import 'skills.dart';

// Attackers: 오리가미 (origami), 스닙 (snip). 페블 lives in skills.dart.
// PLACEHOLDER numbers throughout - balance pass pending.

Vec3 _flat(Player p) => Vec3(math.sin(p.yaw), 0, -math.cos(p.yaw));

// ------------------------------------------------------------- 오리가미 --

/// Q 종이 상승: ride a paper updraft high into the air.
class PaperUpdraft extends SkillImpl {
  const PaperUpdraft();
  @override
  bool get predictable => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.leap(p, 12.5, p.vel.x, p.vel.z, SkillKey.q);
    sim.events.add({'e': 'updraft', 'p': p.id, 'a': p.pos.toList(2)});
    return Use.spend;
  }
}

/// E 접기 질주: short dash toward the held WASD direction (diagonals too;
/// forward when no key is held); a kill soon after resets it.
class PaperDash extends SkillImpl {
  const PaperDash();
  @override
  bool get predictable => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = moveDir(p, inp);
    sim.dash(p, f.x * 22, f.z * 22, 0.25, SkillKey.e);
    p.fx['dashedAt'] = sim.time;
    return Use.spend;
  }

  @override
  void onKill(GameSim sim, Player killer, Player victim) {
    final t = killer.fx['dashedAt'];
    if (t != null && sim.time - t < 4) {
      killer.skillCd[1] = 0;
      killer.skillCharges[1] = 1;
    }
  }
}

/// Shift 종이학 정찰: a paper crane that flies where you look; the first
/// enemy it touches is marked (revealed) for the team.
class CraneScout extends SkillImpl {
  const CraneScout();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'crane_scout', p.eye + d * 0.6, d * 12, life: 5).steer = true;
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    if (hit != null) {
      hit.revealed = math.max(hit.revealed, 6);
      sim.applyDamage(hit, 100, sim.players[pj.owner], 'crane_scout', false);
      sim.events.add({'e': 'reveal', 'p': at.toList(2), 'r': 1.0, 't': pj.team, 'ids': [hit.id]});
    }
    return true;
  }
}

/// 궁 표창 폭풍: 5 precise paper shurikens replace your gun; kills refund one.
class ShurikenStorm extends SkillImpl {
  const ShurikenStorm();
  static const double damage = 120, rate = 3;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.setMode(p, 'shuriken', 12, SkillKey.ult);
    p.fx['modeAmmo'] = 5;
    return Use.spend;
  }

  @override
  bool modeFire(GameSim sim, Player p, PlayerInput inp, int pressed, double dt,
      {required bool predict, required bool replay}) {
    if (pressed & Btn.fire == 0 || p.fireCooldown > 0) return true;
    final ammo = p.fx['modeAmmo'] ?? 0;
    if (ammo <= 0) {
      sim.endMode(p);
      return true;
    }
    p.fx['modeAmmo'] = ammo - 1;
    p.fireCooldown = 1 / rate;
    final o = p.eye, d = p.viewDir;
    final hit = sim.traceShot(p, o, d, 80, inp.renderTick);
    final end = o + d * hit.dist;
    if (!replay) {
      sim.events.add({
        'e': 'shot', 's': p.id, 'g': 'shuriken_storm', 'o': o.toList(2),
        'h': [[...end.toList(2), hit.victim != null ? (hit.part == HitPart.head ? 2 : 1) : (hit.wall ? 0 : -1)]],
      });
    }
    final v = hit.victim;
    if (v != null && !predict && sim.authoritative) {
      sim.applyDamage(v, damage * (hit.part == HitPart.head ? 1.6 : 1), p, 'shuriken_storm', hit.part == HitPart.head);
    }
    return true;
  }

  @override
  void onKill(GameSim sim, Player killer, Player victim) {
    if (killer.mode == 'shuriken') killer.fx['modeAmmo'] = math.min(5, (killer.fx['modeAmmo'] ?? 0) + 1);
  }
}

// ----------------------------------------------------------------- 스닙 --

/// Q 질풍 절단: dash (WASD direction) and slash everyone you pass; a kill
/// resets the cooldown.
class GaleCut extends SkillImpl {
  const GaleCut();

  /// Dash predicted on the client; the slash damage is server-side.
  @override
  bool get predictable => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final f = moveDir(p, inp);
    sim.dash(p, f.x * 18, f.z * 18, 0.32, SkillKey.q);
    return Use.spend;
  }

  @override
  void dashTick(GameSim sim, Player p, double dt) {
    if (!sim.authoritative) return;
    for (final q in [...sim.enemiesNear(p.team, p.pos, 1.7, los: false)]) {
      final key = 'cut${q.id}';
      if (p.fx.containsKey(key)) continue;
      p.fx[key] = 1;
      sim.applyDamage(q, 75, p, 'gale_cut', false);
    }
  }

  @override
  void dashEnded(GameSim sim, Player p) => p.fx.removeWhere((k, _) => k.startsWith('cut'));

  @override
  void onKill(GameSim sim, Player killer, Player victim) {
    if (killer.fx.keys.any((k) => k == 'cut${victim.id}') || (killer.fx['dash'] ?? 0) > 0) {
      killer.skillCd[0] = 0;
      killer.skillCharges[0] = 1;
    }
  }
}

/// E 튕겨내기: spin the blades for 1.5 s: frontal damage is blocked and
/// returned to the attacker doubled; projectiles that come close are sent
/// back (gun projectiles at double damage).
class Deflect extends SkillImpl {
  const Deflect();
  static const double returnMul = 2;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.setMode(p, 'deflect', 1.5, SkillKey.e);
    return Use.spend;
  }

  @override
  bool modeFire(GameSim sim, Player p, PlayerInput inp, int pressed, double dt,
      {required bool predict, required bool replay}) {
    if (!sim.authoritative || predict) return true;
    final c = Vec3(p.pos.x, p.pos.y + 1.1, p.pos.z);
    for (final pj in sim.projectiles) {
      if (pj.team == p.team || pj.stuck || pj.pos.distanceTo(c) > 2.2) continue;
      // Send it back toward where we look, now owned by us.
      final speed = pj.vel.length;
      pj.vel.setFrom(p.viewDir * speed);
      pj.reflect(p.id, p.team, damageMul: returnMul);
      sim.events.add({'e': 'deflect', 'p': p.id});
    }
    return true; // can't shoot while spinning
  }

  @override
  double modeDamaged(GameSim sim, Player victim, Player attacker, double amount, String weapon) {
    final to = attacker.pos - victim.pos;
    final l = to.lengthXZ;
    final f = _flat(victim);
    if (l > 0.01 && (to.x * f.x + to.z * f.z) / l > 0.2) {
      // Never bounce a bounce (two snips deflecting each other).
      if (!reflectedWeapons.contains(weapon) && attacker.id != victim.id) {
        sim.applyDamage(attacker, amount * returnMul, victim, 'deflect', false);
        sim.events.add({'e': 'deflect', 'p': victim.id});
      }
      return 0;
    }
    return amount;
  }
}

/// Shift(C) 속박 비콘: throw a beacon; enemies near where it lands (or the
/// one it hits) are rooted in place.
class PhaseBeacon extends SkillImpl {
  const PhaseBeacon();
  static const double radius = 2.5, rootTime = 2;
  @override
  double get cooldown => 10;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'phase_beacon', p.eye + d * 0.5, d * 24, life: 2.5, gravity: 12);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final o = sim.players[pj.owner];
    if (o == null) return true;
    sim.events.add({'e': 'explode', 'g': 'phase_beacon', 'p': at.toList(2), 'r': radius});
    final caught = {...sim.enemiesNear(pj.team, at, radius, los: false), if (hit != null && hit.team != pj.team) hit};
    for (final q in caught) {
      sim.addFx(q, 'root', rootTime);
    }
    return true;
  }
}

/// 궁 쌍날 개방: split the scissors - fast, strong melee mode for 8 s.
class TwinEdge extends SkillImpl {
  const TwinEdge();
  static const double reach = 2.6, damage = 80, rate = 2.4;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.setMode(p, 'twin', 8, SkillKey.ult);
    return Use.spend;
  }

  @override
  bool modeFire(GameSim sim, Player p, PlayerInput inp, int pressed, double dt,
      {required bool predict, required bool replay}) {
    if (!inp.has(Btn.fire) || p.fireCooldown > 0) return true;
    p.fireCooldown = 1 / rate;
    if (!replay) sim.events.add({'e': 'swing', 's': p.id});
    if (predict || !sim.authoritative) return true;
    final f = p.viewDir;
    for (final q in [...sim.enemiesNear(p.team, p.eye, reach + 0.6, los: true)]) {
      final to = Vec3(q.pos.x, q.pos.y + 1, q.pos.z) - p.eye;
      final l = to.length;
      if (l > 0.01 && to.dot(f) / l > 0.6) sim.applyDamage(q, damage, p, 'twin_edge', false);
    }
    return true;
  }
}
