import 'dart:math' as math;

import '../content/catalog_types.dart';
import '../content/characters.dart';
import '../content/economy.dart';
import '../content/guns.dart';
import '../math.dart';
import '../world/collision.dart';
import '../world/map_loader.dart';
import 'bot.dart';
import 'input.dart';
import 'movement.dart';
import 'nav.dart';
import 'player.dart';
import 'skills.dart';
import 'skills_defender.dart';

class SimConfig {
  final int teamSize;
  final double respawnTime;

  /// Countdown before the match goes live (players frozen in spawn).
  final double pregame;

  /// Seconds for one player to capture a neutral/enemy point.
  final double captureTime;

  /// Seconds of uncontested ownership needed to win (100%).
  final double holdToWin;
  /// Match time limit in seconds; 0 = no limit (first to 100% wins).
  final double timeLimit;
  /// Seconds after (re)spawning during which you can't be hurt while still
  /// inside your own spawn room.
  final double spawnProtect;

  /// HP per second healed while inside your own spawn room.
  final double spawnRegen;

  /// Damage per second inside the enemy spawn room (anti spawn-camping).
  final double enemySpawnDps;
  final double botSkill;

  const SimConfig({
    this.teamSize = 5,
    this.respawnTime = 10,
    this.pregame = 5,
    this.captureTime = 8,
    this.holdToWin = 100,
    this.timeLimit = 0,
    this.spawnProtect = 5,
    this.spawnRegen = 60,
    this.enemySpawnDps = 150,
    this.botSkill = 0.6,
  });
}

enum Phase { pregame, live, ended }

class Projectile {
  final int id;
  int owner, team;

  /// Server-only scratch: who/what this projectile already hit (piercing).
  final Set<String> hits = {};

  /// Turns toward the owner's aim while flying (guided skills).
  bool steer = false;

  /// Deflected: now belongs to [newOwner]'s team.
  void reflect(int newOwner, int newTeam) {
    owner = newOwner;
    team = newTeam;
    hits.clear();
  }

  /// Gun id (rocket) or skill id (recon_pebble, sticky_charge...).
  final String gun;
  final Vec3 pos, vel;
  double life;

  /// Downward acceleration (thrown skills arc; rockets fly straight).
  double gravity;

  /// Stuck to a wall (or to [stuckTo] player at [offset]); [fuse] counts down.
  bool stuck = false;
  int? stuckTo;
  Vec3? offset;
  double fuse = 0;

  Projectile(this.id, this.owner, this.team, this.gun, this.pos, this.vel, this.life, {this.gravity = 0});

  List toNet() => [id, owner, team, gun, ...pos.toList(2), ...vel.toList(2), stuck ? 1 : 0];

  static Projectile fromNet(List l) {
    double d(int i) => (l[i] as num).toDouble();
    return Projectile((l[0] as num).toInt(), (l[1] as num).toInt(), (l[2] as num).toInt(), l[3] as String,
        Vec3(d(4), d(5), d(6)), Vec3(d(7), d(8), d(9)), 1)
      ..stuck = l.length > 10 && l[10] == 1;
  }
}

/// Something a skill placed in the world: barrier, turret, trap, area, smoke.
/// [kind] is the skill id; behaviour lives in that skill's SkillImpl.
class Deployable {
  final int id;
  final int owner, team;
  final String kind;
  final Vec3 pos;
  double yaw;
  double hp, maxHp;
  double life;
  double radius;
  double age = 0;
  final Map<String, double> data = {};
  int? collider;

  Deployable(this.id, this.owner, this.team, this.kind, this.pos,
      {this.yaw = 0, this.hp = 0, this.life = 10, this.radius = 0})
      : maxHp = hp;

  bool get alive => life > 0 && (maxHp <= 0 || hp > 0);

  List toNet() => [id, owner, team, kind, ...pos.toList(2), r(yaw, 3), r(hp, 0), r(maxHp, 0), r(life, 2), r(radius, 2)];

  static Deployable fromNet(List l) {
    double d(int i) => (l[i] as num).toDouble();
    final dp = Deployable((l[0] as num).toInt(), (l[1] as num).toInt(), (l[2] as num).toInt(), l[3] as String,
        Vec3(d(4), d(5), d(6)),
        yaw: d(7), hp: d(8), life: d(10), radius: d(11));
    dp.maxHp = d(9);
    return dp;
  }
}

/// Authoritative capture-point match. The server runs it; the client runs the
/// same code for prediction (authoritative = false skips damage/spawns).
class GameSim {
  final GameMap map;
  final SimConfig cfg;
  final bool authoritative;
  final Mover mover;
  late final NavGrid nav = NavGrid.build(map, mover);

  /// Nav nodes inside the capture zone that both teams can reach (bot goals).
  late final List<int> captureNodes = () {
    final a = nav.reachable(map.spawns[0].first.pos), b = nav.reachable(map.spawns[1].first.pos);
    return [
      for (var i = 0; i < nav.length; i++)
        if (a.contains(i) && b.contains(i) && map.inCapture(nav.node(i))) i,
    ];
  }();

  final Map<int, Player> players = {};
  final Map<int, BotBrain> bots = {};
  final List<Projectile> projectiles = [];
  final List<Deployable> deployables = [];
  final List<Map<String, Object?>> events = [];

  int tick = 0;
  double time = 0;
  Phase phase = Phase.pregame;
  double phaseTime = 0;

  /// Capture state. [owner]: team holding the point (-1 none). [capTeam] is
  /// the team currently taking it, with [capProgress] 0..1.
  int owner = -1, capTeam = -1;
  double capProgress = 0;
  bool contested = false;
  final List<double> score = [0, 0];
  final List<int> onPoint = [0, 0];
  int winner = -1;

  int _nextId = 1, _nextProj = 1, _nextDep = 1;
  final Rng rng;
  final Map<int, Map<int, List<double>>> _history = {};
  late final List<List<SpawnPoint>> spawnPoints = [_expandSpawns(0), _expandSpawns(1)];

  GameSim(this.map, {this.cfg = const SimConfig(), this.authoritative = true, int seed = 1})
      : mover = Mover(map.world),
        rng = Rng(seed);

  // ------------------------------------------------------------- roster --
  Iterable<Player> team(int t) => players.values.where((p) => p.team == t);

  int _smallerTeam() => team(0).length <= team(1).length ? 0 : 1;

  Player addPlayer(String name, String charId, {int? teamId, bool bot = false}) {
    final t = teamId ?? _smallerTeam();
    final p = Player(_nextId++, name, t, isCharacter(charId) ? charId : characters.first.id, isBot: bot);
    players[p.id] = p;
    if (bot) bots[p.id] = BotBrain(cfg.botSkill, seed: p.id * 7919 + rng.nextInt() % 100000);
    _spawn(p);
    return p;
  }

