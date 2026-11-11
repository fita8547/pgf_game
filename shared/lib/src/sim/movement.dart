import 'dart:math' as math;

import '../content/characters.dart';
import '../math.dart';
import '../world/collision.dart';
import 'input.dart';
import 'player.dart';

/// Character movement: a vertical capsule (three spheres) against the map's
/// oriented boxes. Includes the anti-abuse rules carried over from the old
/// prototype: no bunny hopping, no air-strafe speed gain, no tunnelling,
/// automatic step-up, no standing up into ceilings, and push-out/unstuck.
class Mover {
  final CollisionWorld world;
  Mover(this.world);

  static const double gravity = 20.0;
  static const double jumpSpeed = 7.0; // apex ~1.22 m

  /// Ledges up to this height are climbed without jumping.
  static const double stepHeight = 0.5;

  /// Contact normals with ny above this are floor (about 57 degrees).
  static const double walkableNy = 0.55;

  /// Anti bunny-hop: jumps started within [hopWindow] of landing chain, and
  /// each chained hop keeps only [hopKeep] of horizontal speed (80%, 64%...).
  static const double hopWindow = 0.3, hopKeep = 0.8;

  /// Briefly slower right after landing.
  static const double landSlow = 0.7, landSlowTime = 0.18;

  /// No single sub-step moves farther than this (thinnest walls are 0.1 m,
  /// capsule radius is 0.38 m, so the centre never crosses a wall).
  static const double maxStep = 0.2;
  static const double minStepAdvance = 0.12;

  final Contact _c = Contact();

  /// [speed] is the final max run speed (character x gun x modifiers).
  void move(Player p, PlayerInput inp, int pressed, double dt, {required double speed, bool frozen = false}) {
    final wasGround = p.onGround;
    if (p.jumpCooldown > 0) p.jumpCooldown -= dt;
    if (p.landPenalty > 0) p.landPenalty -= dt;
    if (p.onGround) p.groundTime += dt;

    // Standing up needs headroom; otherwise stay crouched.
    if (inp.has(Btn.crouch)) {
      p.crouch = true;
    } else if (p.crouch && !_capsuleHits(p.pos.x, p.pos.y, p.pos.z, standHeight)) {
      p.crouch = false;
    }
    p.walking = inp.has(Btn.walk);

    final baseSpeed = speed;
    var maxSpeed = baseSpeed;
    if (p.walking) maxSpeed *= 0.55;
    if (p.crouch) maxSpeed *= 0.45;
    if (p.ads) maxSpeed *= 0.75;
    if (p.landPenalty > 0) maxSpeed *= landSlow;
    if (frozen) maxSpeed = 0;

    final sy = math.sin(p.yaw), cy = math.cos(p.yaw);
    var wx = cy * inp.moveX + sy * inp.moveZ;
    var wz = sy * inp.moveX - cy * inp.moveZ;
    final wl = math.sqrt(wx * wx + wz * wz);
    if (wl > 1) {
      wx /= wl;
      wz /= wl;
    }

    final tx = wx * maxSpeed, tz = wz * maxSpeed;
    final accel = p.onGround ? (wl > 0.01 ? 55.0 : 42.0) : 8.0;
    final dvx = tx - p.vel.x, dvz = tz - p.vel.z;
    final dl = math.sqrt(dvx * dvx + dvz * dvz);
    final step = accel * dt;
    if (!p.onGround && wl < 0.01) {
      // keep momentum in the air
    } else if (dl <= step) {
      p.vel.x = tx;
      p.vel.z = tz;
    } else {
      p.vel.x += dvx / dl * step;
      p.vel.z += dvz / dl * step;
    }

    // Skill dashes drive horizontal velocity directly.
    final dashing = (p.fx['dash'] ?? 0) > 0;
    if (dashing) {
      p.vel.x = p.fx['dashVx'] ?? 0;
      p.vel.z = p.fx['dashVz'] ?? 0;
    }
    final leaping = (p.fx['leap'] ?? 0) > 0 && !p.onGround;

    // Never gain horizontal speed above the run cap; anything above it (e.g.
    // knockback) bleeds off quickly, faster on the ground. Skill dashes and
    // leaps are the only exceptions.
    final cap = baseSpeed * 1.02;
    final sp = p.vel.lengthXZ;
    if (sp > cap && !dashing && !leaping) {
      final ns = math.max(cap, sp - (p.onGround ? 60.0 : 12.0) * dt);
      p.vel.x *= ns / sp;
      p.vel.z *= ns / sp;
    }

    // Jump only on a fresh press, with chained-hop speed loss.
    var jumped = false;
    if (pressed & Btn.jump != 0 && p.onGround && !frozen && !p.crouch && p.jumpCooldown <= 0) {
      if (p.groundTime < hopWindow) {
        p.hopChain = math.min(p.hopChain + 1, 5);
        final keep = math.pow(hopKeep, p.hopChain).toDouble();
        p.vel.x *= keep;
        p.vel.z *= keep;
      } else {
        p.hopChain = 0;
      }
      p.vel.y = jumpSpeed;
      p.onGround = false;
      p.jumpCooldown = 0.12;
      jumped = true;
    }

    if (p.onGround && !jumped) {
      p.vel.y = 0;
    } else {
      p.vel.y = math.max(p.vel.y - gravity * dt, -45);
    }

    final dx = p.vel.x * dt, dy = p.vel.y * dt, dz = p.vel.z * dt;
    final maxD = math.max(math.sqrt(dx * dx + dz * dz), dy.abs());
    final n = (maxD / maxStep).ceil().clamp(1, 32);
    var grounded = p.onGround && !jumped;
    for (var i = 0; i < n; i++) {
      _horizontal(p, dx / n, dz / n, grounded);
      p.pos.y += p.vel.y * dt / n;
      final landed = _resolve(p);
      if (landed && p.vel.y <= 0) {
        p.vel.y = 0;
        grounded = true;
      }
    }

    // Stick to the floor when walking down slopes/steps instead of flying off.
    if (wasGround && !jumped && p.vel.y <= 0) _snapDown(p);
    p.onGround = !jumped && _groundProbe(p);
    if (p.onGround && p.vel.y < 0) p.vel.y = 0;

    if (!wasGround && p.onGround) {
      p.groundTime = 0;
      p.landPenalty = landSlowTime;
    }
  }

