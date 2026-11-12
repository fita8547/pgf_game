import 'package:rps_shared/rps_shared.dart';

import 'settings.dart';

/// Korean (default) / English UI text. The game content (catalog.json) is
/// Korean, so English names for characters, skills, guns and maps live here.

bool get isEn => Settings.I.lang == 'en';

/// Picks the string for the current language.
String tr(String ko, String en) => isEn ? en : ko;

const _charEn = {
  'boulder': ('Boulder', 'Orc · M'),
  'cardboard': ('Cardboard', 'Bearfolk · M'),
  'shear': ('Shear', 'Orc · F'),
  'origami': ('Origami', 'Human · F'),
  'pebble': ('Pebble', 'Human · F'),
  'snip': ('Snip', 'Wolffolk · M'),
  'gem': ('Gem', 'Foxfolk · F'),
  'needle': ('Needle', 'Human · F'),
  'scroll': ('Scroll', 'Human · M'),
  'inkwell': ('Inkwell', 'Catfolk · F'),
  'quake': ('Quake', 'Human · M'),
  'staple': ('Staple', 'Robot'),
};

/// (name, description, cooldown text)
const _skillEn = {
  'rock_bulwark': ('Rock Bulwark', 'Raise a big stone wall in front of you that blocks bullets; players can walk through it. 1200 HP.', 'held'),
  'landslide_charge': ('Landslide Charge', 'Charge toward your WASD direction (diagonals too), grab the first enemy you hit and slam them into a wall.', '8s'),
  'magma_slug': ('Magma Slug', 'Throw a lump of lava that pierces enemies.', '6s'),
  'earth_rift': ('Earth Rift', 'Smash the ground with your hammer, knocking down enemies in a cone ahead.', 'ultimate'),
  'box_fort': ('Box Fort', 'Throw a dome barrier that surrounds the area.', '12s'),
  'crate_roll': ('Crate Roll', 'Turn into a ball and roll fast, ramming enemies. Faster, -50% damage taken, no shooting. Jump and land to slam nearby enemies.', 'toggle'),
  'tape_hook': ('Tape Hook', 'Pull an enemy toward you with a tape hook.', '8s'),
  'parcel_drop': ('Parcel Drop', 'Scatter exploding parcel mines all around.', 'ultimate'),
  'spike_guard': ('Spike Guard', 'Blocks all damage except from right behind (280°) and bounces it back to the attacker - and to allies standing close.', 'held'),
  'cleave_leap': ('Cleave Leap', 'Leap toward your WASD direction (diagonals too) and slash a wide area where you land.', '7s'),
  'blade_fence': ('Blade Fence', 'Raise a wall of blades that pushes enemies away.', '12s'),
  'blade_rain': ('Blade Rain', 'Rain blades over a wide area, rooting enemies.', 'ultimate'),
  'paper_updraft': ('Paper Updraft', 'Ride a paper wind high into the air.', '8s'),
  'paper_dash': ('Paper Dash', 'Short dash toward your WASD direction (diagonals too). Resets on a kill.', '10s'),
  'crane_scout': ('Crane Scout', 'Fly a steerable paper crane; it hits and marks the first enemy it touches.', '30s'),
  'shuriken_storm': ('Shuriken Storm', 'Get 5 precise paper shurikens. Kills refund one.', 'ultimate'),
  'gravel_blink': ('Gravel Blink', 'Teleport a short way in your move direction. 3 charges.', '3s/charge'),
  'rewind': ('Rewind', 'Return to your position from 3 seconds ago at full HP.', '12s'),
  'recon_pebble': ('Recon Pebble', 'An arrow that reveals enemies around where it lands to your team.', '25s'),
  'sticky_charge': ('Sticky Charge', 'Throw a bomb that sticks to enemies or walls and explodes big.', 'ultimate'),
  'gale_cut': ('Gale Cut', 'Dash toward your WASD direction (diagonals too), slashing. Kills reset the cooldown.', '8s'),
  'deflect': ('Deflect', 'Spin your blades for 4 s: frontal damage is blocked and returned doubled; projectiles are sent back.', '8s'),
  'phase_beacon': ('Binding Beacon', 'Throw a beacon that roots enemies near where it lands for 2 s.', '10s'),
  'twin_edge': ('Twin Edge', 'Split your scissors in two for a powerful melee mode.', 'ultimate'),
  'mend_crystal': ('Mend Crystal', 'A crystal that floats over an ally and heals them over time.', 'retarget'),
  'amp_shard': ('Amp Shard', 'Place a shard that raises nearby allies\' damage by 25%.', '14s'),
  'cleanse_bell': ('Cleanse Bell', 'Make an ally briefly invulnerable and remove harmful effects.', '14s'),
  'crystal_sanctum': ('Crystal Sanctum', 'Grow a crystal tree that heals allies around it a lot. The tree is cover.', 'ultimate'),
  'thread_tether': ('Thread Tether', 'Keep healing the ally you tie a thread to.', 'held'),
  'sleep_dart': ('Sleep Dart', 'Put the enemy you hit to sleep for a few seconds.', '12s'),
  'stitch_grenade': ('Stitch Grenade', 'Allies get more healing; enemies can\'t be healed.', '10s'),
  'nano_stitch': ('Nano Stitch', 'Raise one ally\'s damage and reduce the damage they take.', 'ultimate'),
  'mending_seal': ('Mending Seal', 'Spread a seal on the ground that heals allies inside.', '12s'),
  'ward_talisman': ('Ward Talisman', 'A talisman on an ally that absorbs some damage for them.', '8s'),
  'undying_lantern': ('Undying Lantern', 'Allies in the lantern\'s range can\'t die for 3 seconds.', '22s'),
  'grand_scroll': ('Grand Scroll', 'Unroll a giant scroll that shields the whole team.', 'ultimate'),
  'ink_cloud': ('Ink Cloud', 'Throw an ink bomb that bursts into a cloud; enemies inside are blinded until 3 s after they leave. 3 charges.', 'charges'),
  'ink_puddle': ('Ink Puddle', 'A puddle that slows enemies who step in it and deals 10 damage per second.', '16s'),
  'ink_portal': ('Ink Portal', 'Open an ink door far away and teleport through it.', '30s'),
  'brush_wall': ('Brush Wall', 'An ink wall across the map that blocks bullets and sound.', 'ultimate'),
  'rock_turret': ('Rock Turret', 'Place a turret that shoots enemies automatically.', '10s'),
  'quake_trap': ('Quake Trap', 'Roots the enemy who steps on it for 1.5 seconds.', '10s'),
  'overheat': ('Overheat', 'Briefly gain armour, fire rate and move speed.', '12s'),
  'lava_flow': ('Lava Flow', 'Pour lava around you that burns enemies over time.', 'ultimate'),
  'staple_sentry': ('Staple Sentry', 'A small wall turret that slows and shoots passing enemies.', 'charges'),
  'wire_snare': ('Wire Snare', 'A wire that reveals and briefly roots the enemy who touches it.', '12s'),
  'alarm_bot': ('Alarm Bot', 'A robot that makes nearby enemies take more damage.', 'redeploy'),
  'steel_lockdown': ('Steel Lockdown', 'Scan a wide area; after a delay, root every enemy inside.', 'ultimate'),
};

