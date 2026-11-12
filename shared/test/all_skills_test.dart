import 'dart:math' as math;

import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

import 'combat_test.dart' show arena, dt, place;

/// Press [btn] once (with aim), then let [seconds] of game time pass.
void cast(GameSim sim, Player p, int btn, {double yaw = 0, double pitch = 0, double seconds = 0}) {
  sim.processInput(p, PlayerInput(dt: dt, buttons: btn, yaw: yaw, pitch: pitch));
  sim.processInput(p, PlayerInput(dt: dt, yaw: yaw, pitch: pitch));
  for (var i = 0; i < (seconds / dt).round(); i++) {
    sim.update(dt);
  }
}

/// Holds [btn] / movement for [seconds] while the sim runs.
void hold(GameSim sim, Player p, double seconds, {int btn = 0, double moveZ = 0, double yaw = 0, double pitch = 0}) {
  for (var i = 0; i < (seconds / dt).round(); i++) {
    sim.processInput(p, PlayerInput(dt: dt, buttons: btn, moveZ: moveZ, yaw: yaw, pitch: pitch));
    sim.update(dt);
  }
}

(GameSim, Player, Player) duel(String me, String enemy, {double dist = 6}) {
  final sim = arena();
  final p = place(sim, sim.addPlayer('me', me, teamId: 0), 0, 10);
  final e = place(sim, sim.addPlayer('foe', enemy, teamId: 1), 0, 10 - dist);
  return (sim, p, e);
}

void charge(Player p) => p.ult = p.character.stats.ultCost;

