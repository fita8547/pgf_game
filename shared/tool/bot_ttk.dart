// Balance probe: how long a lone bot needs to kill a standing, visible target
// at a given distance, per bot skill. dart run tool/bot_ttk.dart
import 'package:rps_shared/rps_shared.dart';

void main() {
  for (final skill in [0.0, 0.25, 0.5, 0.75, 1.0]) {
    for (final dist in [10.0, 25.0]) {
      final times = <double>[];
      for (var seed = 1; seed <= 12; seed++) {
        final map = GameMap.synthetic([Obb.aabb('floor', Col.solid, -40, -1, -40, 40, 0, 40)], spawns: [
          [SpawnPoint(Vec3(0, 0, 30), 0)],
          [SpawnPoint(Vec3(0, 0, -30), 3.14)],
        ], spawnRooms: [
          [-2, 38, 2, 39],
          [-2, -39, 2, -38],
        ]);
        final sim = GameSim(map, cfg: SimConfig(pregame: 0, botSkill: skill), seed: seed)..update(1 / 60);
        final target = sim.addPlayer('dummy', 'pebble', teamId: 0)
          ..pos.set(0, 0, 0)
          ..spawnProtect = 0;
        final bot = sim.addPlayer('bot', 'pebble', teamId: 1, bot: true)
          ..pos.set(3, 0, -dist)
          ..yaw = 3.14159 - 0.35 // roughly toward the target (not exact)
          ..spawnProtect = 0;
        var t = 0.0;
        while (target.alive && t < 20) {
          sim.processInput(target, PlayerInput(dt: 1 / 60));
          sim.update(1 / 60);
          bot.pos.z = -dist; // keep the distance fixed
          bot.pos.x = 3;
          t += 1 / 60;
        }
        times.add(t);
      }
      times.sort();
      print('skill ${skill.toStringAsFixed(2)} dist ${dist.toInt()}m: median ${times[6].toStringAsFixed(2)}s  '
          'fastest ${times.first.toStringAsFixed(2)}s');
    }
  }
}
