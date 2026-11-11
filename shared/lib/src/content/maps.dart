/// Map table. Geometry, spawns and colliders come from the GLB at load time
/// (see GameMap); this only holds game rules the art can't express.
class MapDef {
  final String id;
  final String name;

  /// Path relative to rps_assets/.
  final String file;

  /// Capture zone centre (x, z); height is found by probing the GLB.
  final (double, double) capture;
  final double captureRadius;

  /// Floor height the zone is measured from; null = probe the GLB at the
  /// centre. Needed where the centre is a prop (ziggurat relic, shrine).
  final double? captureY;

  /// Falling below this height kills (null = lowest collider - 2 m).
  final double? killY;

  const MapDef({
    required this.id,
    required this.name,
    required this.file,
    this.capture = (0, 0),
    this.captureRadius = 5,
    this.captureY,
    this.killY,
  });
}

const List<MapDef> maps = [
  MapDef(id: 'rps_arena', name: 'RPS 아레나', file: 'glb/maps/rps_arena.glb', captureRadius: 5.5),
  MapDef(id: 'desert_ruins', name: '사막 유적', file: 'glb/maps/desert_ruins.glb', captureRadius: 5.5, captureY: 3.6),
  MapDef(id: 'frost_harbor', name: '설원 항구', file: 'glb/maps/frost_harbor.glb', captureRadius: 5.5),
  MapDef(id: 'neon_rooftops', name: '네온 옥상', file: 'glb/maps/neon_rooftops.glb', captureRadius: 5, killY: -6),
  MapDef(id: 'jungle_temple', name: '정글 사원', file: 'glb/maps/jungle_temple.glb', captureRadius: 4.5, captureY: 5.0),
];

MapDef mapById(String id) => maps.firstWhere((m) => m.id == id, orElse: () => maps.first);