  void removePlayer(int id) {
    players.remove(id);
    bots.remove(id);
  }

  /// Fills both teams up to [SimConfig.teamSize] with bots.
  void fillBots() {
    for (var t = 0; t < 2; t++) {
      while (team(t).length < cfg.teamSize) {
        final used = team(t).map((p) => p.charId).toSet();
        final free = characters.where((c) => !used.contains(c.id)).toList();
        final c = (free.isEmpty ? characters : free)[rng.nextInt() % (free.isEmpty ? characters.length : free.length)];
        addPlayer('Bot ${c.name}', c.id, teamId: t, bot: true);
      }
    }
  }

  /// Character swap: allowed while dead or inside your own spawn room.
  String? pickCharacter(Player p, String charId) {
    if (!isCharacter(charId)) return 'unknown character';
    if (p.alive && !map.inSpawnRoom(p.team, p.pos)) return 'go back to spawn to switch';
    final hpFrac = p.alive ? p.hp / p.maxHp : 1.0;
    p.charId = charId;
    p.hp = p.maxHp * hpFrac;
    p.ult = 0;
    resetSkills(p);
    return null;
  }

  // --------------------------------------------------------------- shop --
  /// Buys [gunId] (replaces the gun in that slot). Only alive, in own spawn.
  String? buy(Player p, String gunId) {
    if (!isGun(gunId)) return 'unknown gun';
    if (phase == Phase.ended) return 'match over';
    if (!p.alive || !map.inSpawnRoom(p.team, p.pos)) return 'shop is only open in your spawn room';
    final g = gunById(gunId);
    final current = g.slot == GunSlot.primary ? p.primary : p.secondary;
    if (current == gunId) return 'already owned';
    if (p.credits < g.stats.cost) return 'not enough credits';
    p.credits -= g.stats.cost;
    if (g.slot == GunSlot.primary) {
      p.primary = gunId;
      p.primMag = g.stats.mag;
      p.primRes = g.stats.reserve;
      _equip(p, 0);
    } else {
      p.secondary = gunId;
      p.secMag = g.stats.mag;
      p.secRes = g.stats.reserve;
      _equip(p, 1);
    }
    events.add({'e': 'buy', 'p': p.id, 'g': gunId});
    return null;
  }

  void _equip(Player p, int slot) {
    p.slot = slot;
    p.drawTimer = p.gun.stats.drawTime;
    p.reloadTimer = 0;
    p.ads = false;
    p.recoilIndex = 0;
  }

  // -------------------------------------------------------------- spawn --
  List<SpawnPoint> _expandSpawns(int t) {
    final out = <SpawnPoint>[];
    const ring = [(0.0, 0.0), (1.3, 0.0), (-1.3, 0.0), (0.0, 1.3), (0.0, -1.3)];
    for (final s in map.spawns[t]) {
      for (final (ox, oz) in ring) {
        final x = s.pos.x + ox, z = s.pos.z + oz;
        if (!map.inSpawnRoom(t, Vec3(x, s.pos.y, z))) continue;
        final y = map.world.groundBelow(x, z, s.pos.y + 1) ?? s.pos.y;
        if (mover.capsuleFree(x, y + 0.01, z)) out.add(SpawnPoint(Vec3(x, y + 0.001, z), s.yaw));
      }
    }
    return out.isEmpty ? map.spawns[t] : out;
  }

  void _spawn(Player p) {
    final pts = spawnPoints[p.team];
    SpawnPoint best = pts.first;
    var bestD = -1.0;
    final start = rng.nextInt() % pts.length;
    for (var i = 0; i < pts.length; i++) {
      final s = pts[(start + i) % pts.length];
      var d = 99.0;
      for (final q in players.values) {
        if (q.id != p.id && q.alive) d = math.min(d, q.pos.distanceTo(s.pos));
      }
      if (d > 1.0) {
        best = s;
        break;
      }
      if (d > bestD) {
        bestD = d;
        best = s;
      }
    }
    p.pos.setFrom(best.pos);
    p.vel.set(0, 0, 0);
    p.yaw = best.yaw;
    p.pitch = 0;
    p.hp = p.maxHp;
    p.alive = true;
    p.respawnIn = 0;
    p.crouch = false;
    p.onGround = true;
    p.spawnProtect = cfg.spawnProtect;
    p.damageFrom.clear();
    p.lastAttacker = null;
    p.stuckTime = 0;
    p.refillAmmo();
    resetSkills(p);
    _equip(p, p.primary != null ? 0 : 1);
    p.drawTimer = 0;
    events.add({'e': 'spawn', 'p': p.id});
  }

  // -------------------------------------------------------------- input --
  /// Applies one input frame. [predict]: client-side prediction (no damage).
  /// [replay]: re-simulation after reconciliation (no effect events either).
  void processInput(Player p, PlayerInput inp, {bool predict = false, bool replay = false}) {
    double f(double v) => v.isFinite ? v : 0;
    inp
      ..dt = f(inp.dt)
      ..yaw = f(inp.yaw)
      ..pitch = f(inp.pitch)
      ..moveX = clampD(f(inp.moveX), -1, 1)
      ..moveZ = clampD(f(inp.moveZ), -1, 1)
      ..renderTick = f(inp.renderTick);
    final dt = clampD(inp.dt, 0, 0.1);
    p.lastSeq = inp.seq;
    final pressed = inp.buttons & ~p.prevButtons;
    p.prevButtons = inp.buttons;
    if (!p.alive) return;
    p.yaw = wrapAngle(inp.yaw);
    p.pitch = clampD(inp.pitch, -1.5, 1.5);

    if (pressed & Btn.slotPrimary != 0 && p.primary != null && p.slot != 0) _equip(p, 0);
    if (pressed & Btn.slotSecondary != 0 && p.slot != 1) _equip(p, 1);

    final frozen = phase != Phase.live || rooted(p);
    final speed = p.character.speed * p.gun.stats.moveMult * moveMult(p);
    mover.move(p, inp, pressed, dt, speed: speed, frozen: frozen);
    _weapon(p, inp, pressed, dt, predict, replay);
    if (pressed & (Btn.skillQ | Btn.skillE | Btn.skillShift | Btn.ult) != 0) _skills(p, inp, pressed, predict, replay);
  }

  // ------------------------------------------------------------- skills --
  static const _skillButtons = [
    (SkillKey.q, Btn.skillQ),
    (SkillKey.e, Btn.skillE),
    (SkillKey.shift, Btn.skillShift),
    (SkillKey.ult, Btn.ult),
  ];

  /// Per-charge cooldown for slot [k] of [p]'s character.
  (SkillImpl?, int maxCharges, double cooldown) skillSpec(Player p, SkillKey key) {
    final info = p.character.info.skill(key);
    final impl = skillImpls[info.id];
    final cd = (impl?.cooldown ?? (info.cooldown > 0 ? info.cooldown : 8)) * p.character.stats.skillCooldown;
    return (impl, impl?.maxCharges ?? 1, cd);
  }

