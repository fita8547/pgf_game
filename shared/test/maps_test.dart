import 'dart:io';

import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

const assets = '../rps_assets';

/// Known asset problems that block traversal (reported, fix belongs in
/// rps_assets/src): neon_rooftops parapets have no openings at bridge ends,
/// barrier_n1/barrier_n-1 fill bridges 4/5 edge to edge, and bridge_6/7 cross
/// straight through bridge_4/5 with their handrails at 1.1 m.
/// Fixed in the 2026-11-11 asset update; keep the hook for future art issues.
const Map<String, String> assetBlocked = {};

GameMap load(MapDef d) => GameMap.fromGlb(d, File('$assets/${d.file}').readAsBytesSync());

void main() {
  for (final def in maps) {
    group(def.id, () {
      late GameMap map;
      late GameSim sim;
      setUpAll(() {
        map = load(def);
        sim = GameSim(map, cfg: const SimConfig(pregame: 0));
      });

      test('colliders, spawns and capture zone are sane', () {
        expect(map.world.statics.length, greaterThan(50));
        for (var t = 0; t < 2; t++) {
          expect(sim.spawnPoints[t].length, greaterThanOrEqualTo(5), reason: 'room for a 5-stack');
          for (final s in sim.spawnPoints[t]) {
            expect(sim.mover.capsuleFree(s.pos.x, s.pos.y + 0.01, s.pos.z), isTrue, reason: '${s.pos}');
            expect(map.inSpawnRoom(t, s.pos), isTrue);
          }
        }
        // A spawns at +Z, B at -Z (brief: A team z+, B team z-).
        expect(map.spawns[0].first.pos.z, greaterThan(0));
        expect(map.spawns[1].first.pos.z, lessThan(0));
        expect(map.killY, lessThan(map.capture.y));
      });

      test('nav graph connects both spawns to the capture point', skip: assetBlocked[def.id], () {
        final nav = sim.nav;
        expect(nav.length, greaterThan(500));
        expect(sim.captureNodes.length, greaterThan(10), reason: 'reachable area inside the zone');
        final goal = nav.node(sim.captureNodes[sim.captureNodes.length ~/ 2]);
        for (var t = 0; t < 2; t++) {
          final path = nav.path(map.spawns[t].first.pos, goal, team: t);
          expect(path, isNotEmpty, reason: 'team $t has no path to the point');
          expect(map.inCapture(path.last), isTrue, reason: 'path ends at ${path.last}');
        }
      });

      test('a lone bot from each team walks onto the point', skip: assetBlocked[def.id], () {
        for (var t = 0; t < 2; t++) {
          final s = GameSim(map, cfg: const SimConfig(pregame: 0, botSkill: 1));
          final bot = s.addPlayer('walker', 'pebble', teamId: t, bot: true);
          var reached = -1.0;
          for (var i = 0; i < 60 * 45 && reached < 0; i++) {
            s.update(1 / 60);
            if (map.inCapture(bot.pos)) reached = s.time;
          }
          final unstuck = s.events.where((e) => e['e'] == 'unstuck').length;
          expect(reached, greaterThan(0), reason: 'team $t stuck at ${bot.pos}');
          expect(unstuck, lessThanOrEqualTo(1));
          expect(bot.alive, isTrue);
        }
      });
    });
  }
}
