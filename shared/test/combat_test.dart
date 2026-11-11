import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

const dt = 1 / 60;

/// Flat 60x60 arena: A spawn room at z 24..29, B at z -29..-24, point at 0,0.
GameSim arena({SimConfig cfg = const SimConfig(pregame: 0)}) {
  final map = GameMap.synthetic(
    [Obb.aabb('floor', Col.solid, -30, -1, -30, 30, 0, 30)],
    spawns: [
      [for (var x = -4.0; x <= 4; x += 2) SpawnPoint(Vec3(x, 0, 27), 0)],
      [for (var x = -4.0; x <= 4; x += 2) SpawnPoint(Vec3(x, 0, -27), 3.14159)],
    ],
    spawnRooms: [
      [-6, 24, 6, 29],
      [-6, -29, 6, -24],
    ],
    capture: Vec3(0, 0, 0),
    captureRadius: 4,
  );
  final sim = GameSim(map, cfg: cfg);
  sim.update(dt); // -> live
  return sim;
}

Player place(GameSim sim, Player p, double x, double z, {double yaw = 0}) {
  p.pos.set(x, 0, z);
  p.vel.set(0, 0, 0);
  p.yaw = yaw;
  p.onGround = true;
  p.spawnProtect = 0;
  p.drawTimer = 0;
  return p;
}

/// Aim [s] at [t]'s head (or chest) and send one input frame.
void shoot(GameSim sim, Player s, Player t, {bool head = true, int extra = 0}) {
  final y = head ? t.body.headCenter : t.body.hips + 0.3;
  final at = Vec3(t.pos.x, t.pos.y + y, t.pos.z);
  final inp = PlayerInput(dt: dt, yaw: yawTo(s.eye, at), pitch: pitchTo(s.eye, at), buttons: Btn.fire | extra);
  sim.processInput(s, inp);
  sim.processInput(s, PlayerInput(dt: dt, yaw: inp.yaw, pitch: inp.pitch, buttons: extra));
}

