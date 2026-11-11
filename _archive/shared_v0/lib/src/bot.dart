import 'dart:math' as math;

import 'agents.dart';
import 'input.dart';
import 'map_data.dart';
import 'math.dart';
import 'player.dart';
import 'sim.dart';
import 'weapons.dart';

/// Server-side AI for one bot slot. Bots act only by producing
/// [PlayerInput]s, exactly like a human client, so they obey every rule.
class BotBrain {
  final int id;

  /// 0 (easy) .. 1 (hard).
  final double skill;
  final Rng _rng;

  int _seq = 0;
  bool _boughtThisRound = false;

  // navigation
  List<Vec3> _path = [];
  Vec3? _goal;
  double _repathTimer = 0;
  double _stuckTimer = 0;
  final Vec3 _lastPos = Vec3.zero();
  HoldSpot? _hold;

  // combat
  int? _targetId;
  double _reaction = 0;
  double _aimErrYaw = 0, _aimErrPitch = 0;
  double _burstTimer = 0;
  Vec3? _threatDir;
  double _threatTimer = 0;

  // abilities
  bool _usedOpener = false;
  int _pulse = 0;

  BotBrain(this.id, this.skill, int seed) : _rng = Rng(seed);

  double get _reactionTime => 0.55 - 0.35 * skill;
  double get _aimError => (1.0 - skill) * 0.06 + 0.004;

  void resetRound(GameSim sim) {
    _boughtThisRound = false;
    _path = [];
    _goal = null;
    _hold = null;
    _targetId = null;
    _threatDir = null;
    _threatTimer = 0;
    _usedOpener = false;
    _repathTimer = 0;
    _stuckTimer = 0;
  }

  void onDamaged(Player? attacker) {
    if (attacker == null) return;
    _threatDir = attacker.pos.copy();
    _threatTimer = 2.5;
  }

  void onFlashed() {
    _targetId = null;
    _reaction = _reactionTime + 0.4;
  }

  PlayerInput? think(GameSim sim, Player p, double dt) {
    if (!p.alive) return null;
    final inp = PlayerInput(seq: ++_seq, dt: dt, yaw: p.yaw, pitch: p.pitch);
    _pulse = 0;

    switch (sim.phase) {
      case Phase.warmup:
      case Phase.matchEnd:
        return inp;
      case Phase.buy:
        if (!_boughtThisRound) _buy(sim, p);
        return inp;
      case Phase.live:
      case Phase.planted:
      case Phase.roundEnd:
        break;
    }

    _repathTimer -= dt;
    _threatTimer -= dt;
    _burstTimer -= dt;

    final enemy = _pickTarget(sim, p, dt);
    final goal = _chooseGoal(sim, p);
    final moveDir = _follow(sim, p, goal, dt);

    var wantUse = false;
    if (sim.isAttacker(p)) {
      if (sim.coreCarrier == p.id && sim.phase == Phase.live && sim.map.siteAt(p.pos) != null && enemy == null) {
        wantUse = true;
      }
    } else if (sim.phase == Phase.planted && p.pos.distanceTo(sim.corePos) < 1.6 && enemy == null) {
      wantUse = true;
    }

    var mx = 0.0, mz = 0.0;
    if (enemy != null) {
      _aimAt(p, enemy, inp, dt);
      final def = p.weapon;
      final onTarget = _reaction <= 0 && p.flashTime < 0.3;
      if (onTarget) {
        if (def.auto) {
          if (_burstTimer <= 0) {
            inp.buttons |= Btn.fire;
            if (p.recoilIndex > 4 + skill * 6) _burstTimer = 0.25 + (1 - skill) * 0.2;
          }
        } else if (p.fireCooldown <= 0 && _rng.nextDouble() < 0.6) {
          inp.buttons |= Btn.fire;
        }
        if (def.zoom > 1.5) inp.buttons |= Btn.ads;
      }
      // Strafe a little while dueling; stand still for accuracy when skilled.
      if (_rng.nextDouble() > skill * 0.7) {
        mx = math.sin(sim.time * 3 + id) > 0 ? 1 : -1;
      }
      _maybeAbility(sim, p, enemy, inp);
    } else {
      if (_threatTimer > 0 && _threatDir != null) {
        _lookToward(p, _threatDir!..y = 1.4, inp, dt, 9);
      } else if (moveDir != null) {
        final look = _hold != null && p.pos.distanceXZ(_hold!.pos) < 1.2 ? _hold!.lookAt : null;
        if (look != null) {
          _lookToward(p, look, inp, dt, 4);
        } else {
          final ahead = Vec3(p.pos.x + moveDir.x * 4, p.eyeHeight, p.pos.z + moveDir.z * 4);
          _lookToward(p, ahead, inp, dt, 6);
        }
      } else if (_hold != null) {
        _lookToward(p, _hold!.lookAt, inp, dt, 4);
      }
      if (p.mag < p.weapon.mag * 0.4 && p.reserve > 0 && !p.weapon.isMelee) {
        inp.buttons |= Btn.reload;
      }
      if (!wantUse) _maybeOpener(sim, p, inp);
    }

    if (moveDir != null && !wantUse) {
      final sy = math.sin(inp.yaw), cy = math.cos(inp.yaw);
      // world -> local (inverse of the sim's local -> world rotation)
      final lx = cy * moveDir.x + sy * moveDir.z;
      final lz = sy * moveDir.x - cy * moveDir.z;
      if (enemy == null) {
        mx = lx;
        mz = lz;
      } else {
        mx = clampD(mx + lx * 0.4, -1, 1);
        mz = lz * 0.3;
      }
    }
    inp
      ..moveX = clampD(mx, -1, 1)
      ..moveZ = clampD(mz, -1, 1);
    if (wantUse) inp.buttons |= Btn.use;
    if (_pulse != 0 && p.prevButtons & _pulse == 0) inp.buttons |= _pulse;
    return inp;
  }

