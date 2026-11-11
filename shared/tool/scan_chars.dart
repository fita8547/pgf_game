// Diagnostic: prints bone world positions for every character GLB.
// dart run tool/scan_chars.dart ../rps_assets/glb/characters
import 'dart:io';

import 'glb.dart';

void main(List<String> args) {
  final files = Directory(args[0]).listSync().whereType<File>().where((f) => f.path.endsWith('.glb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  const bones = ['hips', 'chest', 'neck', 'head', 'upper_arm_L', 'thigh_L', 'foot_L'];
  for (final f in files) {
    final g = readGlb(f.path);
    final pos = <String, List<double>>{};
    var top = 0.0;
    g.walk((i, node, w, path) {
      final n = node['name'] as String? ?? '';
      if (bones.contains(n)) pos[n] = w.translation;
      if (node['mesh'] != null) {
        final (mn, mx, _) = g.meshBounds(node['mesh'] as int)!;
        final (_, b) = w.transformBox(mn, mx);
        if (b[1] > top) top = b[1];
      }
    });
    String v(String k) => pos[k] == null ? '-' : pos[k]!.map((e) => e.toStringAsFixed(2)).join(',');
    print('${f.uri.pathSegments.last.padRight(14)} top=${top.toStringAsFixed(2)} '
        '${bones.map((b) => '$b=${v(b)}').join(' ')}');
  }
}