void main() {
  test('attack role hits harder (pistol headshot, attack vs healer)', () {
    final sim = arena();
    final s = place(sim, sim.addPlayer('atk', 'pebble', teamId: 0), 0, 10); // attack
    final v = place(sim, sim.addPlayer('heal', 'gem', teamId: 1), 0, 0); // healer
    shoot(sim, s, v);
    final pistol = gunById('pistol');
    expect(v.hp, closeTo(200 - pistol.stats.damage * 2 * 1.35 * 1.0, 0.01));
    expect(sim.events.any((e) => e['e'] == 'hit' && e['h'] == true), isTrue);
  });

  test('role profiles: tank armour, attacker fragility, healer damage', () {
    final sim = arena();
    final healer = place(sim, sim.addPlayer('h', 'needle', teamId: 0), 0, 10);
    final atk = place(sim, sim.addPlayer('a', 'snip', teamId: 1), 0, 0);
    shoot(sim, healer, atk, head: false); // healer 0.9 x attack takes 1.2
    expect(atk.hp, closeTo(175 - 24 * 0.9 * 1.2, 0.01));
    final sim2 = arena();
    final a2 = place(sim2, sim2.addPlayer('a', 'pebble', teamId: 0), 0, 10);
    final tank = place(sim2, sim2.addPlayer('t', 'boulder', teamId: 1), 0, 0);
    shoot(sim2, a2, tank, head: false); // attack 1.35 x defender takes 0.75
    expect(tank.hp, closeTo(300 - 24 * 1.35 * 0.75, 0.01));
    expect(roleStats[Role.controller]!.skillPower, greaterThan(1));
  });

  test('damage falls off with distance', () {
    final rifle = gunById('rifle');
    expect(rifle.damageAt(HitPart.body, 10), 24);
    expect(rifle.damageAt(HitPart.body, 50), closeTo(24 * (1 - 0.3 * 15 / 35), 1e-9));
    expect(rifle.damageAt(HitPart.body, 100), closeTo(24 * 0.7, 1e-9));
    expect(gunById('sniper').shotsToKill(300, HitPart.head, 80), 1, reason: 'sniper headshot kills a tank');
  });

  test('shotgun pellets add up up close', () {
    final sim = arena();
    final s = place(sim, sim.addPlayer('s', 'quake', teamId: 0), 0, 4)..credits = 9000;
    s.primary = 'shotgun';
    s.refillAmmo();
    s.slot = 0;
    final v = place(sim, sim.addPlayer('v', 'shear', teamId: 1), 0, 0); // controller beats defender
    shoot(sim, s, v, head: false);
    expect(300 - v.hp, greaterThan(60));
  });

  test('scoped sniper is pin-point, unscoped is not', () {
    final sniper = gunById('sniper');
    final sim = arena();
    final s = place(sim, sim.addPlayer('s', 'pebble', teamId: 0), 0, 23);  // just outside its spawn room
    s.primary = 'sniper';
    s.refillAmmo();
    s.slot = 0;
    final v = place(sim, sim.addPlayer('v', 'gem', teamId: 1), 0, -25)..spawnProtect = 0;
    // Hold ADS until fully zoomed.
    for (var i = 0; i < 30; i++) {
      sim.processInput(s, PlayerInput(dt: dt, yaw: 0, pitch: 0, buttons: Btn.ads));
    }
    expect(s.adsT, 1);
    expect(sim.spreadFor(s), 0);
    shoot(sim, s, v, extra: Btn.ads);
    expect(v.alive, isFalse, reason: 'headshot ${sniper.stats.damage * 2.5}');
    s.ads = false;
    s.adsT = 0;
    expect(sim.spreadFor(s), greaterThan(0.05));
  });

  test('rocket splash hurts the target and the shooter', () {
    final sim = arena();
    final s = place(sim, sim.addPlayer('s', 'pebble', teamId: 0), 0, 3)..credits = 9000;
    s.primary = 'launcher';
    s.refillAmmo();
    s.slot = 0;
    final v = place(sim, sim.addPlayer('v', 'boulder', teamId: 1), 1.5, 0);
    // Fire at the floor between them.
    final at = Vec3(0.6, 0, 1.2);
    sim.processInput(s, PlayerInput(dt: dt, yaw: yawTo(s.eye, at), pitch: pitchTo(s.eye, at), buttons: Btn.fire));
    for (var i = 0; i < 30; i++) {
      sim.update(dt);
    }
    expect(sim.events.any((e) => e['e'] == 'explode'), isTrue);
    expect(v.hp, lessThan(300));
    expect(s.hp, lessThan(200), reason: 'self damage');
  });

  test('kill: credits, kill event with fx, respawn, primary lost', () {
    final sim = arena();
    final s = place(sim, sim.addPlayer('s', 'pebble', teamId: 0), 0, 10);
    final v = place(sim, sim.addPlayer('v', 'gem', teamId: 1), 0, 0)
      ..primary = 'rifle'
      ..hp = 10;
    final c0 = s.credits;
    shoot(sim, s, v);
    expect(v.alive, isFalse);
    expect(s.kills, 1);
    expect(s.credits, c0 + Economy.kill);
    final kill = sim.events.lastWhere((e) => e['e'] == 'kill');
    expect(kill['badge'], 'kill_headshot');
    expect(['death_cat', 'death_dog'], contains(kill['fx']));
    expect(v.primary, isNull);
    for (var i = 0; i < (sim.cfg.respawnTime / dt).ceil() + 2; i++) {
      sim.update(dt);
    }
    expect(v.alive, isTrue);
    expect(v.hp, v.maxHp);
    expect(sim.map.inSpawnRoom(1, v.pos), isTrue);
  });

  test('armour: bought in spawn, soaks damage before HP, lost on death', () {
    final sim = arena();
    final p = sim.addPlayer('p', 'pebble', teamId: 0);
    final e = sim.addPlayer('e', 'pebble', teamId: 1);
    p.credits = 2000;
    expect(sim.buy(p, 'armor_heavy'), isNull);
    expect(p.armor, 100);
    expect(p.credits, 1000);
    expect(sim.buy(p, 'armor_light'), 'armor_full');
    place(sim, p, 0, 0);
    p.spawnProtect = 0;
    final mul = e.character.stats.damageDealt * p.character.stats.damageTaken;
    sim.applyDamage(p, 50 / mul, e, 'pistol', false);
    expect(p.armor, closeTo(50, 0.01));
    expect(p.hp, p.maxHp);
    sim.applyDamage(p, 80 / mul, e, 'pistol', false);
    expect(p.armor, 0);
    expect(p.hp, closeTo(p.maxHp - 30, 0.01));
    final row = Player.fromNet(p.toNet());
    expect(row.armor, 0);
    sim.applyDamage(p, 9999, e, 'pistol', false);
    expect(p.armor, 0);
  });

  test('buying the gun you hold refills its ammo at half price', () {
    final sim = arena();
    final p = sim.addPlayer('p', 'pebble', teamId: 0);
    expect(sim.buy(p, 'revolver'), isNull);
    expect(sim.buy(p, 'revolver'), isNotNull, reason: 'ammo already full');
    p.secMag = 1;
    p.secRes = 0;
    final c = p.credits;
    expect(sim.buy(p, 'revolver'), isNull);
    expect(p.credits, c - 250);
    expect(p.secMag, gunById('revolver').stats.mag);
    expect(p.secRes, gunById('revolver').stats.reserve);
  });

  test('shop only works in your own spawn room', () {
    final sim = arena();
    final p = sim.addPlayer('p', 'pebble', teamId: 0);
    expect(sim.map.inSpawnRoom(0, p.pos), isTrue);
    expect(sim.buy(p, 'sniper'), isNotNull, reason: 'not enough credits');
    expect(sim.buy(p, 'revolver'), isNull);
    expect(p.secondary, 'revolver');
    expect(p.credits, Economy.start - 500);
    p.credits = 5000;
    place(sim, p, 0, 0);
    expect(sim.buy(p, 'rifle'), isNotNull);
    p.pos.set(0, 0, 26);
    expect(sim.buy(p, 'rifle'), isNull);
    expect(p.primary, 'rifle');
    expect(p.slot, 0);
  });

  test('spawn protection and the enemy spawn room', () {
    final sim = arena();
    final s = place(sim, sim.addPlayer('s', 'pebble', teamId: 1), 0, 18);
    final v = sim.addPlayer('v', 'gem', teamId: 0); // in its spawn, protected
    expect(v.spawnProtect, greaterThan(0));
    shoot(sim, s, v, head: false);
    expect(v.hp, v.maxHp);
    // Walking into the enemy spawn hurts.
    place(sim, s, 0, 26);
    for (var i = 0; i < 30; i++) {
      sim.update(dt);
    }
    expect(s.hp, lessThan(s.maxHp));
  });

  test('spawn room: 5 s protection, fast healing, no shooting', () {
    final sim = arena();
    final p = sim.addPlayer('p', 'pebble', teamId: 0);
    final foe = place(sim, sim.addPlayer('f', 'gem', teamId: 1), 0, 15);
    expect(sim.map.inSpawnRoom(0, p.pos), isTrue);
    // Can't shoot from inside your own spawn.
    final shots = p.shotSeq;
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.fire));
    expect(p.shotSeq, shots);
    // Protected for 5 s while inside.
    for (var i = 0; i < 4 * 60; i++) {
      sim.update(dt);
    }
    sim.applyDamage(p, 150, foe, 'rifle', false);
    expect(p.hp, p.maxHp);
    // Heals quickly in the spawn room.
    for (var i = 0; i < 2 * 60; i++) {
      sim.update(dt);
    }
    p.hp = 50;
    for (var i = 0; i < 60; i++) {
      sim.update(dt);
    }
    expect(p.hp, greaterThan(100));
    // Protection ends after 5 s.
    sim.applyDamage(p, 30, foe, 'rifle', false);
    expect(p.hp, lessThan(p.maxHp));
    // Leaving the room you can shoot.
    place(sim, p, 0, 10);
    sim.processInput(p, PlayerInput(dt: dt)); // release the trigger first (semi-auto)
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.fire));
    expect(p.shotSeq, shots + 1);
  });

  test('no time limit by default; respawn takes 10 s', () {
    expect(const SimConfig().timeLimit, 0);
    expect(const SimConfig().respawnTime, 10);
  });

  test('falling below the kill height kills', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 0);
    p.pos.y = -6;
    sim.update(dt);
    expect(p.alive, isFalse);
  });

  test('reload blocks firing and cancels ADS', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'pebble', teamId: 0), 0, 0);
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.ads));
    expect(p.ads, isTrue);
    p.mag = 3;
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.ads | Btn.reload));
    expect(p.reloadTimer, greaterThan(0));
    expect(p.ads, isFalse);
    final shots = p.shotSeq;
    sim.processInput(p, PlayerInput(dt: dt, buttons: Btn.fire));
    expect(p.shotSeq, shots);
    for (var i = 0; i < 100; i++) {
      sim.processInput(p, PlayerInput(dt: dt));
    }
    expect(p.mag, gunById('pistol').stats.mag);
  });

  test('capture, score, contest and win', () {
    final sim = arena(cfg: const SimConfig(pregame: 0, captureTime: 4, holdToWin: 5));
    final a = place(sim, sim.addPlayer('a', 'pebble', teamId: 0), 0, 1);
    var t = 0.0;
    while (sim.owner != 0 && t < 10) {
      sim.update(dt);
      t += dt;
    }
    expect(sim.owner, 0);
    expect(t, closeTo(4, 0.1));
    final b = place(sim, sim.addPlayer('b', 'gem', teamId: 1), 0, -1);
    final s0 = sim.score[0];
    for (var i = 0; i < 60; i++) {
      sim.update(dt);
    }
    expect(sim.contested, isTrue);
    expect(sim.score[0], s0, reason: 'contested pauses scoring');
    b.pos.set(20, 0, -20);
    while (sim.phase != Phase.ended && t < 30) {
      sim.update(dt);
      t += dt;
    }
    expect(sim.winner, 0);
    expect(a.captureTime, greaterThan(4));
    expect(a.credits, greaterThan(Economy.start));
  });

  test('snapshot round trip', () {
    final sim = arena();
    final p = place(sim, sim.addPlayer('p', 'inkwell', teamId: 0), 3, 4)..primary = 'smg';
    sim.update(dt);
    final client = GameSim(sim.map, authoritative: false);
    client.applySnapshot(sim.snapshot());
    final q = client.players[p.id]!;
    expect(q.charId, 'inkwell');
    expect(q.primary, 'smg');
    expect(q.pos.x, closeTo(3, 1e-3));
  });
}
