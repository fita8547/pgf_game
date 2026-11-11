import 'dart:math' as math;

import 'agents.dart';
import 'math.dart';
import 'weapons.dart';

const double standHeight = 1.8;
const double crouchHeight = 1.2;
const double playerRadius = 0.38;
const double maxHp = 100;

class Player {
  final int id;
  String name;

  /// Team group 0 or 1 (which group attacks depends on the half).
  int team;
  AgentId agent;
  bool isBot;
  bool connected = true;

  /// Database id of the logged-in account (null for bots/guests).
  int? accountId;

  final Vec3 pos = Vec3.zero();
  final Vec3 vel = Vec3.zero();
  double yaw = 0, pitch = 0;
  bool onGround = true, crouch = false, walking = false, ads = false;

  double hp = maxHp, shield = 0;
  bool alive = true;
  int credits = 800;

  WeaponId? primary;
  WeaponId secondary = WeaponId.sidearm;

  /// 0 primary, 1 secondary, 2 melee.
  int slot = 1;
  int primMag = 0, primRes = 0, secMag = 12, secRes = 36;

  int qCharges = 0, eCharges = 0;
  double eRecharge = 0;
  double flashTime = 0;
  double healLeft = 0;
  double revealTime = 0;
  double dashTime = 0;
  double dashX = 0, dashZ = 0;
  double plantProgress = 0;

  /// Movement anti-abuse state (see GameSim._move).
  double jumpCooldown = 0, landPenalty = 0, groundTime = 1, stuckTime = 0;
  int hopChain = 0;

  int kills = 0, deaths = 0, assists = 0, score = 0, headshots = 0, damage = 0;

  /// Bit i set = visible to team i.
  int spottedMask = 0;

  int lastSeq = 0;
  double fireCooldown = 0, reloadTimer = 0, equipTimer = 0;
  double recoilIndex = 0, sinceShot = 10;
  int prevButtons = 0;
  int shotSeq = 0;

  /// Damage received this round, by attacker id (assists).
  final Map<int, double> damageFrom = {};

  /// Survived the previous round (keeps gear).
  bool survived = false;

  Player(this.id, this.name, this.team, this.agent, {this.isBot = false, this.accountId});

  AgentDef get agentDef => agents[agent]!;

  WeaponId get currentWeapon {
    switch (slot) {
      case 0:
        return primary ?? secondary;
      case 1:
        return secondary;
      default:
        return WeaponId.knife;
    }
  }

  WeaponDef get weapon => weapons[currentWeapon]!;
  double get height => crouch ? crouchHeight : standHeight;
  double get eyeHeight => crouch ? 1.05 : 1.6;
  Vec3 get eye => Vec3(pos.x, pos.y + eyeHeight, pos.z);
  Vec3 get viewDir => dirFromAngles(yaw, pitch);

  int get mag => slot == 0 && primary != null ? primMag : (slot == 2 ? 1 : secMag);
  int get reserve => slot == 0 && primary != null ? primRes : (slot == 2 ? 0 : secRes);
  set mag(int v) {
    if (slot == 0 && primary != null) {
      primMag = v;
    } else if (slot == 1 || primary == null) {
      secMag = v;
    }
  }

  set reserve(int v) {
    if (slot == 0 && primary != null) {
      primRes = v;
    } else if (slot == 1 || primary == null) {
      secRes = v;
    }
  }

  void refillAmmo() {
    if (primary != null) {
      final d = weapons[primary]!;
      primMag = d.mag;
      primRes = d.reserve;
    }
    final s = weapons[secondary]!;
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

  List toNet() => [
        id, name, team, agent.index, flags, //
        r(pos.x), r(pos.y), r(pos.z), r(vel.x), r(vel.y), r(vel.z),
        r(yaw, 4), r(pitch, 4), r(hp, 1), r(shield, 1), credits,
        primary?.index ?? -1, secondary.index, slot, primMag, primRes, secMag, secRes,
        qCharges, eCharges, r(eRecharge, 2), r(flashTime, 2), r(plantProgress, 2),
        kills, deaths, assists, score, spottedMask, r(revealTime, 2), lastSeq,
        r(fireCooldown, 4), r(reloadTimer, 3), r(equipTimer, 3), r(recoilIndex, 3), r(sinceShot, 3),
        prevButtons, r(dashTime, 3), shotSeq, headshots, damage, accountId ?? -1,
        r(dashX, 3), r(dashZ, 3),
        r(jumpCooldown, 3), r(landPenalty, 3), r(math.min(groundTime, 9), 3), hopChain,
      ];

  static Player fromNet(List l) {
    final p = Player((l[0] as num).toInt(), l[1] as String, (l[2] as num).toInt(),
        AgentId.values[(l[3] as num).toInt()]);
    p.applyNet(l);
    return p;
  }

  void applyNet(List l) {
    double d(int i) => (l[i] as num).toDouble();
    int n(int i) => (l[i] as num).toInt();
    name = l[1] as String;
    team = n(2);
    agent = AgentId.values[n(3)];
    flags = n(4);
    pos.set(d(5), d(6), d(7));
    vel.set(d(8), d(9), d(10));
    yaw = d(11);
    pitch = d(12);
    hp = d(13);
    shield = d(14);
    credits = n(15);
    primary = n(16) < 0 ? null : WeaponId.values[n(16)];
    secondary = WeaponId.values[n(17)];
    slot = n(18);
    primMag = n(19);
    primRes = n(20);
    secMag = n(21);
    secRes = n(22);
    qCharges = n(23);
    eCharges = n(24);
    eRecharge = d(25);
    flashTime = d(26);
    plantProgress = d(27);
    kills = n(28);
    deaths = n(29);
    assists = n(30);
    score = n(31);
    spottedMask = n(32);
    revealTime = d(33);
    lastSeq = n(34);
    fireCooldown = d(35);
    reloadTimer = d(36);
    equipTimer = d(37);
    recoilIndex = d(38);
    sinceShot = d(39);
    prevButtons = n(40);
    dashTime = d(41);
    shotSeq = n(42);
    headshots = n(43);
    damage = n(44);
    accountId = n(45) < 0 ? null : n(45);
    dashX = d(46);
    dashZ = d(47);
    if (l.length > 51) {
      jumpCooldown = d(48);
      landPenalty = d(49);
      groundTime = d(50);
      hopChain = n(51);
    }
  }
}
