import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

const dt = 1 / 60;

/// 40 x 40 m floor at y=0 plus [extra] boxes.
CollisionWorld world(List<Obb> extra) =>
    CollisionWorld([Obb.aabb('floor', Col.solid, -20, -1, -20, 20, 0, 20), ...extra]);

Player player(double x, double y, double z, {double yaw = 0}) => Player(1, 'p', 0, 'pebble')
  ..pos.set(x, y, z)
  ..yaw = yaw
  ..alive = true
  ..onGround = true;

/// Runs [seconds] of input; forward (-Z at yaw 0) unless overridden.
void run(Mover m, Player p, double seconds,
    {double moveZ = 1, double moveX = 0, int buttons = 0, int Function(int frame)? press, double speed = 5.5}) {
  final frames = (seconds / dt).round();
  for (var i = 0; i < frames; i++) {
    final b = buttons | (press?.call(i) ?? 0);
    final inp = PlayerInput(dt: dt, moveX: moveX, moveZ: moveZ, yaw: p.yaw, buttons: b);
    final pressed = b & ~p.prevButtons;
    p.prevButtons = b;
    m.move(p, inp, pressed, dt, speed: speed);
  }
}

void main() {
  test('walks on flat ground at run speed and stays on the floor', () {
    final m = Mover(world([]));
    final p = player(0, 0, 0);
    run(m, p, 1);
    expect(p.pos.z, inInclusiveRange(-5.6, -4.9));
    expect(p.pos.y, closeTo(0, 0.02));
    expect(p.onGround, isTrue);
  });

  test('walls block and do not let the player through', () {
    final m = Mover(world([Obb.aabb('wall', Col.solid, -5, 0, -3.25, 5, 3, -2.75)]));
    final p = player(0, 0, 0);
    run(m, p, 2);
    expect(p.pos.z, greaterThan(-2.75 + playerRadius - 0.02));
  });

  test('thin wall cannot be tunnelled at dash speed', () {
    final m = Mover(world([Obb.aabb('thin', Col.solid, -5, 0, -3.05, 5, 3, -2.95)]));
    final p = player(0, 0, 0);
    run(m, p, 1, speed: 40);
    expect(p.pos.z, greaterThan(-2.95));
  });

  test('auto step-up on low ledges, blocked by tall ones', () {
    final m = Mover(world([
      Obb.aabb('step', Col.solid, -1, 0, -9, 1, 0.35, -2),
      Obb.aabb('crate', Col.solid, 3, 0, -9, 5, 0.9, -2),
    ]));
    final a = player(0, 0, 0);
    run(m, a, 0.6);
    expect(a.pos.y, closeTo(0.35, 0.03), reason: 'climbed the 0.35 m step');
    final b = player(4, 0, 0);
    run(m, b, 1);
    expect(b.pos.y, closeTo(0, 0.02), reason: '0.9 m crate needs a jump');
    expect(b.pos.z, greaterThan(-2 + playerRadius - 0.05));
  });

  test('jumping onto a 1 m crate works', () {
    final m = Mover(world([Obb.aabb('crate', Col.solid, -1, 0, -9, 1, 1.0, -2)]));
    final p = player(0, 0, -0.6);
    run(m, p, 1, press: (f) => f == 6 ? Btn.jump : 0);
    expect(p.pos.y, closeTo(1.0, 0.05));
  });

  test('walks up and down a 30 degree ramp without sliding', () {
    // Ramp along -Z rising 2 m over ~3.46 m.
    const ang = 30 * math.pi / 180;
    final len = 2 / math.sin(ang);
    final ux = 0.0, uy = math.sin(ang), uz = -math.cos(ang);
    final vy = math.cos(ang), vz = math.sin(ang);
    final cx = 0.0, cy = 1.0 - vy * 0.15, cz = -2 - math.cos(ang) * len / 2 - vz * 0.15;
    final ramp =
        Obb('ramp', Col.solid, cx, cy, cz, len / 2, 0.15, 1.5, Float64List.fromList([ux, uy, uz, 0, vy, vz, 1, 0, 0]));
    final top = Obb.aabb('top', Col.solid, -1.5, 0, -12, 1.5, 2, -2 - math.cos(ang) * len);
    final m = Mover(world([ramp, top]));
    final p = player(0, 0, 0);
    run(m, p, 2.2);
    expect(p.pos.y, closeTo(2, 0.05), reason: 'reached the top platform');
    // Standing still half way down must not slide.
    final q = player(0, 1.0, -2 - math.cos(ang) * len / 2);
    run(m, q, 0.2, moveZ: 0);
    final z0 = q.pos.z;
    run(m, q, 1, moveZ: 0);
    expect((q.pos.z - z0).abs(), lessThan(0.02));
    expect(q.onGround, isTrue);
  });

  test('anti bunny-hop: chained hops lose speed', () {
    final m = Mover(world([]));
    final p = player(0, 0, 15);
    run(m, p, 0.5);
    final speeds = <double>[];
    for (var hop = 0; hop < 4; hop++) {
      // Jump on the first frame we are grounded (frame-perfect bhop).
      var jumped = false;
      for (var f = 0; f < 120; f++) {
        final b = (!jumped && p.onGround) ? Btn.jump : 0;
        if (b != 0) jumped = true;
        final inp = PlayerInput(dt: dt, moveZ: 1, yaw: 0, buttons: b);
        final pressed = b & ~p.prevButtons;
        p.prevButtons = b;
        m.move(p, inp, pressed, dt, speed: 5.5);
        if (jumped && !p.onGround) {
          speeds.add(p.vel.lengthXZ);
          break;
        }
      }
      for (var f = 0; f < 120 && !p.onGround; f++) {
        final inp = PlayerInput(dt: dt, moveZ: 1, yaw: 0);
        p.prevButtons = 0;
        m.move(p, inp, 0, dt, speed: 5.5);
      }
    }
    expect(speeds.length, 4);
    expect(speeds[1], lessThan(speeds[0] * 0.85));
    expect(speeds[3], lessThan(speeds[0] * 0.6));
    expect(speeds.every((s) => s <= 5.5 * 1.03), isTrue);
  });

  test('holding jump does not auto-hop', () {
    final m = Mover(world([]));
    final p = player(0, 0, 0);
    var jumps = 0;
    var wasGround = true;
    for (var f = 0; f < 180; f++) {
      final inp = PlayerInput(dt: dt, yaw: 0, buttons: Btn.jump);
      final pressed = Btn.jump & ~p.prevButtons;
      p.prevButtons = Btn.jump;
      m.move(p, inp, pressed, dt, speed: 5.5);
      if (wasGround && !p.onGround) jumps++;
      wasGround = p.onGround;
    }
    expect(jumps, 1);
  });

  test('cannot stand up under a low ceiling', () {
    final m = Mover(world([Obb.aabb('ceil', Col.solid, -3, 1.4, -3, 3, 1.6, 3)]));
    final p = player(0, 0, 0)..crouch = true;
    run(m, p, 0.3, moveZ: 0);
    expect(p.crouch, isTrue);
    final q = player(0, 0, 8)..crouch = true;
    run(m, q, 0.3, moveZ: 0);
    expect(q.crouch, isFalse);
  });

  test('a player inside a box is pushed out or flagged stuck', () {
    final m = Mover(world([Obb.aabb('pillar', Col.solid, -0.3, 0, -0.3, 0.3, 3, 0.3)]));
    final p = player(0.1, 0, 0);
    run(m, p, 0.2, moveZ: 0);
    expect(m.overlaps(p), isFalse);
  });
}
