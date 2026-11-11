// Diagnostic: builds GameMap colliders for every map and prints a summary
// (counts, spawns, capture height, kill height, skipped names).
// dart run tool/scan_colliders.dart ../rps_assets [mapId] [-v]
import 'dart:io';

import 'package:rps_shared/rps_shared.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '../rps_assets' : args[0];
  final only = args.length > 1 && !args[1].startsWith('-') ? args[1] : null;
  final verbose = args.contains('-v');
  for (final def in maps) {
    if (only != null && def.id != only) continue;
    final m = GameMap.fromGlb(def, File('$root/${def.file}').readAsBytesSync());
    String f(double v) => v.toStringAsFixed(2);
    final rotated = m.world.statics.where((b) => !b.aligned).length;
    print('== ${def.id}: colliders ${m.world.statics.length} (rotated $rotated), skipped ${m.skipped.length}, '
        'bounds ${m.bounds.map(f).toList()}, killY ${f(m.killY)}');
    print('  capture ${m.capture} r=${m.captureRadius}');
    for (var t = 0; t < 2; t++) {
      print('  spawns[$t] ${m.spawns[t].map((s) => s.pos).join(' ')} room ${m.spawnRooms[t].map(f).toList()}');
    }
    final names = <String, int>{};
    for (final s in m.skipped) {
      final k = s.replaceAll(RegExp(r'[_\-]?[\d.\-]+(?=$|_|\()'), '');
      names[k] = (names[k] ?? 0) + 1;
    }
    print('  skipped: ${names.entries.map((e) => '${e.key}:${e.value}').join(' ')}');
    if (verbose) {
      for (final b in m.world.statics) {
        print('    ${b.name} [${f(b.minX)},${f(b.minY)},${f(b.minZ)}]..[${f(b.maxX)},${f(b.maxY)},${f(b.maxZ)}]'
            '${b.aligned ? '' : ' OBB'}');
      }
    }
  }
}
