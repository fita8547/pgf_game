import 'dart:math' as math;

import '../content/guns.dart';
import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';
import 'sim.dart';

/// Simple bot: buys a gun in spawn, walks the nav graph to the capture point,
/// fights what it sees. It only produces [PlayerInput]s, so it obeys exactly
/// the same movement/shooting rules as a human.
class BotBrain {
  /// 0 (bad) .. 1 (sharp): reaction time, aim error, recoil control.
  final double skill;
  final Rng rng;
  BotBrain(this.skill, {int seed = 1}) : rng = Rng(seed);

  int _seq = 0;
  List<Vec3> _path = const [];
  int _wp = 0;
  double _repath = 0;
  Vec3? _goal;
  int? _target;
  double _react = 0;
  double _yaw = 0, _pitch = 0;
  double _strafe = 1, _strafeT = 0;
  double _noProgress = 0;
  Vec3 _lastPos = Vec3.zero();
  double _errYaw = 0, _errPitch = 0, _errT = 0;
  bool _fireHeld = false;
  double _skillT = 2;
  int _stuckCount = 0;

  /// Time spent tracking the current target (aim settles over it).
  double _trackT = 0;
  bool _aimHead = false;

  /// Extra pause between semi-auto shots (humans don't fire at max rate).
  double _semiT = 0;
  bool _wasAlive = false;

  static const _primaryWishlist = ['rifle', 'smg', 'shotgun', 'sniper', 'launcher'];

