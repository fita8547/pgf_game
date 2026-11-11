part of 'game_controller.dart';

/// Dev-only console hooks (`?debug` in the URL).
extension _GameDebug on GameController {
  /// Dev only (`?debug`): window.rpsDebug.die() / money(n) / tp(x,y,z) / hp(v) / look(yaw,pitch) /
  /// score(team, 0..1) / state().
  void _debugHooks() {
    final o = JSObject();
    o['die'] = (() => sim!.applyDamage(me!, 9999, null, 'debug', false)).toJS;
    o['money'] = ((JSNumber n) => me!.credits += n.toDartInt).toJS;
    o['hp'] = ((JSNumber v) => me!.hp = v.toDartDouble).toJS;
    o['tp'] = ((JSNumber x, JSNumber y, JSNumber z) {
      me!.pos.set(x.toDartDouble, y.toDartDouble, z.toDartDouble);
      me!.vel.set(0, 0, 0);
    }).toJS;
    o['score'] = ((JSNumber t, JSNumber v) {
      final s = sim!;
      s.score[t.toDartInt] = v.toDartDouble;
      s.owner = t.toDartInt;
    }).toJS;
    o['ult'] = (() => me!.ult = me!.character.stats.ultCost).toJS;
    o['look'] = ((JSNumber y, JSNumber p) {
      yaw = y.toDartDouble;
      pitch = p.toDartDouble;
    }).toJS;
    o['state'] = (() => '${me!.pos} hp=${me!.hp} alive=${me!.alive} gun=${me!.gunId} cr=${me!.credits} '
            'owner=${sim!.owner} score=${sim!.score} t=${sim!.time.toStringAsFixed(1)}'
        .toJS).toJS;
    // Aim at the nearest living enemy in line of sight (for recorded demos).
    // Returns its distance, or -1 if none is visible.
    o['aimNearest'] = (() {
      final s = sim!, p = me!;
      Player? best;
      var bd = 1e9;
      for (final q in s.players.values) {
        if (q.team == p.team || !q.alive) continue;
        final d = q.pos.distanceTo(p.pos);
        if (d < bd && s.map.world.lineClear(p.eye, q.eye)) {
          bd = d;
          best = q;
        }
      }
      if (best == null) return (-1).toJS;
      final dx = best.pos.x - p.pos.x, dz = best.pos.z - p.pos.z;
      final dy = best.pos.y + best.eyeHeight * 0.8 - p.eye.y;
      yaw = math.atan2(dx, -dz);
      pitch = math.atan2(dy, math.sqrt(dx * dx + dz * dz));
      return bd.toJS;
    }).toJS;
    o['me'] = (() => [me!.pos.x, me!.pos.y, me!.pos.z, yaw, me!.alive ? 1 : 0, me!.mag].jsify()).toJS;
    globalContext['rpsDebug'] = o;
  }
}
