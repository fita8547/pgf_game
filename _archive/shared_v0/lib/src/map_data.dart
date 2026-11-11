import 'math.dart';
import 'nav.dart';

/// Visual/physical material of a map box. The renderer maps these to colors.
enum MatKind { floor, wall, wallAlt, crate, metal, accentA, accentB, trim, barrier }

class MapBox {
  final Aabb box;
  final MatKind mat;

  /// Non-solid boxes are decals (site plates etc.): drawn, never collided.
  final bool solid;
  const MapBox(this.box, this.mat, {this.solid = true});
}

class Site {
  final String name;
  final Vec3 center;
  final double radius;
  const Site(this.name, this.center, this.radius);
  bool contains(Vec3 p) => p.distanceXZ(center) <= radius;
}

/// A defensive hold position and where to look from it.
class HoldSpot {
  final Vec3 pos;
  final Vec3 lookAt;
  const HoldSpot(this.pos, this.lookAt);
}

class GameMap {
  final String id;
  final String name;
  final List<MapBox> boxes;
  final Aabb bounds;

  /// Spawns for the attacking and defending side.
  final List<Vec3> attackSpawns;
  final List<Vec3> defenseSpawns;
  final List<Site> sites;

  /// Defender holds: [siteIndex] -> spots; index sites.length is mid.
  final List<List<HoldSpot>> holds;
  late final List<MapBox> solids = boxes.where((b) => b.solid).toList();
  late final NavGrid nav = NavGrid.build(this);

  GameMap({
    required this.id,
    required this.name,
    required this.boxes,
    required this.bounds,
    required this.attackSpawns,
    required this.defenseSpawns,
    required this.sites,
    required this.holds,
  });

  Site? siteAt(Vec3 p) {
    for (final s in sites) {
      if (s.contains(p)) return s;
    }
    return null;
  }
}

MapBox _b(double x0, double y0, double z0, double x1, double y1, double z1, MatKind m,
        {bool solid = true}) =>
    MapBox(Aabb(x0, y0, z0, x1, y1, z1), m, solid: solid);

