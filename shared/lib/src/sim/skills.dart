import 'dart:math' as math;

import '../content/catalog_types.dart';
import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';
import 'skills_attack.dart';
import 'skills_controller.dart';
import 'skills_defender.dart';
import 'skills_healer.dart';

/// Skill framework. The generic part (cooldowns, charges, ult points, input)
/// lives in [GameSim]; each skill only describes what it does. Skills are
/// keyed by the catalog skill id, so adding one is: write a [SkillImpl],
/// register it in [skillImpls]. Skills without an impl are simply inert.
///
/// Q / E / Shift use slots 0..2 on the player; the ult uses ult points.
int skillSlot(SkillKey k) => switch (k) {
      SkillKey.q => 0,
      SkillKey.e => 1,
      SkillKey.shift => 2,
      SkillKey.ult => -1,
    };

/// Result of pressing a skill key.
enum Use {
  /// Nothing happened (no target, blocked...). Nothing is spent.
  fail,

  /// Used: spend a charge / start the cooldown / empty the ult.
  spend,

  /// Did something without costing (recall, retarget, second press).
  free,
}

abstract class SkillImpl {
  const SkillImpl();

  int get maxCharges => 1;

  /// Seconds per charge (or plain cooldown). Null = catalog value.
  double? get cooldown => null;

  /// Pure movement skills also run in client prediction (no rubber-banding).
  bool get predictable => false;

  /// Deployables of this skill vanish when their owner dies.
  bool get diesWithOwner => false;

  /// May be pressed while on cooldown (second press of a two-step skill).
  bool recastable(GameSim sim, Player p) => false;

  /// Performs the skill.
  Use use(GameSim sim, Player p, PlayerInput inp);

  /// A projectile from this skill hit the world ([hit] = player, if any).
  /// Return true to remove the projectile.
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) => true;

  /// Fuse of a stuck projectile ran out.
  void detonate(GameSim sim, Projectile pj) {}

  // Dashes / leaps started with sim.dash / sim.leap.
  void dashTick(GameSim sim, Player p, double dt) {}
  void dashEnded(GameSim sim, Player p) {}
  void landed(GameSim sim, Player p) {}

  /// The owner got a kill (cooldown resets, ammo refunds).
  void onKill(GameSim sim, Player killer, Player victim) {}

  // Weapon modes set with sim.setMode.
  /// Replace normal firing; return true if handled.
  bool modeFire(GameSim sim, Player p, PlayerInput inp, int pressed, double dt,
          {required bool predict, required bool replay}) =>
      false;

  /// Adjust incoming damage while in this mode.
  double modeDamaged(GameSim sim, Player victim, Player attacker, double amount, String weapon) => amount;
  void modeEnded(GameSim sim, Player p) {}

  // Deployables placed with sim.deploy.
  Obb? collider(Deployable d) => null;
  void tickDeployable(GameSim sim, Deployable d, double dt) {}
  void removed(GameSim sim, Deployable d, {required bool destroyed}) {}

  /// Bullets can't cross a sphere of this radius around the deployable.
  double domeRadius(Deployable d) => 0;

  /// Blocks sight (bots, reveal) inside this radius.
  double smokeRadius(Deployable d) => 0;
}

/// Registered skill behaviours: all 12 characters x 4 skills.
const Map<String, SkillImpl> skillImpls = {
  // 디펜서
  'rock_bulwark': RockBulwark(),
  'landslide_charge': LandslideCharge(),
  'magma_slug': MagmaSlug(),
  'earth_rift': EarthRift(),
  'box_fort': BoxFort(),
  'crate_roll': CrateRoll(),
  'tape_hook': TapeHook(),
  'parcel_drop': ParcelDrop(),
  'spike_guard': SpikeGuard(),
  'cleave_leap': CleaveLeap(),
  'blade_fence': BladeFence(),
  'blade_rain': BladeRain(),
  // 어택
  'paper_updraft': PaperUpdraft(),
  'paper_dash': PaperDash(),
  'crane_scout': CraneScout(),
  'shuriken_storm': ShurikenStorm(),
  'gravel_blink': GravelBlink(),
  'rewind': Rewind(),
  'recon_pebble': ReconPebble(),
  'sticky_charge': StickyCharge(),
  'gale_cut': GaleCut(),
  'deflect': Deflect(),
  'phase_beacon': PhaseBeacon(),
  'twin_edge': TwinEdge(),
  // 힐러
  'mend_crystal': MendCrystal(),
  'amp_shard': AmpShard(),
  'cleanse_bell': CleanseBell(),
  'crystal_sanctum': CrystalSanctum(),
  'thread_tether': ThreadTether(),
  'sleep_dart': SleepDart(),
  'stitch_grenade': StitchGrenade(),
  'nano_stitch': NanoStitch(),
  'mending_seal': MendingSeal(),
  'ward_talisman': WardTalisman(),
  'undying_lantern': UndyingLantern(),
  'grand_scroll': GrandScroll(),
  // 컨트롤러
  'ink_cloud': InkCloud(),
  'ink_puddle': InkPuddle(),
  'ink_portal': InkPortal(),
  'brush_wall': BrushWall(),
  'rock_turret': RockTurret(),
  'quake_trap': QuakeTrap(),
  'overheat': Overheat(),
  'lava_flow': LavaFlow(),
  'staple_sentry': StapleSentry(),
  'wire_snare': WireSnare(),
  'alarm_bot': AlarmBot(),
  'steel_lockdown': SteelLockdown(),
};

Vec3 _aimDir(Player p) => dirFromAngles(p.yaw, p.pitch);

