import '../content/characters.dart';
import '../content/economy.dart';
import '../content/guns.dart';
import '../math.dart';

/// fx keys that are server bookkeeping only (not sent in snapshots).
final _serverOnlyFx = RegExp(r'^(bump|cut)\d+$|^(healed|dashedAt|grab|rollAir)$');

class Player {
  final int id;
  String name;

  /// 0 = team A (spawn at +Z), 1 = team B (spawn at -Z).
  int team;
  String charId;
  bool isBot;
  bool connected = true;

  final Vec3 pos = Vec3.zero();
  final Vec3 vel = Vec3.zero();
  double yaw = 0, pitch = 0;
  bool onGround = false, crouch = false, walking = false, ads = false;

  /// 0..1 ADS blend (drives FOV and viewmodel on the client).
  double adsT = 0;

  double hp = 0;

  /// Bought armour; soaks damage before HP, lost on death.
  double armor = 0;

  /// Guns from [Economy.freeAfterFirstBuy] this player has bought this match.
  final Set<String> unlocked = {};
  bool alive = false;
  double respawnIn = 0;
  double spawnProtect = 0;
  int credits = Economy.start;

  String? primary;
  String secondary = 'pistol';

  /// 0 = primary, 1 = secondary.
  int slot = 1;
  int primMag = 0, primRes = 0, secMag = 0, secRes = 0;

  double fireCooldown = 0, reloadTimer = 0, drawTimer = 0;
  double recoilIndex = 0, sinceShot = 10;
  int shotSeq = 0;
  int prevButtons = 0;
  int lastSeq = 0;

  /// Movement anti-abuse state (see movement.dart).
  double jumpCooldown = 0, landPenalty = 0, groundTime = 1, stuckTime = 0;
  int hopChain = 0;

  /// Ult points (damage dealt, healing, objective time).
  double ult = 0;

  /// Skill slots Q, E, Shift: remaining cooldown (or time to the next charge)
  /// and charges left. See skills.dart.
  final List<double> skillCd = [0, 0, 0];
  final List<int> skillCharges = [1, 1, 1];

  /// Seconds this player stays revealed to the enemy team (recon skills).
  double revealed = 0;

  /// Status effects and skill state, by key (see effects.dart). Timed keys
  /// count down to 0 and are removed; values like 'slowMul' ride along.
  final Map<String, double> fx = {};

  /// Weapon/skill mode replacing normal shooting ('' = guns): shuriken,
  /// twin, roll, guard, deflect.
  String mode = '';

  /// Server-only (not networked): recent (time, x, y, z, hp) samples, newest
  /// last, for rewind-type skills.
  final List<List<double>> history = [];

  int kills = 0, deaths = 0, assists = 0, headshots = 0;
  double damageDealt = 0, captureTime = 0;

  /// Damage received this life, by attacker id (assists, fall-kill credit).
  final Map<int, double> damageFrom = {};
  int? lastAttacker;
  double sinceDamaged = 99;

  /// Fractional credit accumulator for per-second income.
  double creditFrac = 0;

  Player(this.id, this.name, this.team, this.charId, {this.isBot = false});

  CharacterDef get character => characterById(charId);
  Body get body => character.body;
  double get maxHp => character.maxHp;

  String get gunId => slot == 0 && primary != null ? primary! : secondary;
  GunDef get gun => gunById(gunId);

  double get height => crouch ? crouchHeight : standHeight;
  double get eyeHeight => crouch ? body.eye * crouchScale : body.eye;
  Vec3 get eye => Vec3(pos.x, pos.y + eyeHeight, pos.z);
  Vec3 get viewDir => dirFromAngles(yaw, pitch);

  int get mag => slot == 0 && primary != null ? primMag : secMag;
  int get reserve => slot == 0 && primary != null ? primRes : secRes;
  set mag(int v) => slot == 0 && primary != null ? primMag = v : secMag = v;
  set reserve(int v) => slot == 0 && primary != null ? primRes = v : secRes = v;

