/// Types for the asset catalog (catalog.g.dart is generated from
/// rps_assets/catalog.json). These describe *what exists* in the art; game
/// numbers live in the hand-tuned tables (roles.dart, characters.dart,
/// guns.dart, economy.dart).
library;

enum Role {
  defender('디펜서'),
  attack('어택'),
  healer('힐러'),
  controller('컨트롤러');

  final String label;
  const Role(this.label);
}

enum SkillKey {
  q('Q'),
  e('E'),
  shift('Shift'),
  ult('궁');

  final String label;
  const SkillKey(this.label);
}

enum CooldownKind {
  /// Fixed cooldown after use ([SkillInfo.cooldown] seconds).
  cooldown,

  /// Held/maintained (e.g. barrier with durability).
  sustain,

  /// On/off mode or target switch.
  toggle,

  /// Charge based (e.g. 3 blinks, 3 s per charge).
  charges,

  /// Placed device that can be picked up and placed again.
  redeploy,

  /// Charged by ult points.
  ultimate,
}

class SkillInfo {
  final String id;
  final SkillKey key;
  final String name;
  final String desc;
  final String cdText;

  /// Seconds parsed from [cdText] (0 when not a plain cooldown). Placeholder
  /// values from the brief: balance pass pending.
  final double cooldown;
  final CooldownKind kind;
  final String file;

  const SkillInfo({
    required this.id,
    required this.key,
    required this.name,
    required this.desc,
    required this.cdText,
    required this.cooldown,
    required this.kind,
    required this.file,
  });
}

class CharacterInfo {
  final String id;
  final String name;
  final Role role;
  final String race;
  final String sex;
  final String file;
  final String fpArms;
  final List<SkillInfo> skills;

  const CharacterInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.race,
    required this.sex,
    required this.file,
    required this.fpArms,
    required this.skills,
  });

  SkillInfo skill(SkillKey k) => skills.firstWhere((s) => s.key == k);
}

class GunInfo {
  final String id;
  final String name;
  final String gunClass;
  final String file;
  final String fpRig;

  /// ADS: viewmodel offset = (0,0,-eye) - (hold + sight); FOV 70 -> adsFov.
  final List<double> adsHold, adsSight;
  final double adsFov, adsEye;
  final bool scope;

  /// Sniper: switch to full-screen scope overlay when zoomed in.
  final bool overlay;

  const GunInfo({
    required this.id,
    required this.name,
    required this.gunClass,
    required this.file,
    required this.fpRig,
    required this.adsHold,
    required this.adsSight,
    required this.adsFov,
    required this.adsEye,
    required this.scope,
    required this.overlay,
  });
}

class FxInfo {
  final String id;
  final String name;
  final String file;
  final String anim;
  const FxInfo({required this.id, required this.name, required this.file, required this.anim});
}
