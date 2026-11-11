import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';
import 'skills.dart';

// Healers: 젬 (gem), 니들 (needle), 스크롤 (scroll).
// PLACEHOLDER numbers throughout - balance pass pending.

/// Starts a heal beam from [p] to [t] (see SimEffects._tickFx).
void _link(Player p, Player t, {required double rate, required double range, bool los = true, bool sticky = false}) {
  p.fx['linkTo'] = t.id.toDouble();
  p.fx['linkRate'] = rate;
  p.fx['linkRange'] = range;
  p.fx['linkLos'] = los ? 1 : 0;
  p.fx['linkSticky'] = sticky ? 1 : 0;
}

// ------------------------------------------------------------------ 젬 --

/// Q 치유 결정: a crystal rides above the targeted ally and heals them
/// until you switch it to someone else.
class MendCrystal extends SkillImpl {
  const MendCrystal();
  @override
  double get cooldown => 1;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final t = sim.targetInSight(p, 40, ally: true, self: true, cone: 0.3);
    if (t == null) return Use.fail;
    _link(p, t, rate: 28, range: 999, los: false, sticky: true);
    sim.events.add({'e': 'link', 'p': p.id, 't': t.id, 'k': 'mend_crystal'});
    return Use.spend;
  }
}

/// E 증폭 파편: shard at the aimed spot; allies near it deal +25% damage.
class AmpShard extends SkillImpl {
  const AmpShard();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'amp_shard', sim.aimPoint(p, 15), hp: 120, life: 8, radius: 6);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in sim.alliesNear(d.team, d.pos, d.radius)) {
      sim.addFx(q, 'amp', 0.3, {'ampMul': 0.25});
    }
  }
}

/// Shift 정화의 종: targeted ally (or you) is invulnerable for 1.5 s and
/// cleansed of slows, roots, sleep, stun and vulnerability.
class CleanseBell extends SkillImpl {
  const CleanseBell();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final t = sim.targetInSight(p, 30, ally: true, self: true, cone: 0.3)!;
    sim.cleanse(t);
    sim.addFx(t, 'invuln', 1.5);
    sim.events.add({'e': 'buff', 'p': t.id, 'k': 'cleanse_bell'});
    return Use.spend;
  }
}

/// 궁 수정 성소: crystal tree (solid cover) that heals allies around it.
class CrystalSanctum extends SkillImpl {
  const CrystalSanctum();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'crystal_sanctum', sim.aimPoint(p, 12), hp: 1000, life: 8, radius: 8);
    return Use.spend;
  }

  @override
  Obb? collider(Deployable d) =>
      Obb.aabb('dp:${d.id}', Col.solid, d.pos.x - 0.6, d.pos.y, d.pos.z - 0.6, d.pos.x + 0.6, d.pos.y + 3, d.pos.z + 0.6);

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in sim.alliesNear(d.team, d.pos, d.radius)) {
      sim.heal(q, 60 * dt, sim.players[d.owner]);
    }
  }
}

// ---------------------------------------------------------------- 니들 --

/// Q 치유 실: tether an ally and heal them while in range and sight. Press
/// again to cut the thread.
class ThreadTether extends SkillImpl {
  const ThreadTether();
  @override
  double get cooldown => 1;
  @override
  bool recastable(GameSim sim, Player p) => p.fx.containsKey('linkTo');

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    if (p.fx.containsKey('linkTo')) {
      p.fx.remove('linkTo');
      return Use.free;
    }
    final t = sim.targetInSight(p, 25, ally: true, cone: 0.25);
    if (t == null) return Use.fail;
    _link(p, t, rate: 50, range: 30);
    sim.events.add({'e': 'link', 'p': p.id, 't': t.id, 'k': 'thread_tether'});
    return Use.spend;
  }
}

