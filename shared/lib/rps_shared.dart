/// Shared code for RPS (hero shooter): content tables, map collision built
/// from the GLB assets, and the authoritative game simulation (the server
/// runs it, the client mirrors it for prediction).
library;

export 'src/math.dart';
export 'src/content/catalog_types.dart';
export 'src/content/catalog.g.dart';
export 'src/content/characters.dart';
export 'src/content/economy.dart';
export 'src/content/guns.dart';
export 'src/content/maps.dart';
export 'src/content/roles.dart';
export 'src/world/collision.dart';
export 'src/world/glb.dart';
export 'src/world/map_loader.dart';
export 'src/net/protocol.dart';
export 'src/sim/bot.dart';
export 'src/sim/input.dart';
export 'src/sim/movement.dart';
export 'src/sim/nav.dart';
export 'src/sim/player.dart';
export 'src/sim/sim.dart';
export 'src/sim/skills.dart';
export 'src/sim/skills_controller.dart';
export 'src/sim/skills_healer.dart';
export 'src/sim/skills_attack.dart';
export 'src/sim/skills_defender.dart';