  void resetSkills(Player p) {
    for (final (key, _) in _skillButtons) {
      final k = skillSlot(key);
      if (k < 0) continue;
      final (_, maxC, _) = skillSpec(p, key);
      p.skillCharges[k] = maxC;
      p.skillCd[k] = 0;
    }
    p.history.clear();
    p.revealed = 0;
  }

  bool ultReady(Player p) => p.ult >= p.character.stats.ultCost;

  void _skills(Player p, PlayerInput inp, int pressed, bool predict, bool replay) {
    if (phase != Phase.live || !p.alive) return;
    for (final (key, btn) in _skillButtons) {
      if (pressed & btn == 0) continue;
      final (impl, maxC, cd) = skillSpec(p, key);
      if (impl == null) continue;
      if (predict && !impl.predictable) continue;
      final k = skillSlot(key);
      if (disabled(p)) continue;
      // Recast-style skills (recall, teleport to beacon) are free and allowed
      // while on cooldown; the impl decides.
      final ready = k < 0 ? ultReady(p) : p.skillCharges[k] > 0;
      if (!ready && !impl.recastable(this, p)) continue;
      final res = impl.use(this, p, inp);
      if (res == Use.fail) continue;
      if (res == Use.spend) {
        if (k < 0) {
          p.ult = 0;
        } else {
          p.skillCharges[k] = math.max(0, p.skillCharges[k] - 1);
          if (p.skillCd[k] <= 0) p.skillCd[k] = cd;
        }
      }
      if (!replay) events.add({'e': 'skill', 'p': p.id, 'k': key.index, 'id': p.character.info.skill(key).id});
    }
    if (replay) events.removeWhere((e) => e['e'] == 'blink');
  }

  void _tickSkills(Player p, double dt) {
    for (final (key, _) in _skillButtons) {
      final k = skillSlot(key);
      if (k < 0) continue;
      final (_, maxC, cd) = skillSpec(p, key);
      if (p.skillCharges[k] >= maxC) {
        p.skillCd[k] = 0;
        continue;
      }
      p.skillCd[k] -= dt;
      if (p.skillCd[k] <= 0) {
        p.skillCharges[k]++;
        p.skillCd[k] = p.skillCharges[k] < maxC ? cd : 0;
      }
    }
    if (p.revealed > 0) p.revealed = math.max(0, p.revealed - dt);
    if (authoritative) {
      // Passive ult charge on top of damage/objective.
      if (phase == Phase.live) p.ult += 3 * dt;
      if (p.history.isEmpty || time - p.history.last[0] >= 0.1) {
        p.history.add([time, p.pos.x, p.pos.y, p.pos.z, p.hp]);
        while (p.history.length > 40) {
          p.history.removeAt(0);
        }
      }
    }
  }

  Projectile addProjectile(Player owner, String kind, Vec3 pos, Vec3 vel, {double life = 6, double gravity = 0}) {
    final pj = Projectile(_nextProj++, owner.id, owner.team, kind, pos, vel, life, gravity: gravity);
    projectiles.add(pj);
    return pj;
  }

  // ------------------------------------------------------------ weapons --
  double spreadFor(Player p) {
    final s = p.gun.stats;
    // Moving ruins accuracy: spread grows with speed (walking/crouching keep
    // it small, running is wild). Aiming down sights barely helps on the move.
    final moveFactor = clampD((p.vel.lengthXZ - 0.4) / 4.6, 0, 1);
    var base = s.spread;
    var move = s.moveSpread * moveFactor * moveFactor.clamp(0.5, 1.0);
    if (p.ads) {
      base *= s.adsSpreadMult * p.adsT + (1 - p.adsT);
      move *= 0.85;
    }
    var out = base + move;
    if (!p.onGround) out += s.airSpread;
    if (p.crouch) out *= 0.85;
    return out;
  }

  void _weapon(Player p, PlayerInput inp, int pressed, double dt, bool predict, bool replay) {
    final g = p.gun;
    final s = g.stats;
    p.sinceShot += dt;
    if (p.fireCooldown > 0) p.fireCooldown -= dt;
    if (p.drawTimer > 0) p.drawTimer -= dt;
    if (p.sinceShot > 1 / s.fireRate + 0.06) p.recoilIndex = math.max(0, p.recoilIndex - dt * 14);

    if (p.reloadTimer > 0) {
      p.reloadTimer -= dt;
      if (p.reloadTimer <= 0) {
        final take = math.min(s.mag - p.mag, p.reserve);
        p.mag = p.mag + take;
        p.reserve = p.reserve - take;
        p.reloadTimer = 0;
      }
    } else if (p.mag < s.mag &&
        p.reserve > 0 &&
        p.drawTimer <= 0 &&
        (pressed & Btn.reload != 0 || (inp.has(Btn.fire) && p.mag == 0 && p.fireCooldown <= 0))) {
      p.reloadTimer = s.reloadTime;
      if (!replay) events.add({'e': 'reload', 'p': p.id});
    }

    // Reload/draw cancels ADS (brief §5).
    p.ads = inp.has(Btn.ads) && p.reloadTimer <= 0 && p.drawTimer <= 0;
    final rate = dt / s.adsTime;
    p.adsT = clampD(p.adsT + (p.ads ? rate : -rate), 0, 1);

    // Skill weapon modes (shuriken, twin blades) replace the gun; rolling,
    // guarding, sleeping and stunned players can't shoot.
    // No shooting from inside your own spawn room.
    if (map.inSpawnRoom(p.team, p.pos)) return;
    if (p.mode.isNotEmpty) {
      final impl = modeImpl(p);
      if (impl != null && impl.modeFire(this, p, inp, pressed, dt, predict: predict, replay: replay)) return;
    }
    if (disabled(p) || p.mode == 'roll' || p.mode == 'guard') return;
    final wantFire = inp.has(Btn.fire) && (s.auto || pressed & Btn.fire != 0);
    if (wantFire && phase == Phase.live && p.fireCooldown <= 0 && p.drawTimer <= 0 && p.reloadTimer <= 0 && p.mag > 0) {
      final rateMul = has(p, 'haste') ? 1.25 : 1.0;
      p.fireCooldown = (p.fireCooldown > -dt ? p.fireCooldown : 0) + 1 / (s.fireRate * rateMul);
      _fire(p, g, inp.renderTick, predict, replay);
      p.mag = p.mag - 1;
      p.recoilIndex += 1;
      p.sinceShot = 0;
      p.shotSeq++;
    }
  }