/// E 수면 침: dart that puts the enemy to sleep (any damage wakes them).
class SleepDart extends SkillImpl {
  const SleepDart();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'sleep_dart', p.eye + d * 0.5, d * 70, life: 1.2);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    if (hit != null) {
      sim.applyDamage(hit, 10, sim.players[pj.owner], 'sleep_dart', false);
      if (hit.alive) sim.addFx(hit, 'sleep', 4);
      sim.events.add({'e': 'buff', 'p': hit.id, 'k': 'sleep_dart'});
    }
    return true;
  }
}

/// Shift 봉합 수류탄: allies in the blast get healed and +50% healing for
/// 4 s; enemies can't be healed for 4 s.
class StitchGrenade extends SkillImpl {
  const StitchGrenade();
  static const double radius = 5;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = p.viewDir;
    sim.addProjectile(p, 'stitch_grenade', p.eye + d * 0.5, d * 20, life: 3, gravity: 12);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final o = sim.players[pj.owner];
    for (final q in sim.alliesNear(pj.team, at, radius)) {
      sim.addFx(q, 'healboost', 4);
      sim.heal(q, 40, o);
    }
    for (final q in [...sim.enemiesNear(pj.team, at, radius)]) {
      sim.addFx(q, 'antiheal', 4);
      sim.applyDamage(q, 30, o, 'stitch_grenade', false);
    }
    sim.events.add({'e': 'explode', 'g': 'stitch_grenade', 'p': at.toList(2), 'r': radius});
    return true;
  }
}

/// 궁 나노 봉합: targeted ally (or you): +50% damage and -50% damage taken
/// for 8 s, plus a quick heal.
class NanoStitch extends SkillImpl {
  const NanoStitch();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final t = sim.targetInSight(p, 40, ally: true, self: true, cone: 0.3)!;
    sim.addFx(t, 'amp', 8, {'ampMul': 0.5});
    sim.addFx(t, 'prot', 8, {'protMul': 0.5});
    sim.heal(t, 150, p);
    sim.events.add({'e': 'buff', 'p': t.id, 'k': 'nano_stitch'});
    return Use.spend;
  }
}

// --------------------------------------------------------------- 스크롤 --

/// Q 치유 인장: healing seal on the ground at your feet.
class MendingSeal extends SkillImpl {
  const MendingSeal();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'mending_seal', p.pos.copy(), life: 5, radius: 4.5);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in sim.alliesNear(d.team, d.pos, d.radius)) {
      if ((q.pos.y - d.pos.y).abs() < 2.5) sim.heal(q, 40 * dt, sim.players[d.owner]);
    }
  }
}

/// E 수호 부적: 75 HP shield on the targeted ally (or you) for 6 s.
class WardTalisman extends SkillImpl {
  const WardTalisman();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final t = sim.targetInSight(p, 30, ally: true, self: true, cone: 0.3)!;
    sim.addFx(t, 'shieldT', 6, {'shield': 75});
    sim.events.add({'e': 'buff', 'p': t.id, 'k': 'ward_talisman'});
    return Use.spend;
  }
}

/// Shift 불사의 등불: allies near the lantern can't drop below 1 HP for 3 s.
class UndyingLantern extends SkillImpl {
  const UndyingLantern();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    sim.deploy(p, 'undying_lantern', p.pos.copy(), life: 3, radius: 6);
    return Use.spend;
  }

  @override
  void tickDeployable(GameSim sim, Deployable d, double dt) {
    for (final q in sim.alliesNear(d.team, d.pos, d.radius)) {
      sim.addFx(q, 'undying', 0.25);
    }
  }
}

/// 궁 대두루마리: the whole team gets a 150 HP shield for 8 s.
class GrandScroll extends SkillImpl {
  const GrandScroll();

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    for (final q in sim.players.values) {
      if (q.alive && q.team == p.team) {
        sim.addFx(q, 'shieldT', 8, {'shield': 150});
        sim.events.add({'e': 'buff', 'p': q.id, 'k': 'grand_scroll'});
      }
    }
    return Use.spend;
  }
}
