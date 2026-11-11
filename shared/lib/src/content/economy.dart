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
}