  List<double> _offsets(double h) => [playerRadius, h * 0.5, h - playerRadius];

  bool _capsuleHits(double x, double y, double z, double h, {double shrink = 0.02}) {
    for (final o in _offsets(h)) {
      if (world.sphereHits(x, y + o, z, playerRadius - shrink, Col.move)) return true;
    }
    return false;
  }

  bool overlaps(Player p) => _capsuleHits(p.pos.x, p.pos.y, p.pos.z, p.height, shrink: 0.05);

  /// Horizontal move with automatic step-up onto low ledges.
  void _horizontal(Player p, double dx, double dz, bool grounded) {
    if (dx == 0 && dz == 0) return;
    final sx = p.pos.x, sy = p.pos.y, sz = p.pos.z;
    final svx = p.vel.x, svz = p.vel.z;
    p.pos.x += dx;
    p.pos.z += dz;
    _resolve(p);
    final want = math.sqrt(dx * dx + dz * dz);
    final gotA = math.sqrt((p.pos.x - sx) * (p.pos.x - sx) + (p.pos.z - sz) * (p.pos.z - sz));
    if (!grounded || gotA >= want * 0.9) return;

    // Blocked: retry from step height, then settle back down.
    final ax = p.pos.x, ay = p.pos.y, az = p.pos.z;
    final avx = p.vel.x, avz = p.vel.z;
    if (_capsuleHits(sx, sy + stepHeight, sz, p.height)) return;
    // Probe at least [minStepAdvance] ahead so the capsule gets over the edge
    // even when blocked velocity has dropped to a crawl.
    final adv = math.max(want, minStepAdvance) / want;
    p.pos.set(sx + dx * adv, sy + stepHeight, sz + dz * adv);
    p.vel.x = svx;
    p.vel.z = svz;
    _resolve(p);
    final gotB = math.sqrt((p.pos.x - sx) * (p.pos.x - sx) + (p.pos.z - sz) * (p.pos.z - sz));
    if (gotB > gotA + 1e-4 && _settle(p, stepHeight + 0.05) && p.pos.y > sy + 0.02) return;
    p.pos.set(ax, ay, az);
    p.vel.x = avx;
    p.vel.z = avz;
  }