// ------------------------------------------------------------- 페블 (Pebble) --

/// Damage sent back by a reflecting skill. Reflectors never reflect these,
/// so two reflectors facing each other can't bounce damage forever.
const Set<String> reflectedWeapons = {'deflect', 'spike_guard'};

/// Unit ground direction of the held movement keys (WASD, diagonals too;
/// same axes as the mover), or the look direction when none are held.
/// Dash / charge / leap skills go this way.
Vec3 moveDir(Player p, PlayerInput inp) {
  final sy = math.sin(p.yaw), cy = math.cos(p.yaw);
  final x = cy * inp.moveX + sy * inp.moveZ, z = sy * inp.moveX - cy * inp.moveZ;
  final l = math.sqrt(x * x + z * z);
  return l < 0.1 ? Vec3(sy, 0, -cy) : Vec3(x / l, 0, z / l);
}

/// Q 자갈 점멸: short teleport toward the movement direction (view direction
/// when standing still). 3 charges, 3 s each. Never passes through walls:
/// the path is checked in steps smaller than the capsule.
class GravelBlink extends SkillImpl {
  const GravelBlink();
  static const double range = 7;

  @override
  int get maxCharges => 3;
  @override
  double get cooldown => 3;
  @override
  bool get predictable => true;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final sy = math.sin(p.yaw), cy = math.cos(p.yaw);
    var wx = cy * inp.moveX + sy * inp.moveZ, wz = sy * inp.moveX - cy * inp.moveZ;
    var l = math.sqrt(wx * wx + wz * wz);
    if (l < 0.1) {
      wx = sy;
      wz = -cy;
      l = 1;
    }
    wx /= l;
    wz /= l;
    final from = p.pos.copy();
    var best = from.copy();
    for (var d = 0.25; d <= range + 1e-9; d += 0.25) {
      final x = from.x + wx * d, z = from.z + wz * d;
      Vec3? ok;
      for (final up in const [0.0, 0.25, 0.5]) {
        final y = best.y + up;
        if (sim.mover.capsuleFree(x, y + 0.02, z, h: p.height)) {
          ok = Vec3(x, y, z);
          break;
        }
      }
      if (ok == null) break;
      best = ok;
    }
    if (best.distanceXZ(from) < 0.75) return Use.fail;
    p.pos.setFrom(best);
    sim.mover.placeOnGround(p);
    sim.events.add({'e': 'blink', 'p': p.id, 'a': from.toList(2), 'b': p.pos.toList(2)});
    return Use.spend;
  }
}

/// E 되감기: back to where you were 3 s ago, at full HP.
class Rewind extends SkillImpl {
  const Rewind();
  static const double back = 3;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    if (p.history.isEmpty) return Use.fail;
    final target = sim.time - back;
    final s = p.history.firstWhere((h) => h[0] >= target - 0.05, orElse: () => p.history.first);
    final from = p.pos.copy();
    p.pos.set(s[1], s[2], s[3]);
    p.vel.set(0, 0, 0);
    p.hp = p.maxHp;
    p.history.clear();
    sim.mover.placeOnGround(p);
    sim.events.add({'e': 'rewind', 'p': p.id, 'a': from.toList(2), 'b': p.pos.toList(2)});
    return Use.spend;
  }
}

/// Shift 정찰 자갈: thrown dart; where it lands, enemies in range and in line of
/// sight of the impact are revealed to the thrower's team for a few seconds.
class ReconPebble extends SkillImpl {
  const ReconPebble();
  static const double radius = 15, duration = 4;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = _aimDir(p);
    sim.addProjectile(p, 'recon_pebble', p.eye + d * 0.5, d * 30, life: 4, gravity: 9);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    final eye = Vec3(at.x, at.y + 0.4, at.z);
    final ids = <int>[];
    for (final q in sim.players.values) {
      if (!q.alive || q.team == pj.team) continue;
      final chest = Vec3(q.pos.x, q.pos.y + 1.1, q.pos.z);
      if (chest.distanceTo(at) > radius || !sim.map.world.lineClear(eye, chest)) continue;
      q.revealed = math.max(q.revealed, duration);
      ids.add(q.id);
    }
    sim.events.add({'e': 'reveal', 'p': at.toList(2), 'r': radius, 't': pj.team, 'ids': ids});
    return true;
  }
}

/// 궁 점착 폭약: sticks to the first wall or enemy it touches and explodes
/// after a short fuse.
class StickyCharge extends SkillImpl {
  const StickyCharge();
  static const double fuse = 1.4, radius = 5.5, damage = 170;

  @override
  Use use(GameSim sim, Player p, PlayerInput inp) {
    final d = _aimDir(p);
    sim.addProjectile(p, 'sticky_charge', p.eye + d * 0.5, d * 24, life: 6, gravity: 9);
    return Use.spend;
  }

  @override
  bool impact(GameSim sim, Projectile pj, Vec3 at, Player? hit) {
    pj
      ..stuck = true
      ..fuse = fuse
      ..vel.set(0, 0, 0)
      ..pos.setFrom(at);
    if (hit != null) {
      pj
        ..stuckTo = hit.id
        ..offset = at - hit.pos;
    }
    sim.events.add({'e': 'stick', 'g': pj.gun, 'p': at.toList(2), 'on': hit?.id});
    return false;
  }

  @override
  void detonate(GameSim sim, Projectile pj) {
    sim.splash(pj.pos, radius, damage, sim.players[pj.owner], pj.team, pj.gun, minFrac: 0.35, selfMult: 0.5);
  }
}