const _gunEn = {
  'pistol': ('Pistol P9', 'Pistol'),
  'revolver': ('Revolver R6', 'Pistol'),
  'smg': ('SMG Buzz', 'SMG'),
  'rifle': ('Rifle AR-K', 'Rifle'),
  'shotgun': ('Pump Shotgun M12', 'Shotgun'),
  'sniper': ('Sniper LR-50', 'Sniper'),
  'launcher': ('Rocket Launcher RX', 'Heavy'),
};

const _mapEn = {
  'rps_arena': 'RPS Arena',
  'desert_ruins': 'Desert Ruins',
  'frost_harbor': 'Frost Harbor',
  'neon_rooftops': 'Neon Rooftops',
  'jungle_temple': 'Jungle Temple',
};

const _roleEn = {
  Role.defender: ('Defender', 'High defense · Low damage'),
  Role.attack: ('Attack', 'Very high damage · Very low defense'),
  Role.healer: ('Healer', 'Strong heals · Medium damage'),
  Role.controller: ('Controller', 'Very strong skills · Average body'),
};

String charName(String id) => isEn ? (_charEn[id]?.$1 ?? id) : characterById(id).name;
String charOrigin(CharacterInfo c) => isEn ? (_charEn[c.id]?.$2 ?? '') : (c.sex == '-' ? c.race : '${c.race} · ${c.sex}');
String skillName(SkillInfo s) => isEn ? (_skillEn[s.id]?.$1 ?? s.name) : s.name;
String skillDesc(SkillInfo s) => isEn ? (_skillEn[s.id]?.$2 ?? s.desc) : s.desc;
String skillCd(SkillInfo s) => isEn ? (_skillEn[s.id]?.$3 ?? s.cdText) : s.cdText;
String gunName(String id) => isEn ? (_gunEn[id]?.$1 ?? id) : gunById(id).name;
String gunClass(GunDef g) => isEn ? (_gunEn[g.id]?.$2 ?? g.info.gunClass) : g.info.gunClass;
String mapName(String id) => isEn ? (_mapEn[id] ?? id) : mapById(id).name;
String roleName(Role r) => isEn ? _roleEn[r]!.$1 : r.label;
String roleTraits(Role r) => isEn ? _roleEn[r]!.$2 : roleStats[r]!.traits;
String armorName(ArmorDef a) => isEn ? a.nameEn : a.name;
/// Player names: bots are named after Korean character names ('Bot 페블').
String playerName(String n) {
  if (!isEn) return n;
  if (n == '플레이어') return 'Player';
  if (n.startsWith('Bot ')) {
    final k = n.substring(4);
    for (final c in characters) {
      if (c.name == k) return 'Bot ${_charEn[c.id]?.$1 ?? k}';
    }
  }
  return n;
}

String teamName(int t) => isEn ? (t == 0 ? 'Team A' : 'Team B') : (t == 0 ? 'A팀' : 'B팀');

/// Shop / server error codes from the sim, plus plain messages passed through.
String errText(String code) => switch (code) {
      'shop_room' => tr('상점은 스폰룸에서만 열립니다', 'The shop only opens in your spawn room'),
      'no_credits' => tr('크레딧이 부족합니다', 'Not enough credits'),
      'ammo_full' => tr('탄약이 이미 가득 찼습니다', 'Ammo is already full'),
      'armor_full' => tr('이미 그 이상의 방어구가 있습니다', 'You already have that much armor'),
      'go back to spawn to switch' => tr('스폰룸에서만 캐릭터를 바꿀 수 있습니다', 'Go back to spawn to switch'),
      _ => code,
    };