  PlayerInput think(GameSim sim, Player p, double dt) {
    final inp = PlayerInput(seq: ++_seq, dt: dt, yaw: p.yaw, pitch: p.pitch);
    if (!p.alive) {
      _wasAlive = false;
      return inp;
    }
    if (!_wasAlive) {
      _wasAlive = true;
      _yaw = p.yaw;
      _pitch = 0;
      _path = const [];
      _target = null;
    }

    _shop(sim, p);

    // --- target selection
    Player? target;
    var bestD = double.infinity;
    for (final q in sim.players.values) {
      if (!q.alive || q.team == p.team) continue;
      final chest = Vec3(q.pos.x, q.pos.y + q.body.hips + 0.3, q.pos.z);
      final d = p.pos.distanceTo(q.pos);
      final aware = q.id == _target || p.sinceDamaged < 1.5;
      if (d < bestD && sim.canSee(p, chest, fovCos: aware ? -1 : 0.35, maxDist: 45 + 45 * skill)) {
        bestD = d;
        target = q;
      }
    }
    if (target?.id != _target) {
      _target = target?.id;
      _react = 0.75 - 0.5 * skill + rng.range(0, 0.3);
      _trackT = 0;
      _aimHead = rng.nextDouble() < 0.05 + 0.3 * skill;
    }
    if (_react > 0) _react -= dt;

    // --- aim
    _errT -= dt;
    if (_errT <= 0) {
      final settle = 1 + 2.5 * math.exp(-_trackT * 1.2);
      final e = ((1 - skill) * 0.09 + 0.012) * settle;
      _errYaw = rng.range(-e, e);
      _errPitch = rng.range(-e, e) * 0.6;
      _errT = rng.range(0.25, 0.6);
    }
    var wantYaw = _yaw, wantPitch = _pitch;
    if (target != null) {
      _trackT += dt;
      final aimHead = _aimHead;
      final ty =
          target.pos.y + (aimHead ? target.body.headCenter : target.body.hips + 0.3) * (target.crouch ? 0.67 : 1.0);
      final at = Vec3(target.pos.x, ty, target.pos.z);
      wantYaw = yawTo(p.eye, at) + _errYaw;
      wantPitch = pitchTo(p.eye, at) + _errPitch;
      // Pull down against recoil (better bots compensate more).
      final (rp, _) = p.gun.recoilAt(p.recoilIndex);
      wantPitch -= rp * (0.3 + 0.6 * skill);
    } else if (_path.isNotEmpty && _wp < _path.length) {
      final wpt = _path[_wp];
      if (wpt.distanceXZ(p.pos) > 0.3) wantYaw = yawTo(p.pos, wpt);
      wantPitch = 0;
    }
    final turn = (2.5 + 6 * skill) * dt;
    _yaw = wrapAngle(_yaw + clampD(wrapAngle(wantYaw - _yaw), -turn, turn));
    _pitch = clampD(_pitch + clampD(wantPitch - _pitch, -turn, turn), -1.4, 1.4);
    inp
      ..yaw = _yaw
      ..pitch = _pitch;

    // --- shooting
    var buttons = 0;
    final s = p.gun.stats;
    if (target != null && _react <= 0) {
      final err = wrapAngle(wantYaw - _yaw).abs() + (wantPitch - _pitch).abs();
      final dist = bestD;
      final tol = 0.04 + 0.6 / math.max(dist, 1);
      if (err < tol) {
        if (s.auto) {
          // Burst at range, spray up close.
          final burst = dist > 20 ? 3 : (6 + 6 * skill).round();
          if (p.recoilIndex < burst) buttons |= Btn.fire;
        } else if (!_fireHeld && p.fireCooldown <= 0 && _semiT <= 0) {
          _semiT = rng.range(0.15, 0.45) * (1.3 - skill);
          buttons |= Btn.fire;
        }
      }
      if ((p.gunId == 'sniper' || p.gunId == 'rifle') && dist > 15) buttons |= Btn.ads;
    }
    _fireHeld = buttons & Btn.fire != 0;
    if (_semiT > 0) _semiT -= dt;

    // Skills: every few seconds in a fight, press a random one; ult when ready.
    _skillT -= dt;
    if (target != null && _react <= 0 && _skillT <= 0) {
      _skillT = rng.range(2.5, 6) * (1.4 - skill * 0.6);
      const keys = [Btn.skillQ, Btn.skillE, Btn.skillShift];
      buttons |= keys[rng.nextInt() % keys.length];
      if (sim.ultReady(p) && bestD < 25) buttons |= Btn.ult;
    }
    if (p.mag == 0 || (target == null && p.mag < s.mag * 0.4 && p.reserve > 0)) buttons |= Btn.reload;
    if (p.slot == 1 && p.primary != null) buttons |= Btn.slotPrimary;

    // --- movement
    _repath -= dt;
    final goal = _goal;
    if (goal == null || _repath <= 0 || _wp >= _path.length) {
      final nodes = sim.captureNodes;
      if (nodes.isEmpty) {
        _goal = sim.map.capture;
      } else {
        _goal = sim.nav.node(nodes[rng.nextInt() % nodes.length]);
      }
      _path = sim.nav.path(p.pos, _goal!, team: p.team);
      _wp = 0;
      _repath = rng.range(2.5, 4);
    }
    var mx = 0.0, mz = 0.0;
    if (_wp < _path.length) {
      final wpt = _path[_wp];
      if (wpt.distanceXZ(p.pos) < 0.45 && (wpt.y - p.pos.y).abs() < 1.2) {
        _wp++;
      }
      if (_wp < _path.length) {
        final t = _path[_wp];
        var wx = t.x - p.pos.x, wz = t.z - p.pos.z;
        final l = math.sqrt(wx * wx + wz * wz);
        if (l > 1e-6) {
          wx /= l;
          wz /= l;
        }
        final cy = math.cos(_yaw), sy = math.sin(_yaw);
        mx = cy * wx + sy * wz;
        mz = sy * wx - cy * wz;
        if (t.y - p.pos.y > 0.45 && l < 1.3) buttons |= Btn.jump;
        // Jump links: something knee-high, or a gap, before the next waypoint.
        if (l < 1.5 && p.onGround) {
          final w = sim.map.world;
          final blocked =
              !w.lineClear(Vec3(p.pos.x, p.pos.y + 0.6, p.pos.z), Vec3(t.x, t.y + 0.6, t.z), mask: Col.move);
          final mid = w.groundBelow((p.pos.x + t.x) / 2, (p.pos.z + t.z) / 2, math.max(p.pos.y, t.y) + 0.3);
          final gap = l > 0.9 && (mid == null || mid < math.min(p.pos.y, t.y) - 0.4);
          if (blocked || gap) buttons |= Btn.jump;
        }
      }
    }
    if (target != null && _react <= 0 && bestD < 30) {
      // Strafe while fighting; hold ground instead of walking into them.
      _strafeT -= dt;
      if (_strafeT <= 0) {
        _strafe = rng.nextDouble() < 0.5 ? -1 : 1;
        _strafeT = rng.range(0.3, 0.9);
      }
      mx = _strafe;
      mz = bestD > 12 ? mz * 0.5 : 0;
    }
    if (p.pos.distanceXZ(_lastPos) < 0.01 && (mx != 0 || mz != 0)) {
      _noProgress += dt;
      if (_noProgress > 0.8) {
        buttons |= Btn.jump;
        _repath = 0;
        _noProgress = 0;
        // Stuck repeatedly: give up on this goal and pick another spot.
        if (++_stuckCount >= 3) {
          _stuckCount = 0;
          _goal = null;
        }
      }
    } else {
      _noProgress = 0;
    }
    _lastPos = p.pos.copy();

    inp
      ..moveX = mx
      ..moveZ = mz
      ..buttons = buttons;
    return inp;
  }

  void _shop(GameSim sim, Player p) {
    if (p.primary != null || !sim.map.inSpawnRoom(p.team, p.pos)) return;
    final options = _primaryWishlist.where((g) => gunById(g).stats.cost <= p.credits).toList();
    if (options.isEmpty) {
      // Only well-off bots bother with the revolver.
      if (p.secondary == 'pistol' && p.credits >= 1500 && rng.nextDouble() < 0.002) {
        sim.buy(p, 'revolver');
      }
      return;
    }
    // Mostly the best affordable, sometimes a random one for variety.
    final pick = rng.nextDouble() < 0.7 ? options.first : options[rng.nextInt() % options.length];
    sim.buy(p, pick);
  }
}
