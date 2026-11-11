import 'dart:io';

import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

import 'maps_test.dart' show assetBlocked, assets;

/// 5v5 bots, 3 minutes of game time at 30 Hz on every map.
void main() {
  for (final def in maps) {
    test('${def.id}: 5v5 bot match runs clean', skip: assetBlocked[def.id], () {
      final map = GameMap.fromGlb(def, File('$assets/${def.file}').readAsBytesSync());
      final sim = GameSim(map, cfg: const SimConfig(pregame: 3, timeLimit: 600), seed: 42)..fillBots();
      expect(sim.players.length, 10);
      final sw = Stopwatch()..start();
      var kills = 0, unstuck = 0, captures = 0, buys = 0;
      const dt = 1 / 30;
      for (var i = 0; i < 180 * 30 && sim.phase != Phase.ended; i++) {
        sim.update(dt);
        for (final e in sim.events) {
          switch (e['e']) {
            case 'kill':
              kills++;
            case 'unstuck':
              unstuck++;
            case 'captured':
              captures++;
            case 'buy':
              buys++;
          }
        }
        sim.events.clear();
        for (final p in sim.players.values) {
          expect(p.pos.x.isFinite && p.pos.y.isFinite && p.pos.z.isFinite, isTrue);
          if (p.alive) {
            expect(p.pos.x, inInclusiveRange(map.bounds[0] - 1, map.bounds[2] + 1));
            expect(p.pos.z, inInclusiveRange(map.bounds[1] - 1, map.bounds[3] + 1));
          }
        }
      }
      final ms = sw.elapsedMilliseconds;
      final ticks = sim.tick;
      printOnFailure('kills $kills captures $captures buys $buys unstuck $unstuck score ${sim.score}');
      print('${def.id}: ${(sim.time).toStringAsFixed(0)} s, kills $kills, captures $captures, buys $buys, '
          'unstuck $unstuck, score ${sim.score.map((s) => (s * 100).toStringAsFixed(0)).toList()}, '
          'winner ${sim.winner}, ${(ms / ticks).toStringAsFixed(2)} ms/tick');
      expect(kills, greaterThan(5));
      expect(captures, greaterThan(0));
      expect(buys, greaterThan(0));
      expect(unstuck, lessThan(10));
    });
  }
}
