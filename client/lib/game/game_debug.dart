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
    globalContext['rpsDebug'] = o;
  }
}
