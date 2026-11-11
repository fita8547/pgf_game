// Diagnostic: prints selected meshes of a map with world bounds.
// dart run tool/scan_detail.dart <map.glb> <regex>
import 'glb.dart';

void main(List<String> args) {
  final g = readGlb(args[0]);
  final re = RegExp(args[1]);
  String f(List<double> v) => v.map((e) => e.toStringAsFixed(2)).join(',');
  g.walk((i, node, w, path) {
    final name = node['name'] as String? ?? '';
    if (!re.hasMatch(path.join('/'))) return;
    if (node['mesh'] == null) {
      print('  [node] ${path.join('/')} t=${f(w.translation)}');
      return;
    }
    final (mn, mx, mat) = g.meshBounds(node['mesh'] as int)!;
    final (a, b) = w.transformBox(mn, mx);
    print(
        '  $name  [${f(a)}]..[${f(b)}]  ${w.axisAligned ? '' : 'ROT yaw=${(w.yaw * 57.3).toStringAsFixed(0)}'}  $mat');
  });
}