  void _fire(Player p, GunDef g, double renderTick, bool predict, bool replay) {
    final s = g.stats;
    final spread = spreadFor(p);
    var (rp, ry) = g.recoilAt(p.recoilIndex);
    if (p.ads) {
      rp *= s.adsRecoilMult;
      ry *= s.adsRecoilMult;
    }
    final rr = Rng(p.id * 100003 + p.shotSeq * 7919);
    final origin = p.eye;

    if (s.isProjectile) {
      final dir = _coneDir(p.yaw + ry, p.pitch + rp, spread, rr);
      if (!replay) events.add({'e': 'shot', 's': p.id, 'g': g.id, 'o': origin.toList(2), 'd': dir.toList(3)});
      if (!predict && authoritative) {
        projectiles.add(Projectile(_nextProj++, p.id, p.team, g.id, origin + dir * 0.6, dir * s.projectileSpeed, 6));
      }
      return;
    }

    final dmgBy = <int, double>{};
    final headBy = <int, bool>{};
    final depDmg = <int, double>{};
    final ends = <List<double>>[];
    for (var k = 0; k < s.pellets; k++) {
      final dir = _coneDir(p.yaw + ry, p.pitch + rp, spread, rr);
      final hit = traceShot(p, origin, dir, s.range, renderTick);
      final end = origin + dir * hit.dist;
      ends.add([...end.toList(2), hit.victim != null ? (hit.part == HitPart.head ? 2 : 1) : (hit.wall ? 0 : -1)]);
      final v = hit.victim;
      if (v != null) {
        dmgBy[v.id] = (dmgBy[v.id] ?? 0) + g.damageAt(hit.part, hit.dist);
        if (hit.part == HitPart.head) headBy[v.id] = true;
      } else if (hit.dep != null) {
        depDmg[hit.dep!] = (depDmg[hit.dep!] ?? 0) + g.damageAt(HitPart.body, hit.dist);
      }
    }
    if (!predict && authoritative) {
      for (final e in depDmg.entries) {
        damageDeployable(e.key, e.value, p);
      }
    }
    if (!replay) events.add({'e': 'shot', 's': p.id, 'g': g.id, 'o': origin.toList(2), 'h': ends});
    if (!predict && authoritative) {
      for (final e in dmgBy.entries) {
        final v = players[e.key];
        if (v != null) applyDamage(v, e.value, p, g.id, headBy[e.key] ?? false);
      }
    }
  }

  Vec3 _coneDir(double yaw, double pitch, double spread, Rng rr) {
    final a = rr.nextDouble() * math.pi * 2;
    final rad = math.sqrt(rr.nextDouble()) * spread;
    return dirFromAngles(yaw + math.cos(a) * rad, pitch + math.sin(a) * rad);
  }

  /// First thing a bullet from [shooter] hits: enemy hitbox or world.
  ShotHit traceShot(Player shooter, Vec3 o, Vec3 d, double range, double renderTick) {
    final w = map.world.raycast(o, d, range);
    var best = w?.$1 ?? range;
    final hit = ShotHit(best, w != null);
    if (w != null && w.$2.name.startsWith('dp:')) hit.dep = int.tryParse(w.$2.name.substring(3));
    // Domes stop bullets crossing their shell (in or out).
    for (final dp in deployables) {
      final dome = skillImpls[dp.kind]?.domeRadius(dp) ?? 0;
      if (dome <= 0) continue;
      final inside = o.distanceTo(dp.pos) < dome;
      double? t;
      if (inside) {
        // Exit point of the sphere.
        final oc = o - dp.pos;
        final b = oc.dot(d), c = oc.lengthSq - dome * dome;
        t = -b + math.sqrt(math.max(0, b * b - c));
      } else {
        t = raySphere(o, d, dp.pos, dome, best);
      }
      if (t != null && t < best) {
        best = t;
        hit
          ..dist = t
          ..wall = true
          ..dep = dp.id;
      }
    }
    for (final q in players.values) {
      if (q.id == shooter.id || !q.alive || q.team == shooter.team) continue;
      final h = _positionAt(q, renderTick);
      final r = rayHitboxes(q.body, h[0], h[1], h[2], h[3] > 0.5, o, d, best);
      if (r != null && r.$1 < best) {
        best = r.$1;
        hit
          ..dist = r.$1
          ..victim = q
          ..part = r.$2
          ..wall = false
          ..dep = null;
      }
    }
    return hit;
  }

  /// Ray vs one player's hitboxes (head sphere, torso capsule, legs capsule
  /// built from the character's bones). Returns (distance, part) or null.
  static (double, HitPart)? rayHitboxes(
      Body b, double x, double y, double z, bool crouch, Vec3 o, Vec3 d, double maxDist) {
    final k = crouch ? crouchScale : 1.0;
    (double, HitPart)? best;
    final th = raySphere(o, d, Vec3(x, y + b.headCenter * k, z), b.headR, maxDist);
    if (th != null) best = (th, HitPart.head);
    final tb = rayCapsule(o, d, x, y + b.hips * k, y + (b.neck - b.torsoR * 0.6) * k, z, b.torsoR, best?.$1 ?? maxDist);
    if (tb != null && (best == null || tb < best.$1)) best = (tb, HitPart.body);
    final tl = rayCapsule(o, d, x, y + b.legR, y + b.hips * k - b.legR * 0.5, z, b.legR, best?.$1 ?? maxDist);
    if (tl != null && (best == null || tl < best.$1)) best = (tl, HitPart.legs);
    return best;
  }

  List<double> _positionAt(Player q, double renderTick) {
    if (authoritative && renderTick >= 0) {
      final rt = clampD(renderTick, tick - 20.0, tick.toDouble());
      final t0 = rt.floor(), t1 = t0 + 1;
      final h0 = _history[t0]?[q.id];
      final h1 = _history[t1]?[q.id] ?? h0;
      if (h0 != null && h1 != null) {
        final f = rt - t0;
        return [
          h0[0] + (h1[0] - h0[0]) * f,
          h0[1] + (h1[1] - h0[1]) * f,
          h0[2] + (h1[2] - h0[2]) * f,
          f < 0.5 ? h0[3] : h1[3],
        ];
      }
    }
    return [q.pos.x, q.pos.y, q.pos.z, q.crouch ? 1 : 0];
  }

