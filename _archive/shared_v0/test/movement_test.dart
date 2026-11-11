import 'dart:math' as math;

import 'package:pgf_shared/pgf_shared.dart';
import 'package:test/test.dart';

const dt = 1 / 60;

/// Open north-south lane on Dunewall.
const lx = -8.0;

/// A live-phase sim with one player standing in open ground at (lx, 0, 22),
/// facing north (-Z).
(GameSim, Player) setup() {
  final sim = GameSim();
  final p = sim.addPlayer('t', team: 0);
  sim.phase = Phase.live;
  p.pos.set(lx, 0, 22);
  p.yaw = 0;
  for (var z = 14.0; z <= 26; z++) {
    expect(sim.map.nav.isBlockedAt(lx, z), isFalse, reason: 'test lane must be open at z=$z');
  }
  return (sim, p);
}

var _seq = 0;
void step(GameSim sim, Player p, {double mz = 0, int buttons = 0, double yaw = 0}) =>
    sim.processInput(p, PlayerInput(seq: ++_seq, dt: dt, moveZ: mz, yaw: yaw, buttons: buttons));

void main() {
  group('anti bunny-hop', () {
    test('holding jump does not auto-hop', () {
      final (sim, p) = setup();
      var jumps = 0;
      var wasGround = true;
      for (var i = 0; i < 180; i++) {
        step(sim, p, buttons: Btn.jump);
        if (wasGround && !p.onGround) jumps++;
        wasGround = p.onGround;
      }
      expect(jumps, 1);
    });

    test('timed hops never exceed run speed and chain hops lose speed', () {
      final (sim, p) = setup();
      p.pos.set(lx, 0, 26);
      var top = 0.0;
      for (var i = 0; i < 20; i++) {
        step(sim, p, mz: 1);
      }
      final runSpeed = p.vel.lengthXZ;
      // press jump on the first ground frame every time (perfect bhop timing)
      var hops = 0, prevGround = true;
      for (var i = 0; i < 90 && hops < 4; i++) {
        final press = p.onGround && !prevGround || i == 0;
        prevGround = p.onGround;
        step(sim, p, mz: 1, buttons: press ? Btn.jump : 0);
        if (press) hops++;
        top = math.max(top, p.vel.lengthXZ);
      }
      expect(top, lessThanOrEqualTo(runSpeed * 1.03));
      expect(p.hopChain, greaterThan(0));
    });

    test('dash momentum is not carried by hopping', () {
      final (sim, p) = setup();
      p.pos.set(lx, 0, 26);
      p.dashX = 0;
      p.dashZ = -1;
      p.dashTime = 0.2;
      for (var i = 0; i < 12; i++) {
        step(sim, p);
      }
      step(sim, p, buttons: Btn.jump);
      for (var i = 0; i < 45; i++) {
        step(sim, p);
      }
      expect(p.vel.lengthXZ, lessThanOrEqualTo(GameSim.runSpeed * 1.03));
    });
  });

  group('anti stuck', () {
    test('dash cannot tunnel through a thin barrier', () {
      final (sim, p) = setup();
      sim.barriers.add(Barrier(Aabb(lx + -3, 0, 20.7, lx + 3, 2.6, 21.0), 30));
      p.dashX = 0;
      p.dashZ = -1;
      p.dashTime = 0.2;
      for (var i = 0; i < 6; i++) {
        sim.processInput(p, PlayerInput(seq: ++_seq, dt: 0.1)); // laggy 10 fps frames
      }
      expect(p.pos.z, greaterThan(21.0));
    });

    test('barrier spawned on top of a player pushes them out', () {
      final (sim, p) = setup();
      sim.barriers.add(Barrier(Aabb(lx + -2.2, 0, 21.7, lx + 2.2, 2.6, 22.3), 30));
      step(sim, p);
      final b = sim.barriers.first.box;
      final r = playerRadius;
      expect(b.overlaps(p.pos.x - r, p.pos.y, p.pos.z - r, p.pos.x + r, p.pos.y + p.height, p.pos.z + r), isFalse);
    });

    test('cannot stand up into a low ceiling', () {
      final (sim, p) = setup();
      step(sim, p, buttons: Btn.crouch);
      sim.barriers.add(Barrier(Aabb(lx + -2, 1.4, 20, lx + 2, 3, 24), 30));
      step(sim, p); // released crouch
      expect(p.crouch, isTrue);
      sim.barriers.clear();
      step(sim, p);
      expect(p.crouch, isFalse);
    });

    test('walks up low ledges instead of snagging', () {
      final (sim, p) = setup();
      sim.barriers.add(Barrier(Aabb(lx + -3, 0, 18, lx + 3, 0.3, 21), 30));
      for (var i = 0; i < 60; i++) {
        step(sim, p, mz: 1);
      }
      expect(p.pos.z, lessThan(20.5));
    });

    test('falling out of the map is rescued in place', () {
      final (sim, p) = setup();
      p.pos.set(lx, -6, 22);
      step(sim, p);
      expect(p.pos.y, greaterThanOrEqualTo(0));
      expect(p.pos.distanceXZ(Vec3(lx, 0, 22)), lessThan(2));
    });
  });

  group('weapons', () {
    test('spray pattern starts on target then climbs', () {
      final talon = weapons[WeaponId.talon]!;
      expect(talon.recoilAt(0), (0.0, 0.0));
      final (p5, _) = talon.recoilAt(5);
      final (p10, _) = talon.recoilAt(10);
      expect(p10, greaterThan(p5));
      expect(talon.recoilAt(40).$1.isFinite, isTrue); // loops past the end
    });

    test('falloff and time-to-kill', () {
      final hornet = weapons[WeaponId.hornet]!;
      expect(hornet.damageAt(1, 5), 26);
      expect(hornet.damageAt(1, 40), closeTo(26 * 0.65, 1e-9));
      final talon = weapons[WeaponId.talon]!;
      expect(talon.shotsToKill(0, 20, shield: 50), 1); // rifle head one-tap
      expect(weapons[WeaponId.lancer]!.shotsToKill(1, 40), 1);
    });
  });

  group('input guard', () {
    test('speedhack frames are dropped', () {
      final g = InputGuard();
      var accepted = 0;
      for (var i = 1; i <= 600; i++) {
        if (i % 2 == 0) g.tick(dt); // client claims 2x real time
        if (g.accept(PlayerInput(seq: i, dt: dt)) != null) accepted++;
      }
      expect(accepted, lessThan(330));
      expect(g.droppedForTime, greaterThan(0));
    });

    test('replayed and garbage inputs', () {
      final g = InputGuard()..tick(0.1);
      expect(g.accept(PlayerInput(seq: 5, dt: dt)), isNotNull);
      expect(g.accept(PlayerInput(seq: 5, dt: dt)), isNull);
      final i = g.accept(PlayerInput(seq: 6, dt: double.nan, yaw: 1e300, pitch: double.infinity, moveX: 9))!;
      expect([i.dt, i.yaw.isFinite, i.pitch, i.moveX], [0, true, 0, 1]);
    });
  });
}
