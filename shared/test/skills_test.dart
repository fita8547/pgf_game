import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

import 'combat_test.dart' show arena, dt, place;

void press(GameSim sim, Player p, int btn, {double moveZ = 0, double yaw = 0, double pitch = 0}) {
  sim.processInput(p, PlayerInput(dt: dt, buttons: btn, moveZ: moveZ, yaw: yaw, pitch: pitch));
  sim.processInput(p, PlayerInput(dt: dt, moveZ: moveZ, yaw: yaw, pitch: pitch));
}

void run(GameSim sim, double seconds) {
  for (var i = 0; i < (seconds / dt).round(); i++) {
    sim.update(dt);
  }
}

void main() {
  test('blink: ~7 m forward, 3 charges, 3 s recharge each', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    press(sim, p, Btn.skillQ);
    expect(p.pos.z, closeTo(10 - GravelBlink.range, 0.3));
    expect(p.skillCharges[0], 2);
    press(sim, p, Btn.skillQ);
    press(sim, p, Btn.skillQ);
    expect(p.skillCharges[0], 0);
    final z = p.pos.z;
    press(sim, p, Btn.skillQ);
    expect(p.pos.z, z, reason: 'no charges left');
    run(sim, 3.1);
    expect(p.skillCharges[0], 1);
  });

  test('blink stops at walls', () {
    final map = GameMap.synthetic([
      Obb.aabb('floor', Col.solid, -30, -1, -30, 30, 0, 30),
      Obb.aabb('wall', Col.solid, -10, 0, 6.9, 10, 4, 7.1),
    ], spawns: [
      [SpawnPoint(Vec3(0, 0, 20), 0)],
      [SpawnPoint(Vec3(0, 0, -20), 3.14)],
    ], spawnRooms: [
      [-3, 18, 3, 22],
      [-3, -22, 3, -18],
    ]);
    final sim = GameSim(map, cfg: const SimConfig(pregame: 0))..update(dt);
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    press(sim, p, Btn.skillQ);
    expect(p.pos.z, greaterThan(7.1 + playerRadius - 0.01));
    expect(p.pos.z, lessThan(8));
  });

  test('blink is predicted on the client (no server needed)', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.skillQ), predict: true);
    expect(p.pos.z, lessThan(4));
  });

  test('rewind returns to the position and HP of 3 s ago', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    run(sim, 0.5);
    for (var i = 0; i < 180; i++) {
      sim.processInput(p, PlayerInput(dt: dt, moveZ: 1));
      sim.update(dt);
    }
    p.hp = 40;
    press(sim, p, Btn.skillE);
    expect(p.pos.z, greaterThan(8), reason: 'back near the start, not at ${p.pos}');
    expect(p.hp, p.maxHp);
    expect(p.skillCd[1], closeTo(12, 0.1));
  });

  test('recon pebble reveals enemies near the impact', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    final near = place(sim, sim.addPlayer('e1', 'gem', teamId: 1), 2, -2);
    final far = place(sim, sim.addPlayer('e2', 'gem', teamId: 1), 0, -25);
    // Throw at the floor a few metres ahead.
    press(sim, p, Btn.skillShift, pitch: -0.5);
    run(sim, 2);
    expect(sim.events.any((e) => e['e'] == 'reveal'), isTrue);
    expect(near.revealed, greaterThan(0));
    expect(far.revealed, 0);
  });

  test('sticky charge needs ult, sticks, explodes', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    final v = place(sim, sim.addPlayer('v', 'shear', teamId: 1), 0, 2);
    press(sim, p, Btn.ult, pitch: -0.12);
    expect(sim.projectiles, isEmpty, reason: 'ult not charged');
    p.ult = p.character.stats.ultCost;
    press(sim, p, Btn.ult, pitch: -0.12);
    expect(sim.projectiles.length, 1);
    expect(p.ult, 0);
    run(sim, 0.6);
    expect(sim.projectiles.single.stuck, isTrue);
    run(sim, 1.5);
    expect(sim.projectiles, isEmpty);
    expect(v.hp, lessThan(300 - 100));
  });

  test('skill state survives the wire', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 10);
    press(sim, p, Btn.skillQ);
    final q = Player.fromNet(p.toNet());
    expect(q.skillCharges, p.skillCharges);
    expect(q.skillCd[0], closeTo(p.skillCd[0], 0.01));
  });

  test('rock turret disappears when quake dies; origami hits harder', () {
    final sim = arena();
    final q = place(sim, sim.addPlayer('q', 'quake', teamId: 0), 0, 10);
    final e = place(sim, sim.addPlayer('e', 'origami', teamId: 1), 3, -10);
    press(sim, q, Btn.skillQ);
    expect(sim.deployablesOf(q, 'rock_turret'), isNotEmpty);
    q.spawnProtect = 0;
    final hp = q.hp;
    sim.applyDamage(q, 10, e, 'pistol', false);
    final taken = hp - q.hp;
    expect(taken, closeTo(10 * 1.35 * 1.5 * q.character.stats.damageTaken, 0.01));
    sim.applyDamage(q, 9999, e, 'pistol', false);
    expect(q.alive, isFalse);
    expect(sim.deployablesOf(q, 'rock_turret'), isEmpty);
  });
}