  // ------------------------------------------------------------- damage --
  void applyDamage(Player victim, double amount, Player? attacker, String? weapon, bool head) {
    if (!victim.alive || amount <= 0 || phase == Phase.ended) return;
    if (attacker != null && attacker.team == victim.team && attacker.id != victim.id) return;
    if (victim.spawnProtect > 0 && attacker != null) return;
    if (has(victim, 'invuln')) return;
    if (attacker != null && attacker.id != victim.id) {
      // Role profile: attacker's damage (+ controller skill power), victim's armour.
      final ra = attacker.character.stats;
      amount *= ra.damageDealt * attacker.character.damageMul;
      if (weapon != null && !isGun(weapon)) amount *= ra.skillPower;
      amount *= victim.character.stats.damageTaken;
      if (has(attacker, 'amp')) amount *= 1 + (attacker.fx['ampMul'] ?? 0);
      // Mode reactions (spike guard, deflect) on the victim.
      final mi = modeImpl(victim);
      if (mi != null) amount = mi.modeDamaged(this, victim, attacker, amount, weapon ?? '');
    }
    if (has(victim, 'vuln')) amount *= 1 + (victim.fx['vulnMul'] ?? 0);
    if (has(victim, 'prot')) amount *= 1 - (victim.fx['protMul'] ?? 0);
    if (victim.mode == 'roll') amount *= 1 - CrateRoll.damageReduction;
    if (amount <= 0) return;
    // Shields soak first.
    final sh = victim.fx['shield'] ?? 0;
    if (sh > 0) {
      final soak = math.min(sh, amount);
      victim.fx['shield'] = sh - soak;
      amount -= soak;
      if (amount <= 0) {
        if (attacker != null && attacker.id != victim.id) {
          events.add({'e': 'hit', 's': attacker.id, 'v': victim.id, 'a': r(soak, 1), 'h': head, 'sh': 1, 'w': weapon});
        }
        return;
      }
    }
    victim.fx.remove('sleep');
    var dealt = math.min(amount, victim.hp);
    if (has(victim, 'undying')) dealt = math.min(dealt, math.max(0, victim.hp - 1));
    victim.hp -= dealt;
    victim.sinceDamaged = 0;
    if (attacker != null && attacker.id != victim.id) {
      victim.damageFrom[attacker.id] = (victim.damageFrom[attacker.id] ?? 0) + dealt;
      victim.lastAttacker = attacker.id;
      attacker.damageDealt += dealt;
      attacker.ult += dealt;
      events.add({'e': 'hit', 's': attacker.id, 'v': victim.id, 'a': r(dealt, 1), 'h': head, 'w': weapon});
    }
    if (victim.hp <= 0.001) _kill(victim, attacker, weapon, head);
  }

  void _kill(Player victim, Player? killer, String? weapon, bool head) {
    if (killer != null && killer.id != victim.id) {
      for (final sk in killer.character.info.skills) {
        skillImpls[sk.id]?.onKill(this, killer, victim);
      }
    }
    for (final d in [...deployables]) {
      if (d.owner == victim.id && (skillImpls[d.kind]?.diesWithOwner ?? false)) removeDeployable(d, destroyed: true);
    }
    victim.fx.clear();
    victim.mode = '';
    for (final q in players.values) {
      if (q.fx['linkTo'] == victim.id) {
        q.fx.remove('linkTo');
      }
    }
    victim.hp = 0;
    victim.alive = false;
    victim.deaths++;
    victim.respawnIn = cfg.respawnTime;
    victim.vel.set(0, 0, 0);
    victim.credits = math.min(Economy.max, victim.credits + Economy.death);
    if (Economy.losePrimaryOnDeath && victim.primary != null) {
      victim.primary = null;
      victim.slot = 1;
    }
    final k = killer != null && killer.id != victim.id ? killer : null;
    if (k != null) {
      k.kills++;
      if (head) k.headshots++;
      k.credits = math.min(Economy.max, k.credits + Economy.kill);
    }
    final assisters = <int>[];
    for (final e in victim.damageFrom.entries) {
      if (e.key == k?.id || e.value < 30) continue;
      final a = players[e.key];
      if (a == null) continue;
      a.assists++;
      a.credits = math.min(Economy.max, a.credits + Economy.assist);
      assisters.add(a.id);
    }
    events.add({
      'e': 'kill',
      'k': k?.id,
      'v': victim.id,
      'w': weapon,
      'h': head,
      'a': assisters,
      // Client fx (brief §2-11): victim sees a random cat/dog ghost; killer
      // gets a small badge at bottom centre.
      'fx': rng.nextDouble() < 0.5 ? 'death_cat' : 'death_dog',
      'badge': head ? 'kill_headshot' : 'kill_paw',
    });
  }

  // ------------------------------------------------------------- update --
  void update(double dt) {
    tick++;
    time += dt;
    phaseTime += dt;
    if (authoritative && phase == Phase.pregame && phaseTime >= cfg.pregame) {
      phase = Phase.live;
      phaseTime = 0;
      events.add({'e': 'live'});
    }

    if (authoritative) {
      for (final e in bots.entries) {
        final p = players[e.key];
        if (p == null) continue;
        final inp = e.value.think(this, p, dt);
        processInput(p, inp);
      }
    }

    for (final p in players.values) {
      if (!p.alive) {
        if (authoritative && phase != Phase.ended) {
          p.respawnIn -= dt;
          if (p.respawnIn <= 0) _spawn(p);
        }
        continue;
      }
      p.sinceDamaged += dt;
      _tickSkills(p, dt);
      _tickFx(p, dt);
      if (p.spawnProtect > 0) {
        p.spawnProtect -= dt;
        if (!map.inSpawnRoom(p.team, p.pos)) p.spawnProtect = 0;
      }
      if (!authoritative) continue;
      if (map.inSpawnRoom(p.team, p.pos) && p.hp < p.maxHp) heal(p, cfg.spawnRegen * dt, null);
      if (p.pos.y < map.killY) {
        final a = p.lastAttacker != null && p.sinceDamaged < 6 ? players[p.lastAttacker] : null;
        _kill(p, a, a == null ? 'fall' : 'fall_assist', false);
        continue;
      }
      if (map.inSpawnRoom(1 - p.team, p.pos)) applyDamage(p, cfg.enemySpawnDps * dt, null, 'spawn', false);
      if (p.alive && mover.stuck(p, dt)) _unstick(p);
    }

    if (authoritative) {
      _updateProjectiles(dt);
      _updateDeployables(dt);
      if (phase == Phase.live) _updateCapture(dt);
    }
    _recordHistory();
  }

  void _unstick(Player p) {
    final safe = nav.nearest(p.pos);
    if (safe != null) {
      p.pos.setFrom(safe);
    } else {
      final s = spawnPoints[p.team].first;
      p.pos.setFrom(s.pos);
    }
    p.vel.set(0, 0, 0);
    mover.placeOnGround(p);
    p.stuckTime = 0;
    events.add({'e': 'unstuck', 'p': p.id});
  }