  void refillAmmo() {
    if (primary != null) {
      final s = gunById(primary!).stats;
      primMag = s.mag;
      primRes = s.reserve;
    }
    final s = gunById(secondary).stats;
    secMag = s.mag;
    secRes = s.reserve;
  }

  int get flags =>
      (alive ? 1 : 0) |
      (crouch ? 2 : 0) |
      (onGround ? 4 : 0) |
      (isBot ? 8 : 0) |
      (ads ? 16 : 0) |
      (walking ? 32 : 0) |
      (connected ? 64 : 0);

  set flags(int f) {
    alive = f & 1 != 0;
    crouch = f & 2 != 0;
    onGround = f & 4 != 0;
    isBot = f & 8 != 0;
    ads = f & 16 != 0;
    walking = f & 32 != 0;
    connected = f & 64 != 0;
  }

  /// Compact snapshot row. Order is the wire format: append only.
  List toNet() => [
        id, name, team, charId, flags, //
        r(pos.x), r(pos.y), r(pos.z), r(vel.x), r(vel.y), r(vel.z),
        r(yaw, 4), r(pitch, 4), r(hp, 1), r(respawnIn, 2), r(spawnProtect, 2), credits,
        primary ?? '', secondary, slot, primMag, primRes, secMag, secRes,
        r(fireCooldown, 4), r(reloadTimer, 3), r(drawTimer, 3), r(recoilIndex, 3), r(sinceShot, 3), shotSeq,
        prevButtons, lastSeq, r(adsT, 3),
        r(jumpCooldown, 3), r(landPenalty, 3), r(groundTime > 9 ? 9 : groundTime, 3), hopChain,
        r(ult, 1), kills, deaths, assists, headshots, r(damageDealt, 0), r(captureTime, 1),
        r(skillCd[0], 2), r(skillCd[1], 2), r(skillCd[2], 2), ...skillCharges, r(revealed, 2),
        {for (final e in fx.entries) if (!_serverOnlyFx.hasMatch(e.key)) e.key: r(e.value, 3)}, mode,
        r(armor, 1),
        unlocked.join(','),
      ];

  static Player fromNet(List l) {
    final p = Player((l[0] as num).toInt(), l[1] as String, (l[2] as num).toInt(), l[3] as String);
    p.applyNet(l);
    return p;
  }

  void applyNet(List l) {
    double d(int i) => (l[i] as num).toDouble();
    int n(int i) => (l[i] as num).toInt();
    name = l[1] as String;
    team = n(2);
    charId = l[3] as String;
    flags = n(4);
    pos.set(d(5), d(6), d(7));
    vel.set(d(8), d(9), d(10));
    yaw = d(11);
    pitch = d(12);
    hp = d(13);
    respawnIn = d(14);
    spawnProtect = d(15);
    credits = n(16);
    primary = (l[17] as String).isEmpty ? null : l[17] as String;
    secondary = l[18] as String;
    slot = n(19);
    primMag = n(20);
    primRes = n(21);
    secMag = n(22);
    secRes = n(23);
    fireCooldown = d(24);
    reloadTimer = d(25);
    drawTimer = d(26);
    recoilIndex = d(27);
    sinceShot = d(28);
    shotSeq = n(29);
    prevButtons = n(30);
    lastSeq = n(31);
    adsT = d(32);
    jumpCooldown = d(33);
    landPenalty = d(34);
    groundTime = d(35);
    hopChain = n(36);
    ult = d(37);
    kills = n(38);
    deaths = n(39);
    assists = n(40);
    headshots = n(41);
    damageDealt = d(42);
    captureTime = d(43);
    if (l.length > 50) {
      for (var k = 0; k < 3; k++) {
        skillCd[k] = d(44 + k);
        skillCharges[k] = n(47 + k);
      }
      revealed = d(50);
    }
    if (l.length > 52) {
      fx
        ..clear()
        ..addAll({for (final e in (l[51] as Map).entries) e.key as String: (e.value as num).toDouble()});
      mode = l[52] as String;
    }
    armor = l.length > 53 ? d(53) : 0;
    unlocked.clear();
    if (l.length > 54 && (l[54] as String).isNotEmpty) unlocked.addAll((l[54] as String).split(','));
  }
}
