// Diagnostic: summarizes map GLBs (groups, name kinds, rotated parts).
// dart run tool/scan_maps.dart ../rps_assets/glb/maps
import 'dart:io';

import 'glb.dart';

void main(List<String> args) {
  final files = Directory(args[0]).listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final g = readGlb(f.path);
    var n = 0, rot = 0;
    final bigRot = <String>[];
    final kinds = <String, int>{};
    final groups = <String, int>{};
    final special = <String>{};
    final mats = <String>{};
    final lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
    g.walk((i, node, w, path) {
      if (node['mesh'] == null) return;
      final (mn, mx, mat) = g.meshBounds(node['mesh'] as int)!;
      final (a, b) = w.transformBox(mn, mx);
      for (var k = 0; k < 3; k++) {
        if (a[k] < lo[k]) lo[k] = a[k];
        if (b[k] > hi[k]) hi[k] = b[k];
      }
      n++;
      mats.add(mat.replaceAll(RegExp(r'#[0-9a-f]{6}'), ''));
      final name = node['name'] as String? ?? '';
      final grp = path.length > 1 ? path[1] : '?';
      groups[grp] = (groups[grp] ?? 0) + 1;
      final kind = name.split('_').first.replaceAll(RegExp(r'\d'), '');
      kinds[kind] = (kinds[kind] ?? 0) + 1;
      if (!w.axisAligned) {
        rot++;
        final sx = b[0] - a[0], sy = b[1] - a[1], sz = b[2] - a[2];
        if ((sx > 2.5 || sz > 2.5) && sy > 0.3) {
          bigRot.add(
              '$name(${sx.toStringAsFixed(1)}x${sy.toStringAsFixed(1)}x${sz.toStringAsFixed(1)} y${a[1].toStringAsFixed(1)})');
        }
      }
      if (RegExp(r'ramp|stair|step|slope|water|river|point|capture|zone|smoke|leaf|tree|vine|glass|bridge|cap|obj')
          .hasMatch(name)) {
        special.add(name.replaceAll(RegExp(r'_?\d+$'), ''));
      }
    });
    String f1(double v) => v.toStringAsFixed(1);
    print(
        '== ${f.uri.pathSegments.last}: meshes $n, bounds ${lo.map(f1).toList()}..${hi.map(f1).toList()}, rotated $rot');
    print('  groups $groups');
    print('  mats $mats');
    print('  big rotated (${bigRot.length}): ${bigRot.take(16).join(', ')}');
    final ks = kinds.entries.toList()..sort((a, b) => b.value - a.value);
    print('  kinds ${ks.take(50).map((e) => '${e.key}:${e.value}').join(' ')}');
    print('  special ${special.take(40).join(' ')}');
  }
}