  void _updateCapture(double dt) {
    onPoint[0] = onPoint[1] = 0;
    for (final p in players.values) {
      if (p.alive && map.inCapture(p.pos)) {
        onPoint[p.team]++;
        p.captureTime += dt;
        p.ult += 5 * dt;
        p.creditFrac += Economy.capturePerSecond * dt;
        if (p.creditFrac >= 1) {
          final c = p.creditFrac.floor();
          p.credits = math.min(Economy.max, p.credits + c);
          p.creditFrac -= c;
        }
      }
    }
    final a = onPoint[0] > 0, b = onPoint[1] > 0;
    contested = a && b;
    final rate = dt / cfg.captureTime;
    if (a != b) {
      final t = a ? 0 : 1;
      final n = math.min(onPoint[t], 3);
      if (owner == t) {
        capProgress = math.max(0, capProgress - rate * 2);
        if (capProgress == 0) capTeam = -1;
      } else if (capTeam != -1 && capTeam != t) {
        capProgress -= rate * 2;
        if (capProgress <= 0) {
          capProgress = 0;
          capTeam = t;
        }
      } else {
        capTeam = t;
        capProgress += rate * (1 + 0.25 * (n - 1));
        if (capProgress >= 1) {
          owner = t;
          capTeam = -1;
          capProgress = 0;
          events.add({'e': 'captured', 't': t});
        }
      }
    } else if (!a && !b && capProgress > 0) {
      capProgress = math.max(0, capProgress - rate * 0.5);
      if (capProgress == 0) capTeam = -1;
    }

    if (owner >= 0 && !contested) {
      score[owner] += dt / cfg.holdToWin;
      // Overtime: can't win while enemies still stand on the point.
      if (score[owner] >= 1) {
        if (onPoint[1 - owner] > 0) {
          score[owner] = 0.999;
        } else {
          _end(owner, 'capture');
          return;
        }
      }
    }
    if (cfg.timeLimit > 0 && time - cfg.pregame >= cfg.timeLimit) {
      final enemyTaking = capTeam >= 0 && capTeam != owner && capProgress > 0;
      if (contested || enemyTaking) return; // overtime
      _end(score[0] == score[1] ? -1 : (score[0] > score[1] ? 0 : 1), 'time');
    }
  }

  void _end(int w, String reason) {
    winner = w;
    phase = Phase.ended;
    phaseTime = 0;
    events.add({'e': 'end', 'w': w, 'r': reason});
  }

  void _updateProjectiles(double dt) {
    for (final pj in [...projectiles]) {
      pj.life -= dt;
      final impl = skillImpls[pj.gun];
      if (pj.stuck) {
        final host = pj.stuckTo == null ? null : players[pj.stuckTo];
        if (host != null && host.alive && pj.offset != null) pj.pos.setFrom(host.pos + pj.offset!);
        pj.fuse -= dt;
        if (pj.fuse <= 0) {
          impl?.detonate(this, pj);
          projectiles.remove(pj);
        }
        continue;
      }
      pj.vel.y -= pj.gravity * dt;
      if (pj.steer) {
        final o = players[pj.owner];
        if (o != null && o.alive) {
          final speed = pj.vel.length;
          final want = o.viewDir;
          final cur = pj.vel * (1 / speed);
          final k = math.min(1.0, 3.0 * dt);
          pj.vel.setFrom((cur + (want - cur) * k).normalized() * speed);
        }
      }
      final step = pj.vel * dt;
      final len = step.length;
      final dir = step * (1 / len);
      final w = map.world.raycast(pj.pos, dir, len);
      var hitT = w?.$1;
      Player? direct;
      for (final q in players.values) {
        if (!q.alive || q.team == pj.team) continue;
        final t = rayCapsule(pj.pos, dir, q.pos.x, q.pos.y + 0.3, q.pos.y + q.height - 0.3, q.pos.z, 0.42, hitT ?? len);
        if (t != null && (hitT == null || t < hitT)) {
          hitT = t;
          direct = q;
        }
      }
      if (hitT != null || pj.life <= 0) {
        final at = pj.pos + dir * math.max(0, (hitT ?? len) - 0.05);
        if (impl != null) {
          if (impl.impact(this, pj, at, direct)) projectiles.remove(pj);
        } else {
          _explode(pj, at, direct);
          projectiles.remove(pj);
        }
      } else {
        pj.pos.setFrom(pj.pos + step);
      }
    }
  }

  void _explode(Projectile pj, Vec3 at, Player? direct) {
    final s = gunById(pj.gun).stats;
    final owner = players[pj.owner];
    if (direct != null) applyDamage(direct, s.damage, owner, pj.gun, false);
    splash(at, s.splashRadius, s.splashDamage, owner, pj.team, pj.gun, minFrac: 0.4, selfMult: s.selfDamageMult);
  }

  /// Area damage with line-of-sight and linear falloff to [minFrac] at the
  /// edge. Hurts enemies of [team] and the owner (x [selfMult]).
  void splash(Vec3 at, double radius, double damage, Player? owner, int team, String weapon,
      {double minFrac = 0.4, double selfMult = 0.5}) {
    events.add({'e': 'explode', 'g': weapon, 'p': at.toList(2), 'r': radius});
    for (final d in [...deployables]) {
      if (d.team != team && d.maxHp > 0 && d.pos.distanceTo(at) <= radius + 1) damageDeployable(d.id, damage * 0.6, owner);
    }
    for (final q in [...players.values]) {
      if (!q.alive) continue;
      final isSelf = q.id == owner?.id;
      if (!isSelf && q.team == team) continue;
      final c = Vec3(q.pos.x, q.pos.y + q.height * 0.5, q.pos.z);
      final d = c.distanceTo(at);
      if (d > radius) continue;
      if (!map.world.lineClear(at + (c - at).normalized() * 0.05, c)) continue;
      var dmg = damage * (1 - (1 - minFrac) * d / radius);
      if (isSelf) dmg *= selfMult;
      applyDamage(q, dmg, owner, weapon, false);
    }
  }

  void _recordHistory() {
    if (!authoritative) return;
    _history[tick] = {
      for (final p in players.values)
        if (p.alive) p.id: [p.pos.x, p.pos.y, p.pos.z, p.crouch ? 1 : 0],
    };
    _history.remove(tick - 32);
  }

  // ------------------------------------------------------------ queries --
  bool canSee(Player o, Vec3 target, {double fovCos = 0.3, double maxDist = 120}) {
    final eye = o.eye;
    final diff = target - eye;
    final dist = diff.length;
    if (dist > maxDist || dist < 1e-6) return dist < 1e-6;
    if (o.viewDir.dot(diff * (1 / dist)) < fovCos) return false;
    if (!map.world.lineClear(eye, target)) return false;
    return !smokeBlocks(eye, target);
  }

  /// True if a smoke cloud sits between [a] and [b].
  bool smokeBlocks(Vec3 a, Vec3 b) {
    final diff = b - a;
    final len = diff.length;
    if (len < 1e-6) return false;
    final d = diff * (1 / len);
    for (final dp in deployables) {
      final r = skillImpls[dp.kind]?.smokeRadius(dp) ?? 0;
      if (r > 0 && raySphere(a, d, dp.pos, r, len) != null) return true;
    }
    return false;
  }