void main() {
  test('every catalog skill has an implementation', () {
    final missing = [
      for (final c in characters)
        for (final s in c.info.skills)
          if (skillImpls[s.id] == null) '${c.id}/${s.id}',
    ];
    expect(missing, isEmpty);
  });

  group('볼더', () {
    test('Q bulwark blocks bullets, recall frees it', () {
      final (sim, p, e) = duel('boulder', 'pebble');
      cast(sim, p, Btn.skillQ);
      expect(sim.deployables.single.kind, 'rock_bulwark');
      final hit = sim.traceShot(e, e.eye, (p.eye - e.eye).normalized(), 50, -1);
      expect(hit.victim, isNull);
      expect(hit.dep, sim.deployables.single.id);
      cast(sim, p, Btn.skillQ);
      expect(sim.deployables, isEmpty);
    });
    test('E charge grabs and damages', () {
      final (sim, p, e) = duel('boulder', 'gem', dist: 4);
      cast(sim, p, Btn.skillE);
      hold(sim, p, 1.2);
      expect(e.hp, lessThan(200 - 40));
    });
    test('Shift magma pierces two enemies', () {
      final (sim, p, e) = duel('boulder', 'gem');
      final e2 = place(sim, sim.addPlayer('foe2', 'needle', teamId: 1), 0, 0);
      cast(sim, p, Btn.skillShift, pitch: 0.02, seconds: 1);
      expect(e.hp, lessThan(200));
      expect(e2.hp, lessThan(200));
    });
    test('ult knocks down in a cone', () {
      final (sim, p, e) = duel('boulder', 'gem');
      charge(p);
      cast(sim, p, Btn.ult);
      expect(sim.has(e, 'stun'), isTrue);
    });
  });

  group('카드보드', () {
    test('Q dome stops bullets from outside', () {
      final (sim, p, e) = duel('cardboard', 'pebble', dist: 12);
      cast(sim, p, Btn.skillQ, pitch: -1.2, seconds: 1.5);
      final dome = sim.deployables.single;
      expect(dome.kind, 'box_fort');
      final hit = sim.traceShot(e, e.eye, (p.eye - e.eye).normalized(), 50, -1);
      expect(hit.victim, isNull);
    });
    test('E roll: faster, no shooting, bumps enemies', () {
      final (sim, p, e) = duel('cardboard', 'gem', dist: 5);
      cast(sim, p, Btn.skillE);
      expect(p.mode, 'roll');
      expect(sim.moveMult(p), closeTo(1.9, 1e-9));
      final shots = p.shotSeq;
      cast(sim, p, Btn.fire);
      expect(p.shotSeq, shots, reason: 'no shooting while rolling');
      sim.applyDamage(p, 100, e, 'rifle', false);
      expect(p.hp, closeTo(p.maxHp - 100 * 0.9 * 0.5 * 0.75, 0.01), reason: 'roll halves damage on top of tank armour');
      p.hp = p.maxHp;
      hold(sim, p, 1, moveZ: 1);
      expect(e.hp, lessThan(200));
      cast(sim, p, Btn.skillE);
      expect(p.mode, '');
      expect(p.skillCd[1], greaterThan(5));
    });
    test('E roll: jump and land slams nearby enemies', () {
      final (sim, p, e) = duel('cardboard', 'gem', dist: 2.5);
      cast(sim, p, Btn.skillE);
      hold(sim, p, 0.5);
      expect(e.hp, e.maxHp, reason: 'no slam without a jump');
      hold(sim, p, 0.05, btn: Btn.jump);
      hold(sim, p, 1);
      expect(p.mode, 'roll');
      expect(e.hp, lessThan(e.maxHp));
      expect(e.hp, greaterThan(e.maxHp - 60), reason: 'one slam only');
    });
    test('Shift hook pulls the enemy', () {
      final (sim, p, e) = duel('cardboard', 'gem', dist: 12);
      cast(sim, p, Btn.skillShift, pitch: -0.03, seconds: 0.5);
      expect(e.pos.distanceTo(p.pos), lessThan(3));
    });
    test('ult mines explode on enemies', () {
      final (sim, p, e) = duel('cardboard', 'gem', dist: 3);
      charge(p);
      cast(sim, p, Btn.ult, seconds: 1.5);
      expect(e.hp, lessThan(200));
    });
  });

  group('시어', () {
    test('Q guard cuts frontal damage and spikes back', () {
      final (sim, p, e) = duel('shear', 'pebble');
      cast(sim, p, Btn.skillQ);
      expect(p.mode, 'guard');
      sim.applyDamage(p, 100, e, 'pistol', false);
      // attack 135% x guard 25% x tank armour 75%
      expect(p.hp, closeTo(300 - 100 * 1.35 * 0.25 * 0.75, 0.5));
      expect(e.hp, lessThan(200));
    });
    test('E leap lands and cleaves', () {
      final (sim, p, e) = duel('shear', 'gem', dist: 8);
      cast(sim, p, Btn.skillE);
      hold(sim, p, 2);
      expect(e.hp, lessThan(200));
    });
    test('Shift fence blocks movement', () {
      final (sim, p, e) = duel('shear', 'gem', dist: 8);
      cast(sim, p, Btn.skillShift);
      expect(sim.deployables.single.collider, isNotNull);
    });
    test('ult roots the area', () {
      final (sim, p, e) = duel('shear', 'gem', dist: 8);
      charge(p);
      cast(sim, p, Btn.ult, pitch: -0.2, seconds: 1.3);
      expect(sim.has(e, 'root'), isTrue);
    });
  });

  group('오리가미', () {
    test('Q updraft goes high', () {
      final (sim, p, _) = duel('origami', 'gem');
      var top = 0.0;
      cast(sim, p, Btn.skillQ);
      for (var i = 0; i < 90; i++) {
        hold(sim, p, dt);
        if (p.pos.y > top) top = p.pos.y;
      }
      expect(top, greaterThan(3));
    });
    test('E dash follows WASD, diagonals too', () {
      for (final (mx, mz) in [(1.0, 0.0), (-1.0, 0.0), (0.0, -1.0), (1.0, 1.0)]) {
        final (sim, p, _) = duel('origami', 'gem', dist: 30);
        final start = p.pos.copy();
        sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.skillE, moveX: mx, moveZ: mz));
        for (var i = 0; i < 24; i++) {
          sim.processInput(p, PlayerInput(dt: dt, moveX: mx, moveZ: mz));
          sim.update(dt);
        }
        final dx = p.pos.x - start.x, dz = p.pos.z - start.z;
        // yaw 0: right = +x, forward = -z.
        final l = math.sqrt(mx * mx + mz * mz);
        expect(dx / math.sqrt(dx * dx + dz * dz), closeTo(mx / l, 0.1), reason: 'dir ($mx,$mz)');
        expect(-dz / math.sqrt(dx * dx + dz * dz), closeTo(mz / l, 0.1), reason: 'dir ($mx,$mz)');
        expect(math.sqrt(dx * dx + dz * dz), greaterThan(4), reason: 'dash, not walk ($mx,$mz)');
      }
    });
    test('E dash moves fast, kill resets', () {
      final (sim, p, e) = duel('origami', 'gem');
      cast(sim, p, Btn.skillE);
      hold(sim, p, 0.4);
      expect(p.pos.z, lessThan(6));
      expect(p.skillCharges[1], 0);
      sim.applyDamage(e, 999, p, 'pistol', false);
      expect(p.skillCharges[1], 1);
    });
    test('Shift crane reveals what it hits', () {
      final (sim, p, e) = duel('origami', 'gem', dist: 8);
      final aim = Vec3(e.pos.x, e.pos.y + 1.1, e.pos.z);
      cast(sim, p, Btn.skillShift, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim));
      hold(sim, p, 1.5, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim));
      expect(e.revealed, greaterThan(0));
    });
    test('ult shurikens hit hard', () {
      final (sim, p, e) = duel('origami', 'gem', dist: 10);
      charge(p);
      cast(sim, p, Btn.ult);
      expect(p.mode, 'shuriken');
      final aim = Vec3(e.pos.x, e.pos.y + 1.1, e.pos.z);
      cast(sim, p, Btn.fire, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim));
      expect(e.hp, lessThan(200 - 80));
    });
  });

  group('스닙', () {
    test('Q gale cut damages on the way', () {
      final (sim, p, e) = duel('snip', 'gem', dist: 4);
      cast(sim, p, Btn.skillQ);
      hold(sim, p, 0.5);
      expect(e.hp, lessThan(200 - 70));
    });
    test('E deflect blocks frontal damage and returns it doubled', () {
      final (sim, p, e) = duel('snip', 'gem');
      cast(sim, p, Btn.skillE);
      sim.applyDamage(p, 40, e, 'rifle', false);
      expect(p.hp, p.maxHp);
      // What snip would have taken (40 x gem 0.9 x snip taken 1.2), x2, x snip's attack 1.35.
      expect(e.hp, closeTo(e.maxHp - 40 * 0.9 * 1.2 * 2 * 1.35, 0.5));
    });
    test('E deflect: two snips deflecting each other do not loop', () {
      final (sim, p, e) = duel('snip', 'snip');
      cast(sim, p, Btn.skillE);
      cast(sim, e, Btn.skillE, yaw: math.pi);
      sim.applyDamage(p, 20, e, 'rifle', false);
      expect(p.hp, p.maxHp);
      expect(e.hp, e.maxHp, reason: 'the bounce is blocked by the other deflect, not bounced again');
    });
    test('Shift(C) beacon roots enemies where it lands', () {
      final (sim, p, e) = duel('snip', 'gem', dist: 6);
      cast(sim, p, Btn.skillShift, seconds: 0.6);
      expect(sim.has(e, 'root'), isTrue);
      expect(sim.deployables, isEmpty, reason: 'no teleport beacon any more');
      expect(p.skillCd[2], greaterThan(5));
    });
    test('ult melee mode slashes', () {
      final (sim, p, e) = duel('snip', 'gem', dist: 2);
      charge(p);
      cast(sim, p, Btn.ult);
      final aim = Vec3(e.pos.x, e.pos.y + 1, e.pos.z);
      cast(sim, p, Btn.fire, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim));
      expect(e.hp, lessThan(200 - 70));
    });
  });

  group('젬', () {
    test('Q crystal heals the targeted ally over time', () {
      final (sim, p, _) = duel('gem', 'pebble');
      final ally = place(sim, sim.addPlayer('ally', 'boulder', teamId: 0), 0, 5)..hp = 100;
      final aim = Vec3(ally.pos.x, ally.pos.y + 1.1, ally.pos.z);
      cast(sim, p, Btn.skillQ, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim), seconds: 2);
      expect(ally.hp, greaterThan(140));
    });
    test('E amp boosts ally damage', () {
      final (sim, p, e) = duel('gem', 'quake');
      cast(sim, p, Btn.skillE, pitch: -0.6, seconds: 0.2);
      sim.applyDamage(e, 100, p, 'pistol', false);
      // healer deals 90% x amp (+25%); controller takes 100%
      expect(e.hp, closeTo(225 - 100 * 0.9 * 1.25, 0.5));
    });
    test('Shift bell: invulnerable and cleansed', () {
      final (sim, p, e) = duel('gem', 'pebble');
      sim.addFx(p, 'root', 3);
      cast(sim, p, Btn.skillShift, pitch: 1.4);
      expect(sim.has(p, 'root'), isFalse);
      sim.applyDamage(p, 100, e, 'pistol', false);
      expect(p.hp, 200);
    });
    test('ult tree heals around it', () {
      final (sim, p, _) = duel('gem', 'pebble');
      p.hp = 50;
      charge(p);
      cast(sim, p, Btn.ult, pitch: -1.2, seconds: 1);
      expect(p.hp, greaterThan(90));
    });
  });

  group('니들', () {
    test('Q tether heals, press again cuts it', () {
      final (sim, p, _) = duel('needle', 'pebble');
      final ally = place(sim, sim.addPlayer('ally', 'boulder', teamId: 0), 0, 4)..hp = 100;
      final aim = Vec3(ally.pos.x, ally.pos.y + 1.1, ally.pos.z);
      cast(sim, p, Btn.skillQ, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim), seconds: 1);
      expect(ally.hp, greaterThan(140));
      cast(sim, p, Btn.skillQ);
      expect(p.fx.containsKey('linkTo'), isFalse);
    });
    test('E sleep dart: asleep, can not move or shoot, damage wakes', () {
      final (sim, p, e) = duel('needle', 'gem', dist: 10);
      final aim = Vec3(e.pos.x, e.pos.y + 1.1, e.pos.z);
      cast(sim, p, Btn.skillE, yaw: yawTo(p.eye, aim), pitch: pitchTo(p.eye, aim), seconds: 0.3);
      expect(sim.has(e, 'sleep'), isTrue);
      final shots = e.shotSeq;
      cast(sim, e, Btn.fire);
      expect(e.shotSeq, shots);
      sim.applyDamage(e, 5, p, 'pistol', false);
      expect(sim.has(e, 'sleep'), isFalse);
    });
    test('Shift grenade: enemies anti-healed', () {
      final (sim, p, e) = duel('needle', 'gem', dist: 6);
      cast(sim, p, Btn.skillShift, pitch: -0.2, seconds: 1.5);
      expect(sim.has(e, 'antiheal'), isTrue);
      final hp = e.hp;
      sim.heal(e, 50, null);
      expect(e.hp, hp);
    });
    test('ult nano: more damage dealt, less taken', () {
      final (sim, p, e) = duel('needle', 'gem');
      charge(p);
      cast(sim, p, Btn.ult, pitch: 1.4);
      sim.applyDamage(p, 100, e, 'pistol', false);
      expect(p.hp, closeTo(200 - 100 * 0.9 * 0.5, 0.5)); // healer dealt 90%, nano -50%
    });
  });

  group('스크롤', () {
    test('Q seal heals allies inside', () {
      final (sim, p, _) = duel('scroll', 'gem');
      p.hp = 100;
      cast(sim, p, Btn.skillQ, seconds: 1);
      expect(p.hp, greaterThan(130));
    });
    test('E talisman shield soaks damage', () {
      final (sim, p, e) = duel('scroll', 'pebble');
      cast(sim, p, Btn.skillE, pitch: 1.4);
      sim.applyDamage(p, 50, e, 'pistol', false); // 50 x 1.35 = 67.5 < 75 shield
      expect(p.hp, 200);
    });
    test('Shift lantern: can not die', () {
      final (sim, p, e) = duel('scroll', 'pebble');
      cast(sim, p, Btn.skillShift, seconds: 0.1);
      sim.applyDamage(p, 999, e, 'sniper', true);
      expect(p.alive, isTrue);
      expect(p.hp, closeTo(1, 0.01));
    });
    test('ult shields the whole team', () {
      final (sim, p, _) = duel('scroll', 'pebble');
      final ally = place(sim, sim.addPlayer('ally', 'boulder', teamId: 0), 20, 20);
      charge(p);
      cast(sim, p, Btn.ult);
      expect(ally.fx['shield'], 150);
    });
  });

  group('잉크웰', () {
    test('Q thrown smoke blinds enemies inside it', () {
      final (sim, p, e) = duel('inkwell', 'gem', dist: 8);
      cast(sim, p, Btn.skillQ, pitch: -0.05, seconds: 1.5);
      expect(sim.deployables.single.kind, 'ink_cloud');
      expect(sim.has(e, 'blind'), isTrue);
      expect(sim.has(p, 'blind'), isFalse, reason: 'allies are not blinded');
    });
    test('Q smoke blocks sight, 3 charges', () {
      final (sim, p, e) = duel('inkwell', 'gem', dist: 16);
      expect(sim.canSee(e, p.eye, fovCos: -1), isTrue);
      cast(sim, p, Btn.skillQ, pitch: -0.1, seconds: 1.5);
      expect(sim.canSee(e, p.eye, fovCos: -1), isFalse);
      expect(p.skillCharges[0], 2);
    });
    test('E puddle hurts 10 per second', () {
      final (sim, p, e) = duel('inkwell', 'gem', dist: 6);
      cast(sim, p, Btn.skillE, pitch: -0.3, seconds: 1);
      expect(sim.has(e, 'slow'), isTrue);
      final hp = e.hp;
      hold(sim, p, 1);
      // 10/s x controller role (skill power) x healer damage taken.
      final mul = p.character.stats.damageDealt * p.character.stats.skillPower * e.character.stats.damageTaken;
      expect(hp - e.hp, closeTo(10 * mul, 0.6));
    });
    test('E puddle slows', () {
      final (sim, p, e) = duel('inkwell', 'gem', dist: 6);
      cast(sim, p, Btn.skillE, pitch: -0.3, seconds: 1.5);
      expect(sim.has(e, 'slow'), isTrue);
    });
    test('Shift portal teleports to the aimed spot', () {
      final (sim, p, _) = duel('inkwell', 'gem', dist: 30);
      cast(sim, p, Btn.skillShift, pitch: -0.2);
      expect(p.pos.z, lessThan(5));
    });
    test('ult wall stops bullets but not movement', () {
      final (sim, p, e) = duel('inkwell', 'gem', dist: 10);
      e.pos.set(4, 0, 2);
      final ally = place(sim, sim.addPlayer('ally', 'boulder', teamId: 0), -4, 2);
      charge(p);
      cast(sim, p, Btn.ult); // wall runs straight ahead (-Z) through x = 0
      final hit = sim.traceShot(e, e.eye, (ally.eye - e.eye).normalized(), 50, -1);
      expect(hit.victim, isNull);
      expect(sim.mover.capsuleFree(0, 0.02, 0), isTrue, reason: 'walkable');
    });
  });

  group('퀘이크', () {
    test('Q turret shoots enemies', () {
      final (sim, p, e) = duel('quake', 'gem', dist: 10);
      cast(sim, p, Btn.skillQ, pitch: -0.6, seconds: 1.5);
      expect(e.hp, lessThan(200));
    });
    test('E trap roots whoever steps on it', () {
      final (sim, p, e) = duel('quake', 'gem', dist: 5);
      cast(sim, p, Btn.skillE, pitch: -0.5, seconds: 1.1);
      final t = sim.deployables.single;
      e.pos.set(t.pos.x, t.pos.y, t.pos.z);
      hold(sim, p, 0.1);
      expect(sim.has(e, 'root'), isTrue);
    });
    test('Shift overheat: faster fire rate', () {
      final (sim, p, _) = duel('quake', 'gem');
      cast(sim, p, Btn.skillShift);
      expect(sim.has(p, 'haste'), isTrue);
      expect(sim.moveMult(p), closeTo(1.25, 1e-9));
    });
    test('ult lava burns', () {
      final (sim, p, e) = duel('quake', 'gem', dist: 4);
      charge(p);
      cast(sim, p, Btn.ult, seconds: 1);
      expect(e.hp, lessThan(200 - 30));
    });
  });

  group('스테이플', () {
    test('Q sentry slows and shoots', () {
      final (sim, p, e) = duel('staple', 'gem', dist: 10);
      cast(sim, p, Btn.skillQ, pitch: -0.6, seconds: 1);
      expect(e.hp, lessThan(200));
      expect(sim.has(e, 'slow'), isTrue);
    });
    test('E snare roots and reveals', () {
      final (sim, p, e) = duel('staple', 'gem', dist: 5);
      cast(sim, p, Btn.skillE, pitch: -0.5, seconds: 1.1);
      final t = sim.deployables.single;
      e.pos.set(t.pos.x, t.pos.y, t.pos.z);
      hold(sim, p, 0.1);
      expect(sim.has(e, 'root'), isTrue);
      expect(e.revealed, greaterThan(0));
    });
    test('Shift alarm bot makes enemies take more damage', () {
      final (sim, p, e) = duel('staple', 'gem', dist: 6);
      cast(sim, p, Btn.skillShift, seconds: 2);
      expect(sim.has(e, 'vuln'), isTrue);
    });
    test('ult lockdown roots after the warm-up', () {
      final (sim, p, e) = duel('staple', 'gem', dist: 8);
      charge(p);
      cast(sim, p, Btn.ult, pitch: -0.5, seconds: 1);
      expect(sim.has(e, 'root'), isFalse);
      hold(sim, p, 3);
      expect(sim.has(e, 'root'), isTrue);
    });
  });
}