  /// Lowers the player by up to [maxDrop] until the feet touch walkable
  /// ground (sphere probe, so ledge edges count). Restores and returns false
  /// if there's no floor that close.
  bool _settle(Player p, double maxDrop) {
    final y0 = p.pos.y;
    for (var d = 0.0; d <= maxDrop + 1e-9; d += 0.04) {
      p.pos.y = y0 - d;
      if (_groundProbe(p)) {
        _resolve(p);
        return true;
      }
    }
    p.pos.y = y0;
    return false;
  }

  void _snapDown(Player p) {
    if (_groundProbe(p)) return;
    _settle(p, stepHeight);
  }

  bool _groundProbe(Player p) {
    _c.reset();
    world.sphere(p.pos.x, p.pos.y + playerRadius - 0.06, p.pos.z, playerRadius - 0.01, Col.move, _c);
    return _c.count > 0 && _c.maxNy > walkableNy;
  }

  /// Pushes the capsule out of geometry. Returns true if it rests on floor.
  bool _resolve(Player p) {
    var landed = false;
    final offs = _offsets(p.height);
    for (var iter = 0; iter < 4; iter++) {
      var any = false;
      for (var k = 0; k < 3; k++) {
        // Per contact: floors lift straight up (no sliding on slopes), walls
        // and ceilings push along their normal and clip velocity.
        var lift = 0.0, px = 0.0, py = 0.0, pz = 0.0;
        var hits = 0;
        world.sphereEach(p.pos.x, p.pos.y + offs[k], p.pos.z, playerRadius, Col.move, (nx, ny, nz, depth) {
          if (depth < 1e-7) return;
          hits++;
          if (ny > walkableNy) {
            lift = math.max(lift, math.min(depth / ny, stepHeight + 0.1));
            landed = true;
            return;
          }
          if (ny > 0) {
            // Too steep to stand on (ledge edge, steep slope): a pure wall,
            // so it neither launches us upward nor lets us climb it.
            final h = math.sqrt(nx * nx + nz * nz);
            if (h < 1e-6) return;
            depth *= h;
            nx /= h;
            nz /= h;
            ny = 0;
          }
          px += nx * depth;
          py += ny * depth;
          pz += nz * depth;
          final vn = p.vel.x * nx + p.vel.y * ny + p.vel.z * nz;
          if (vn < 0) {
            p.vel.x -= nx * vn;
            p.vel.y -= ny * vn;
            p.vel.z -= nz * vn;
          }
        });
        if (hits == 0) continue;
        any = true;
        p.pos.x += px;
        p.pos.y += py + lift;
        p.pos.z += pz;
      }
      if (!any) break;
    }
    return landed;
  }

  /// Anti-stuck: true if the player is still inside geometry this tick.
  bool stuck(Player p, double dt) {
    if (overlaps(p)) {
      p.stuckTime += dt;
    } else {
      p.stuckTime = 0;
    }
    return p.stuckTime > 0.4;
  }

  /// Clamps a teleport/spawn position up onto the floor.
  void placeOnGround(Player p) {
    final g = world.groundBelow(p.pos.x, p.pos.z, p.pos.y + 1.0, maxDrop: 6);
    if (g != null) p.pos.y = g + 0.001;
    _resolve(p);
    p.onGround = _groundProbe(p);
  }

  /// Exposed for tests/tools.
  bool capsuleFree(double x, double y, double z, {double h = standHeight}) => !_capsuleHits(x, y, z, h);

  static double clampSpeed(double v) => clampD(v, 0, 20);
}