  // ------------------------------------------------------ serialization --
  Map<String, Object?> snapshot() => {
        't': tick,
        'time': r(time, 3),
        'ph': phase.index,
        'pt': r(phaseTime, 3),
        'cap': [owner, capTeam, r(capProgress, 4), contested ? 1 : 0, r(score[0], 4), r(score[1], 4), ...onPoint],
        'w': winner,
        'p': [for (final p in players.values) p.toNet()],
        'pj': [for (final pj in projectiles) pj.toNet()],
        'dp': [for (final d in deployables) d.toNet()],
      };

  void applySnapshot(Map<String, dynamic> s) {
    tick = (s['t'] as num).toInt();
    time = (s['time'] as num).toDouble();
    phase = Phase.values[(s['ph'] as num).toInt()];
    phaseTime = (s['pt'] as num).toDouble();
    final c = s['cap'] as List;
    owner = (c[0] as num).toInt();
    capTeam = (c[1] as num).toInt();
    capProgress = (c[2] as num).toDouble();
    contested = c[3] == 1;
    score[0] = (c[4] as num).toDouble();
    score[1] = (c[5] as num).toDouble();
    onPoint[0] = (c[6] as num).toInt();
    onPoint[1] = (c[7] as num).toInt();
    winner = (s['w'] as num).toInt();
    final seen = <int>{};
    for (final row in s['p'] as List) {
      final l = row as List;
      final id = (l[0] as num).toInt();
      seen.add(id);
      final p = players[id];
      if (p == null) {
        players[id] = Player.fromNet(l);
      } else {
        p.applyNet(l);
      }
    }
    players.removeWhere((id, _) => !seen.contains(id));
    projectiles
      ..clear()
      ..addAll([for (final row in (s['pj'] as List? ?? const [])) Projectile.fromNet(row as List)]);
    _syncDeployables([for (final row in (s['dp'] as List? ?? const [])) Deployable.fromNet(row as List)]);
  }
}

extension SimEffects on GameSim {
  bool has(Player p, String k) => (p.fx[k] ?? 0) > 0;
  bool disabled(Player p) => has(p, 'sleep') || has(p, 'stun');
  bool rooted(Player p) => disabled(p) || has(p, 'root');

  /// Movement speed multiplier from effects and modes.
  double moveMult(Player p) {
    var m = 1.0;
    if (has(p, 'slow')) m *= p.fx['slowMul'] ?? 0.6;
    if (has(p, 'haste')) m *= 1.25;
    m *= switch (p.mode) { 'roll' => CrateRoll.speedMult, 'twin' => 1.25, 'guard' => 0.6, _ => 1.0 };
    return m;
  }

  /// Applies/refreshes a timed effect; [vals] ride along (kept at the max).
  void addFx(Player p, String key, double seconds, [Map<String, double> vals = const {}]) {
    if (!p.alive) return;
    final fresh = !p.fx.containsKey(key);
    p.fx[key] = math.max(p.fx[key] ?? 0, seconds);
    for (final e in vals.entries) {
      final cur = p.fx[e.key];
      // Slows: the strongest (lowest multiplier) wins; buffs: the highest.
      p.fx[e.key] = cur == null || fresh
          ? e.value
          : (e.key == 'slowMul' ? math.min(cur, e.value) : math.max(cur, e.value));
    }
  }

  /// Removes harmful effects (cleanse).
  void cleanse(Player p) {
    for (final k in const ['slow', 'slowMul', 'root', 'sleep', 'stun', 'vuln', 'vulnMul', 'antiheal']) {
      p.fx.remove(k);
    }
  }

  void heal(Player target, double amount, Player? healer) {
    if (!target.alive || amount <= 0) return;
    if (has(target, 'antiheal')) return;
    if (has(target, 'healboost')) amount *= 1.5;
    if (healer != null) amount *= healer.character.stats.healPower;
    final got = math.min(amount, target.maxHp - target.hp);
    if (got <= 0) return;
    target.hp += got;
    if (healer != null) {
      healer.ult += got;
      healer.fx['healed'] = (healer.fx['healed'] ?? 0) + got;
    }
  }

  void setMode(Player p, String mode, double seconds, SkillKey key) {
    p.mode = mode;
    p.fx['modeT'] = seconds;
    p.fx['modeKey'] = key.index.toDouble();
  }

  void endMode(Player p) {
    final impl = modeImpl(p);
    p.mode = '';
    p.fx.remove('modeT');
    p.fx.remove('modeAmmo');
    impl?.modeEnded(this, p);
    p.fx.remove('modeKey');
  }

  SkillImpl? modeImpl(Player p) {
    final k = p.fx['modeKey'];
    if (p.mode.isEmpty || k == null) return null;
    return skillImpls[p.character.info.skill(SkillKey.values[k.toInt()]).id];
  }

  /// Puts skill slot [key] on cooldown now (charges emptied).
  void startCooldown(Player p, SkillKey key, double seconds) {
    final k = skillSlot(key);
    if (k < 0) return;
    p.skillCharges[k] = 0;
    p.skillCd[k] = seconds;
  }

  void dash(Player p, double vx, double vz, double seconds, SkillKey key) {
    p.fx['dash'] = seconds;
    p.fx['dashVx'] = vx;
    p.fx['dashVz'] = vz;
    p.fx['dashKey'] = key.index.toDouble();
  }

  void leap(Player p, double up, double vx, double vz, SkillKey key) {
    p.vel.set(vx, up, vz);
    p.onGround = false;
    p.fx['leap'] = 3;
    p.fx['leapAge'] = 0;
    p.fx['leapKey'] = key.index.toDouble();
  }

  static const _timers = {
    'slow': ['slowMul'],
    'root': <String>[],
    'sleep': <String>[],
    'stun': <String>[],
    'amp': ['ampMul'],
    'vuln': ['vulnMul'],
    'prot': ['protMul'],
    'haste': <String>[],
    'shieldT': ['shield'],
    'invuln': <String>[],
    'undying': <String>[],
    'antiheal': <String>[],
    'healboost': <String>[],
    'hot': ['hotRate'],
    'dash': ['dashVx', 'dashVz', 'dashKey', 'dashHit'],
    'marked': <String>[],
  };

