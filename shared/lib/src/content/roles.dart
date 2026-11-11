import 'catalog_types.dart';

/// Role identity (user decision 2026-11-11, replaces the earlier RPS role
/// counter): every role has a fixed strength profile instead of matchups.
///  - 디펜서(탱커): tough (takes less damage), deals less damage.
///  - 어택: hits very hard, very fragile.
///  - 힐러: strong heals, medium damage.
///  - 컨트롤러: average body, much stronger skills (damage + cooldowns).
/// PLACEHOLDER numbers - tune in playtests.
class RoleStats {
  final double hp;

  /// Run speed (m/s).
  final double speed;

  /// Ult points needed.
  final double ultCost;

  /// Incoming damage multiplier (0.75 = 25% armour).
  final double damageTaken;

  /// Outgoing damage multiplier (guns and skills).
  final double damageDealt;

  /// Extra multiplier on skill damage (on top of [damageDealt]).
  final double skillPower;

  /// Skill cooldown multiplier (0.75 = 25% faster).
  final double skillCooldown;

  /// Healing done multiplier.
  final double healPower;

  /// One-line description for the lobby.
  final String traits;

  const RoleStats({
    required this.hp,
    required this.speed,
    required this.ultCost,
    this.damageTaken = 1,
    this.damageDealt = 1,
    this.skillPower = 1,
    this.skillCooldown = 1,
    this.healPower = 1,
    required this.traits,
  });
}

const Map<Role, RoleStats> roleStats = {
  Role.defender: RoleStats(
      hp: 300, speed: 5.2, ultCost: 1800, damageTaken: 0.75, damageDealt: 0.8, traits: '방어력 높음 · 공격력 낮음'),
  Role.attack: RoleStats(
      hp: 175, speed: 5.9, ultCost: 1600, damageTaken: 1.2, damageDealt: 1.35, traits: '공격력 매우 높음 · 방어력 매우 낮음'),
  Role.healer: RoleStats(hp: 200, speed: 5.5, ultCost: 1700, damageDealt: 0.9, healPower: 1.3, traits: '치유 강화 · 공격력 보통'),
  Role.controller: RoleStats(
      hp: 225, speed: 5.5, ultCost: 1700, skillPower: 1.5, skillCooldown: 0.75, traits: '스킬 매우 강함 · 공격·방어 보통'),
};