  // ------------------------------------------------------------- buying --
  void _buy(GameSim sim, Player p) {
    _boughtThisRound = true;
    final c = p.credits;
    if (p.primary == null) {
      if (c >= 4700 + 1000 && _rng.nextDouble() < 0.25) {
        sim.buy(p, WeaponId.lancer.name);
      } else if (c >= 2900 + 400) {
        sim.buy(p, WeaponId.talon.name);
      } else if (c >= 1600 + 400) {
        sim.buy(p, WeaponId.hornet.name);
      } else if (c >= 800 && p.secondary == WeaponId.sidearm && _rng.nextDouble() < 0.5) {
        sim.buy(p, WeaponId.hound.name);
      }
    }
    if (p.credits >= heavyShieldCost + 300) {
      sim.buy(p, 'heavy');
    } else if (p.credits >= lightShieldCost) {
      sim.buy(p, 'light');
    }
    while (p.credits >= p.agentDef.q.cost && p.agentDef.q.cost > 0 && sim.buy(p, 'q') == null) {}
  }

  // ------------------------------------------------------------ targets --
  Player? _pickTarget(GameSim sim, Player p, double dt) {
    final current = _targetId == null ? null : sim.players[_targetId];
    if (current != null && current.alive && _visible(sim, p, current, wide: true)) {
      _reaction -= dt;
      return current;
    }
    Player? best;
    var bestD = double.infinity;
    for (final o in sim.players.values) {
      if (!o.alive || o.team == p.team) continue;
      if (!_visible(sim, p, o)) continue;
      final d = p.pos.distanceTo(o.pos);
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (best == null) {
      _targetId = null;
      return null;
    }
    _targetId = best.id;
    _reaction = _reactionTime * (0.7 + _rng.nextDouble() * 0.6);
    _aimErrYaw = _rng.range(-1, 1) * _aimError * 4;
    _aimErrPitch = _rng.range(-1, 1) * _aimError * 2;
    return best;
  }

  bool _visible(GameSim sim, Player p, Player o, {bool wide = false}) {
    final chest = Vec3(o.pos.x, o.pos.y + o.height * 0.7, o.pos.z);
    return sim.canSee(p, chest, fovCos: wide ? 0.2 : 0.55, maxDist: 70);
  }

  void _aimAt(Player p, Player o, PlayerInput inp, double dt) {
    final headish = skill > 0.6 && _rng.nextDouble() < skill * 0.5;
    final target = Vec3(o.pos.x, o.pos.y + (headish ? o.eyeHeight + 0.05 : o.height * 0.7), o.pos.z);
    // Error shrinks as the bot settles on target.
    _aimErrYaw *= math.max(0, 1 - dt * (2 + skill * 4));
    _aimErrPitch *= math.max(0, 1 - dt * (2 + skill * 4));
    final eye = p.eye;
    final wantYaw = yawTo(eye, target) + _aimErrYaw + _rng.range(-1, 1) * _aimError;
    // Pull down against recoil like a human would.
    final (kick, _) = p.weapon.recoilAt(p.recoilIndex);
    final wantPitch = pitchTo(eye, target) + _aimErrPitch - kick * skill;
    final speed = 8 + skill * 14;
    inp.yaw = _turn(p.yaw, wantYaw, speed * dt);
    inp.pitch = p.pitch + clampD(wantPitch - p.pitch, -speed * dt, speed * dt);
  }

  void _lookToward(Player p, Vec3 point, PlayerInput inp, double dt, double speed) {
    final eye = p.eye;
    inp.yaw = _turn(p.yaw, yawTo(eye, point), speed * dt);
    final wantPitch = pitchTo(eye, point);
    inp.pitch = p.pitch + clampD(wantPitch - p.pitch, -speed * dt, speed * dt);
  }

  static double _turn(double from, double to, double maxStep) =>
      wrapAngle(from + clampD(wrapAngle(to - from), -maxStep, maxStep));

  // --------------------------------------------------------- objectives --
  Vec3 _chooseGoal(GameSim sim, Player p) {
    final map = sim.map;
    final site = map.sites[sim.attackSiteIndex % map.sites.length];
    if (sim.phase == Phase.planted) {
      if (sim.isAttacker(p)) {
        _hold ??= HoldSpot(map.nav.randomPointNear(sim.corePos, 6, _rng), sim.corePos.copy()..y = 1.0);
        return _hold!.pos;
      }
      _hold = null;
      return sim.corePos;
    }
    if (sim.isAttacker(p)) {
      if (sim.coreState == CoreState.dropped) return sim.corePos;
      if (sim.coreCarrier == p.id) return site.center;
      return _goal ?? map.nav.randomPointNear(site.center, site.radius * 0.8, _rng);
    }
    if (_hold == null) {
      final pool = map.holds[_rng.nextInt() % map.holds.length];
      if (pool.isNotEmpty) _hold = pool[_rng.nextInt() % pool.length];
    }
    return _hold?.pos ?? map.defenseSpawns.first;
  }

  /// Advances along a nav path toward [goal]; returns world XZ move dir.
  Vec3? _follow(GameSim sim, Player p, Vec3 goal, double dt) {
    final changed = _goal == null || _goal!.distanceXZ(goal) > 1.5;
    if (changed || _repathTimer <= 0 || _path.isEmpty) {
      if (p.pos.distanceXZ(goal) < 0.8) {
        _goal = goal;
        return null;
      }
      _goal = goal.copy();
      _path = sim.map.nav.findPath(p.pos, goal);
      _repathTimer = 3 + _rng.nextDouble() * 2;
    }
    while (_path.isNotEmpty && p.pos.distanceXZ(_path.first) < 0.7) {
      _path.removeAt(0);
    }
    if (_path.isEmpty) return null;

    // stuck detection
    if (p.pos.distanceXZ(_lastPos) < 0.05) {
      _stuckTimer += dt;
      if (_stuckTimer > 0.8) {
        _stuckTimer = 0;
        _repathTimer = 0;
        _path = [sim.map.nav.randomPointNear(p.pos, 3, _rng)];
      }
    } else {
      _stuckTimer = 0;
    }
    _lastPos.setFrom(p.pos);

    final next = _path.first;
    final dx = next.x - p.pos.x, dz = next.z - p.pos.z;
    final l = math.sqrt(dx * dx + dz * dz);
    if (l < 1e-4) return null;
    return Vec3(dx / l, 0, dz / l);
  }

  // ---------------------------------------------------------- abilities --
  void _maybeAbility(GameSim sim, Player p, Player enemy, PlayerInput inp) {
    final e = p.agentDef.e;
    if (e.kind == AbilityKind.heal && p.eCharges > 0 && p.hp < 50) {
      // Heal self: look away from teammates is fine, sim falls back to self.
      _pulse = Btn.abilityE;
    } else if (e.kind == AbilityKind.dash && p.eCharges > 0 && p.hp < 40) {
      _pulse = Btn.abilityE;
    }
  }

  void _maybeOpener(GameSim sim, Player p, PlayerInput inp) {
    if (_usedOpener || sim.phase != Phase.live) return;
    final site = sim.map.sites[sim.attackSiteIndex % sim.map.sites.length];
    final d = p.pos.distanceXZ(site.center);
    if (!sim.isAttacker(p) || d > 22 || d < 10) return;
    _usedOpener = true;
    if (_rng.nextDouble() > 0.4 + skill * 0.4) return;
    final q = p.agentDef.q, e = p.agentDef.e;
    // Throw utility at the site when about to enter it.
    _lookToward(p, site.center.copy()..y = 4, inp, 1, 100);
    if (e.kind == AbilityKind.smoke || e.kind == AbilityKind.recon) {
      if (p.eCharges > 0) _pulse = Btn.abilityE;
    } else if (q.kind == AbilityKind.smoke && p.qCharges > 0) {
      _pulse = Btn.abilityQ;
    }
  }
}