  void _tickFx(Player p, double dt) {
    for (final e in _timers.entries) {
      final v = p.fx[e.key];
      if (v == null) continue;
      if (v - dt <= 0) {
        p.fx.remove(e.key);
        if (e.key == 'dash') _dashEnded(p);
        for (final k in e.value) {
          p.fx.remove(k);
        }
      } else {
        p.fx[e.key] = v - dt;
      }
    }
    if (p.fx.containsKey('modeT')) {
      p.fx['modeT'] = p.fx['modeT']! - dt;
      if (p.fx['modeT']! <= 0) endMode(p);
    }
    if (has(p, 'dash')) {
      final k = p.fx['dashKey'];
      if (k != null) skillImpls[p.character.info.skill(SkillKey.values[k.toInt()]).id]?.dashTick(this, p, dt);
    }
    final leapT = p.fx['leap'];
    if (leapT != null) {
      final age = (p.fx['leapAge'] ?? 0) + dt;
      p.fx['leapAge'] = age;
      if ((p.onGround && age > 0.15) || age > 3) {
        final k = p.fx['leapKey'];
        p.fx.remove('leap');
        p.fx.remove('leapAge');
        p.fx.remove('leapKey');
        if (k != null && authoritative) skillImpls[p.character.info.skill(SkillKey.values[k.toInt()]).id]?.landed(this, p);
      }
    }
    if (!authoritative) return;
    if (has(p, 'hot')) heal(p, (p.fx['hotRate'] ?? 0) * dt, null);
    // Beam-style heals (tether, mend crystal).
    final link = p.fx['linkTo'];
    if (link != null) {
      final t = players[link.toInt()];
      final range = p.fx['linkRange'] ?? 30;
      if (t == null || !t.alive || t.pos.distanceTo(p.pos) > range ||
          ((p.fx['linkLos'] ?? 1) > 0 && !map.world.lineClear(p.eye, t.eye))) {
        if ((p.fx['linkSticky'] ?? 0) == 0) p.fx.remove('linkTo');
      } else {
        heal(t, (p.fx['linkRate'] ?? 0) * dt, p);
      }
    }
  }

  void _dashEnded(Player p) {
    final k = p.fx['dashKey'];
    if (k == null) return;
    p.vel.x *= 0.3;
    p.vel.z *= 0.3;
    if (authoritative) skillImpls[p.character.info.skill(SkillKey.values[k.toInt()]).id]?.dashEnded(this, p);
  }

  // ------------------------------------------------------- deployables --
  Deployable deploy(Player owner, String kind, Vec3 pos,
      {double yaw = 0, double hp = 0, double life = 10, double radius = 0}) {
    final d = Deployable(_nextDep++, owner.id, owner.team, kind, pos, yaw: yaw, hp: hp, life: life, radius: radius);
    deployables.add(d);
    _attachCollider(d);
    events.add({'e': 'deploy', 'id': d.id, 'k': kind, 'p': pos.toList(2), 't': owner.team});
    return d;
  }

  void _attachCollider(Deployable d) {
    final obb = skillImpls[d.kind]?.collider(d);
    if (obb != null) d.collider = map.world.addDynamic(obb);
  }

  void removeDeployable(Deployable d, {bool destroyed = false}) {
    if (!deployables.remove(d)) return;
    if (d.collider != null) map.world.removeDynamic(d.collider!);
    if (authoritative) skillImpls[d.kind]?.removed(this, d, destroyed: destroyed);
    events.add({'e': 'undeploy', 'id': d.id, 'k': d.kind, 'p': d.pos.toList(2), 'x': destroyed});
  }

  void damageDeployable(int id, double amount, Player? attacker) {
    final d = deployables.where((x) => x.id == id).firstOrNull;
    if (d == null || d.maxHp <= 0) return;
    if (attacker != null && attacker.team == d.team) return;
    d.hp -= amount;
    if (d.hp <= 0) removeDeployable(d, destroyed: true);
  }

  Iterable<Deployable> deployablesOf(Player p, String kind) =>
      deployables.where((d) => d.owner == p.id && d.kind == kind);

  void _updateDeployables(double dt) {
    for (final d in [...deployables]) {
      d.age += dt;
      d.life -= dt;
      skillImpls[d.kind]?.tickDeployable(this, d, dt);
      if (!d.alive && deployables.contains(d)) removeDeployable(d, destroyed: d.maxHp > 0 && d.hp <= 0);
    }
  }

  /// Client: mirror the server's deployables (and their colliders, so
  /// predicted movement collides with barriers too).
  void _syncDeployables(List<Deployable> incoming) {
    final byId = {for (final d in deployables) d.id: d};
    final keep = <int>{};
    for (final n in incoming) {
      keep.add(n.id);
      final cur = byId[n.id];
      if (cur == null) {
        deployables.add(n);
        _attachCollider(n);
      } else {
        cur
          ..hp = n.hp
          ..maxHp = n.maxHp
          ..life = n.life
          ..radius = n.radius
          ..yaw = n.yaw
          ..pos.setFrom(n.pos);
      }
    }
    for (final d in [...deployables]) {
      if (!keep.contains(d.id)) {
        deployables.remove(d);
        if (d.collider != null) map.world.removeDynamic(d.collider!);
      }
    }
  }

  // ------------------------------------------------------ aim helpers --
  /// Where the player's crosshair meets the world within [maxDist] (or the
  /// end of the ray), dropped to the ground if [ground].
  Vec3 aimPoint(Player p, double maxDist, {bool ground = true}) {
    final e = p.eye, d = p.viewDir;
    final h = map.world.raycast(e, d, maxDist);
    var at = e + d * ((h?.$1 ?? maxDist) - 0.1);
    if (ground) {
      final g = map.world.groundBelow(at.x, at.z, at.y + 0.5, maxDrop: 30);
      if (g != null) at = Vec3(at.x, g, at.z);
    }
    return at;
  }

  /// Ally (or enemy) closest to the crosshair within [maxDist] and line of
  /// sight; [self] falls back to the player itself for ally targeting.
  Player? targetInSight(Player p, double maxDist, {required bool ally, bool self = false, double cone = 0.2}) {
    Player? best;
    var bestA = cone;
    for (final q in players.values) {
      if (!q.alive || q.id == p.id || (q.team == p.team) != ally) continue;
      final c = Vec3(q.pos.x, q.pos.y + 1.1, q.pos.z);
      final diff = c - p.eye;
      final dist = diff.length;
      if (dist > maxDist) continue;
      final a = math.acos(clampD(p.viewDir.dot(diff * (1 / dist)), -1, 1));
      if (a < bestA && map.world.lineClear(p.eye, c)) {
        bestA = a;
        best = q;
      }
    }
    return best ?? (self ? p : null);
  }

  Iterable<Player> enemiesNear(int team, Vec3 at, double radius, {bool los = true}) => players.values.where((q) =>
      q.alive &&
      q.team != team &&
      Vec3(q.pos.x, q.pos.y + 1, q.pos.z).distanceTo(at) <= radius &&
      (!los || map.world.lineClear(Vec3(at.x, at.y + 0.4, at.z), Vec3(q.pos.x, q.pos.y + 1, q.pos.z))));

  Iterable<Player> alliesNear(int team, Vec3 at, double radius) =>
      players.values.where((q) => q.alive && q.team == team && q.pos.distanceTo(at) <= radius + 0.5);
}

class ShotHit {
  double dist;
  bool wall;
  int? dep;
  Player? victim;
  HitPart part = HitPart.body;
  ShotHit(this.dist, this.wall);
}

/// World collision is only exposed for tools/tests.
extension SimWorld on GameSim {
  CollisionWorld get world => map.world;
}