/// "Dunewall": an original three-lane desert compound with two plant sites.
///
///   north (-Z): defender spawn, A site (west) and B site (east)
///   south (+Z): attacker spawn
GameMap buildDunewall() {
  const h = 7.0; // outer wall height
  const w = 5.5; // inner wall height
  final boxes = <MapBox>[
    // Ground
    _b(-40, -1, -32, 40, 0, 32, MatKind.floor),
    // Outer walls
    _b(-41, 0, -33, 41, h, -32, MatKind.wall),
    _b(-41, 0, 32, 41, h, 33, MatKind.wall),
    _b(-41, 0, -32, -40, h, 32, MatKind.wall),
    _b(40, 0, -32, 41, h, 32, MatKind.wall),

    // West divider (A side | mid): openings z[-18,-12] (A short), z[6,10] (A link)
    _b(-14, 0, -32, -12, w, -18, MatKind.wallAlt),
    _b(-14, 0, -12, -12, w, 6, MatKind.wallAlt),
    _b(-14, 0, 10, -12, w, 22, MatKind.wallAlt),
    // East divider (mid | B side): openings z[-16,-10] (B short), z[-2,2] (B link)
    _b(12, 0, -32, 14, w, -16, MatKind.wallAlt),
    _b(12, 0, -10, 14, w, -2, MatKind.wallAlt),
    _b(12, 0, 2, 14, w, 22, MatKind.wallAlt),

    // A main choke into the site (opening x[-30,-22])
    _b(-40, 0, -8, -30, w, -6, MatKind.wall),
    _b(-22, 0, -8, -14, w, -6, MatKind.wall),
    // B main choke (opening x[22,30])
    _b(14, 0, -8, 22, w, -6, MatKind.wall),
    _b(30, 0, -8, 40, w, -6, MatKind.wall),

    // ---- A site ----
    _b(-31, 0, -23, -23, 0.03, -15, MatKind.accentA, solid: false),
    _b(-30, 0, -22, -27, 2.2, -19, MatKind.crate),
    _b(-27, 0, -22, -25.5, 1.1, -20.5, MatKind.crate),
    _b(-36, 0, -16, -34, 4, -12, MatKind.wallAlt),
    _b(-22, 0, -26, -18, 1.2, -25, MatKind.metal),
    _b(-20, 0, -14, -18, 2, -12, MatKind.crate),
    _b(-38, 0, -30, -34, 3, -27, MatKind.metal),

    // ---- B site ----
    _b(23, 0, -23, 31, 0.03, -15, MatKind.accentB, solid: false),
    _b(24, 0, -24, 27, 2.5, -21, MatKind.crate),
    _b(27, 0, -24, 28.5, 1.2, -22.5, MatKind.crate),
    _b(33, 0, -28, 35, 3.5, -25, MatKind.wallAlt),
    _b(20, 0, -16, 24, 1.2, -15, MatKind.metal),
    _b(34, 0, -14, 36, 2, -12, MatKind.crate),
    _b(16, 0, -30, 19, 2.4, -27, MatKind.metal),

    // ---- Mid ----
    _b(-3, 0, 2, 3, 2.5, 6, MatKind.metal),
    _b(-8, 0, -12, -5, 1.4, -9, MatKind.crate),
    _b(5, 0, -16, 8, 2.2, -13, MatKind.crate),
    _b(-4, 0, 14, 4, 1.2, 15, MatKind.wallAlt),
    _b(-2, 0, -22, 2, 4.5, -20, MatKind.wall),
    _b(-11, 0, -4, -9, 1.2, -2, MatKind.crate),
    _b(9, 0, 8, 11, 1.8, 10, MatKind.crate),

    // ---- A main ----
    _b(-34, 0, 4, -24, 4.5, 14, MatKind.wall),
    _b(-34, 4.5, 4, -24, 4.8, 14, MatKind.trim),
    _b(-20, 0, 16, -18, 1.2, 18, MatKind.crate),
    _b(-38, 0, -2, -36, 2, 0, MatKind.crate),
    _b(-20, 0, -2, -17, 2.2, 1, MatKind.crate),

    // ---- B main ----
    _b(24, 0, -2, 32, 4.5, 8, MatKind.wall),
    _b(24, 4.5, -2, 32, 4.8, 8, MatKind.trim),
    _b(36, 0, 12, 38, 2, 14, MatKind.crate),
    _b(18, 0, 14, 20, 1.2, 16, MatKind.crate),
    _b(34, 0, 0, 37, 1.3, 2, MatKind.metal),

    // ---- South band / attacker spawn ----
    _b(-20, 0, 26, -17, 2, 28, MatKind.crate),
    _b(16, 0, 25, 19, 2, 27, MatKind.crate),
    _b(-30, 0, 24, -26, 3, 32, MatKind.wallAlt),
    _b(26, 0, 24, 30, 3, 32, MatKind.wallAlt),
    _b(-8, 0, 30, 8, 0.03, 31.5, MatKind.trim, solid: false),
    _b(-8, 0, -31.5, 8, 0.03, -30, MatKind.trim, solid: false),
  ];

  final siteA = Site('A', Vec3(-27, 0, -19), 6.5);
  final siteB = Site('B', Vec3(27, 0, -19), 6.5);

  return GameMap(
    id: 'dunewall',
    name: 'Dunewall',
    boxes: boxes,
    bounds: Aabb(-40, 0, -32, 40, 10, 32),
    attackSpawns: [for (final x in [-6.0, -3.0, 0.0, 3.0, 6.0]) Vec3(x, 0, 28)],
    defenseSpawns: [for (final x in [-6.0, -3.0, 0.0, 3.0, 6.0]) Vec3(x, 0, -27)],
    sites: [siteA, siteB],
    holds: [
      [
        HoldSpot(Vec3(-33, 0, -24), Vec3(-26, 1.5, -7)),
        HoldSpot(Vec3(-24, 0, -27), Vec3(-15, 1.5, -15)),
        HoldSpot(Vec3(-37, 0, -20), Vec3(-26, 1.5, -7)),
      ],
      [
        HoldSpot(Vec3(31, 0, -25), Vec3(26, 1.5, -7)),
        HoldSpot(Vec3(22, 0, -27), Vec3(15, 1.5, -13)),
        HoldSpot(Vec3(37, 0, -17), Vec3(26, 1.5, -7)),
      ],
      [
        HoldSpot(Vec3(-5, 0, -18), Vec3(0, 1.5, 10)),
        HoldSpot(Vec3(6, 0, -18), Vec3(0, 1.5, 10)),
      ],
    ],
  );
}

final Map<String, GameMap Function()> mapRegistry = {'dunewall': buildDunewall};
