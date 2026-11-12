/// Credits economy for capture + respawn (user decision: shop kept). Players
/// buy guns at the shop while standing in their spawn room. PLACEHOLDER values.
abstract final class Economy {
  static const int start = 800;
  static const int max = 9000;
  static const int kill = 200;

  /// About half of a kill (user request 2026-11-11).
  static const int assist = 100;

  /// Close to a kill so a player who keeps dying can still rebuy guns
  /// (user request 2026-11-11: kill and death roughly equal).
  static const int death = 180;

  /// Per second while alive inside the capture zone.
  static const int capturePerSecond = 10;

  /// Purchased primary is lost on death (you respawn with your sidearm and
  /// your banked credits). Set false to keep loadouts across lives.
  static const bool losePrimaryOnDeath = true;

  /// Guns that cost nothing (buy again, refill) once bought in this match
  /// (user request 2026-11-12: sniper).
  static const Set<String> freeAfterFirstBuy = {'sniper'};
}

/// Armour sold in the shop (user request 2026-11-11: 100 / 60 / 40).
/// Armour soaks damage before HP (after skill shields) and is lost on death.
/// Buying replaces your armour with that tier's full amount.
class ArmorDef {
  final String id;
  final String name;
  final String nameEn;
  final double amount;
  final int cost;
  const ArmorDef(this.id, this.name, this.nameEn, this.amount, this.cost);
}

const List<ArmorDef> armors = [
  ArmorDef('armor_light', '경량 방어구', 'Light Armor', 40, 400),
  ArmorDef('armor_medium', '중형 방어구', 'Medium Armor', 60, 650),
  ArmorDef('armor_heavy', '중장 방어구', 'Heavy Armor', 100, 1000),
];

ArmorDef? armorById(String id) {
  for (final a in armors) {
    if (a.id == id) return a;
  }
  return null;
}
