import 'catalog.g.dart';
import 'catalog_types.dart';
import 'roles.dart';

/// Hitbox / camera dimensions for one character, measured from the rest pose
/// bones of `glb/characters/<id>.glb` (tool/scan_chars.dart). Hitboxes follow
/// the bones (brief §6-4): head sphere on the `head` node, torso capsule
/// hips..neck, legs capsule ground..hips.
class Body {
  /// `head` node height (neck top pivot).
  final double head;
  final double neck;
  final double hips;
  final double headR, torsoR, legR;
  const Body(this.head, this.neck, this.hips, {this.headR = 0.15, this.torsoR = 0.26, this.legR = 0.2});

  /// Big frames (orc / bear) are wider.
  const Body.big(this.head, this.neck, this.hips)
      : headR = 0.17,
        torsoR = 0.32,
        legR = 0.24;

  /// Camera height above feet when standing.
  double get eye => head + 0.11;
  double get headCenter => head + 0.13;
}

/// Movement collision is the same capsule for everyone so no character can
/// fit through gaps others can't.
const double playerRadius = 0.38;
const double standHeight = 1.8;
const double crouchHeight = 1.2;

/// Crouching scales hitbox heights by this.
const double crouchScale = crouchHeight / standHeight;

const Map<String, Body> _bodies = {
  'boulder': Body.big(1.66, 1.57, 1.00),
  'cardboard': Body.big(1.70, 1.62, 1.03),
  'shear': Body.big(1.57, 1.49, 0.95),
  'origami': Body(1.48, 1.41, 0.90),
  'pebble': Body(1.42, 1.35, 0.86),
  'snip': Body(1.51, 1.43, 0.91),
  'gem': Body(1.45, 1.38, 0.88),
  'needle': Body(1.42, 1.35, 0.86),
  'scroll': Body(1.48, 1.41, 0.90),
  'inkwell': Body(1.45, 1.38, 0.88),
  'quake': Body(1.41, 1.33, 0.85),
  'staple': Body(1.48, 1.41, 0.90),
};

/// Per-character damage multiplier on top of the role profile (all damage
/// the character deals: guns and skills).
const Map<String, double> characterDamage = {
  'origami': 1.5,
};

/// Per-character max HP overriding the role profile.
const Map<String, double> characterHp = {
  'cardboard': 500,
};

/// Everything the sim needs about a character: catalog info (art, skills)
/// joined with role stats and body dimensions.
class CharacterDef {
  final CharacterInfo info;
  final Body body;
  const CharacterDef(this.info, this.body);

  String get id => info.id;
  String get name => info.name;
  Role get role => info.role;
  RoleStats get stats => roleStats[info.role]!;
  double get maxHp => characterHp[info.id] ?? stats.hp;
  double get speed => stats.speed;
  double get damageMul => characterDamage[info.id] ?? 1;
}

final List<CharacterDef> characters = [
  for (final c in characterInfos) CharacterDef(c, _bodies[c.id] ?? const Body(1.45, 1.38, 0.88)),
];

final Map<String, CharacterDef> _byId = {for (final c in characters) c.id: c};

CharacterDef characterById(String id) => _byId[id] ?? characters.first;
bool isCharacter(String id) => _byId.containsKey(id);
