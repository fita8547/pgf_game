import 'dart:math' as math;

import 'agents.dart';
import 'bot.dart';
import 'input.dart';
import 'map_data.dart';
import 'math.dart';
import 'player.dart';
import 'weapons.dart';

enum Phase { warmup, buy, live, planted, roundEnd, matchEnd }

enum CoreState { carried, dropped, planted, defused, detonated }

class SimConfig {
  final int teamSize;
  final int winRounds;
  final double buyTime, roundTime, coreTime, roundEndTime, warmupTime;
  final double plantTime, defuseTime;

  /// 0 (easy) .. 1 (hard)
  final double botSkill;
  const SimConfig({
    this.teamSize = 5,
    this.winRounds = 7,
    this.buyTime = 15,
    this.roundTime = 100,
    this.coreTime = 40,
    this.roundEndTime = 5,
    this.warmupTime = 4,
    this.plantTime = 4,
    this.defuseTime = 7,
    this.botSkill = 0.5,
  });
  int get halfRounds => winRounds - 1;
}

class Smoke {
  final Vec3 pos;
  final double radius;
  double life;
  final int team;
  Smoke(this.pos, this.radius, this.life, this.team);
}

class Barrier {
  final Aabb box;
  double life;
  Barrier(this.box, this.life);
}

class Projectile {
  final int owner;
  final AbilityKind kind;
  final Vec3 pos, vel;
  double fuse;
  Projectile(this.owner, this.kind, this.pos, this.vel, this.fuse);
}

typedef GameEvent = Map<String, Object?>;

/// The complete game state and rules. Runs authoritatively on the server (or
/// locally for offline play). The client keeps a non-authoritative mirror
/// that is overwritten by snapshots and used for prediction.
class GameSim {
  final SimConfig cfg;
  final GameMap map;
  final bool authoritative;
  final Rng rng;

  final Map<int, Player> players = {};
  final Map<int, BotBrain> brains = {};
  final List<Smoke> smokes = [];
  final List<Barrier> barriers = [];
  final List<Projectile> projectiles = [];
  final List<GameEvent> events = [];

  Phase phase = Phase.warmup;
  double phaseTimer;
  int tick = 0;
  double time = 0;
  int round = 0, half = 0;
  final List<int> scores = [0, 0];
  final List<int> lossStreak = [0, 0];

  CoreState coreState = CoreState.carried;
  int? coreCarrier;
  final Vec3 corePos = Vec3.zero();
  double defuseProgress = 0;
  int? defuserId;
  String? coreSite;
  int? matchWinner;
  int lastRoundWinner = -1;
  String lastRoundReason = '';
  int attackSiteIndex = 0;

  final Map<int, Map<int, List<double>>> _history = {};
  final Map<int, bool> _useHeld = {};
  int _nextId = 1;

  GameSim({this.cfg = const SimConfig(), GameMap? map, this.authoritative = true, int seed = 1337})
      : map = map ?? buildDunewall(),
        rng = Rng(seed),
        phaseTimer = cfg.warmupTime;

  // ---------------------------------------------------------------- teams --
  int get attackTeam => half == 0 ? 0 : 1;
  int get defenseTeam => 1 - attackTeam;
  bool isAttacker(Player p) => p.team == attackTeam;
  Iterable<Player> teamOf(int t) => players.values.where((p) => p.team == t);
  int aliveCount(int t) => players.values.where((p) => p.team == t && p.alive).length;
  Player? get carrier => coreCarrier == null ? null : players[coreCarrier];

  bool get shootingAllowed =>
      phase == Phase.live || phase == Phase.planted || phase == Phase.roundEnd;

  // -------------------------------------------------------------- roster --
  Player addPlayer(String name,
      {int? team, AgentId? agent, bool isBot = false, int? accountId}) {
    team ??= teamOf(0).length <= teamOf(1).length ? 0 : 1;
    final id = _nextId++;
    final p = Player(id, name, team,
        agent ?? AgentId.values[rng.nextInt() % AgentId.values.length],
        isBot: isBot, accountId: accountId);
    p.refillAmmo();
    players[id] = p;
    if (isBot) brains[id] = BotBrain(id, cfg.botSkill, rng.nextInt());
    if (phase == Phase.warmup || phase == Phase.buy) {
      _spawn(p);
      p.eCharges = p.agentDef.e.freeCharges;
    } else {
      p.alive = false; // joins next round
    }
    return p;
  }

  /// Fill both teams to [cfg.teamSize] with bots.
  void fillBots() {
    const botNames = ['Kestrel', 'Bastion', 'Morrow', 'Tundra', 'Quill', 'Ember', 'Lux', 'Rook', 'Sable', 'Cinder'];
    var n = 0;
    for (var t = 0; t < 2; t++) {
      while (teamOf(t).length < cfg.teamSize) {
        addPlayer('${botNames[(n++ + players.length) % botNames.length]} [BOT]', team: t, isBot: true);
      }
    }
  }

  /// A human takes over a bot slot (online join). Returns the player.
  Player joinHuman(String name, AgentId agent, int? accountId) {
    int humans(int t) => teamOf(t).where((p) => !p.isBot).length;
    final team = humans(0) <= humans(1) ? 0 : 1;
    final bot = teamOf(team).where((p) => p.isBot).firstOrNull ??
        teamOf(1 - team).where((p) => p.isBot).firstOrNull;
    if (bot == null) return addPlayer(name, team: team, agent: agent, accountId: accountId);
    brains.remove(bot.id);
    bot
      ..isBot = false
      ..connected = true
      ..name = name
      ..agent = agent
      ..accountId = accountId
      ..kills = 0
      ..deaths = 0
      ..assists = 0
      ..score = 0
      ..headshots = 0
      ..damage = 0
      ..lastSeq = 0;
    return bot;
  }

  /// A human disconnected: a bot takes over the slot.
  void humanToBot(int id) {
    final p = players[id];
    if (p == null) return;
    p
      ..isBot = true
      ..connected = false
      ..accountId = null
      ..name = '${p.name} [BOT]';
    brains[id] = BotBrain(id, cfg.botSkill, rng.nextInt());
  }

  void _spawn(Player p) {
    final attack = isAttacker(p);
    final spawns = attack ? map.attackSpawns : map.defenseSpawns;
    final mates = teamOf(p.team).toList()..sort((a, b) => a.id.compareTo(b.id));
    final idx = mates.indexOf(p);
    final base = spawns[idx % spawns.length];
    p.pos.set(base.x + (idx ~/ spawns.length) * 1.2, 0, base.z + (attack ? 1.5 : -1.5) * (idx ~/ spawns.length));
    p.vel.set(0, 0, 0);
    p.yaw = attack ? 0 : math.pi;
    p.pitch = 0;
    p.alive = true;
    p.hp = maxHp;
    p.onGround = true;
    p
      ..jumpCooldown = 0
      ..landPenalty = 0
      ..groundTime = 1
      ..hopChain = 0
      ..stuckTime = 0;
  }

  // -------------------------------------------------------------- rounds --
  void _startRound() {
    round++;
    if (round == cfg.halfRounds + 1) {
      half = 1;
      lossStreak
        ..[0] = 0
        ..[1] = 0;
      for (final p in players.values) {
        p
          ..credits = 800
          ..primary = null
          ..secondary = WeaponId.sidearm
          ..shield = 0
          ..survived = false
          ..qCharges = 0;
      }
      events.add({'e': 'half'});
    }
    for (final p in players.values) {
      if (!p.survived) {
        p.primary = null;
        p.shield = 0;
        p.secondary = p.survived ? p.secondary : WeaponId.sidearm;
      }
      _spawn(p);
      p
        ..refillAmmo()
        ..slot = p.primary != null ? 0 : 1
        ..flashTime = 0
        ..plantProgress = 0
        ..healLeft = 0
        ..revealTime = 0
        ..dashTime = 0
        ..reloadTimer = 0
        ..equipTimer = 0
        ..recoilIndex = 0
        ..fireCooldown = 0
        ..spottedMask = 0
        ..eCharges = p.agentDef.e.freeCharges
        ..eRecharge = 0;
      p.damageFrom.clear();
    }
    final atk = teamOf(attackTeam).toList();
    coreState = CoreState.carried;
    coreCarrier = atk.isEmpty ? null : atk[rng.nextInt() % atk.length].id;
    defuseProgress = 0;
    defuserId = null;
    coreSite = null;
    smokes.clear();
    barriers.clear();
    projectiles.clear();
    phase = Phase.buy;
    phaseTimer = cfg.buyTime;
    attackSiteIndex = rng.nextInt() % map.sites.length;
    for (final b in brains.values) {
      b.resetRound(this);
    }
    events.add({'e': 'roundStart', 'rd': round});
  }

  void _endRound(int winner, String reason) {
    if (phase == Phase.roundEnd || phase == Phase.matchEnd) return;
    scores[winner]++;
    lastRoundWinner = winner;
    lastRoundReason = reason;
    final loser = 1 - winner;
    for (final p in players.values) {
      final int gain = p.team == winner ? 3000 : 1900 + 500 * math.min(lossStreak[loser], 2);
      p.credits = math.min(9000, p.credits + gain);
      p.survived = p.alive;
      p.plantProgress = 0;
    }
    lossStreak[winner] = 0;
    lossStreak[loser]++;
    defuserId = null;
    phase = Phase.roundEnd;
    phaseTimer = cfg.roundEndTime;
    if (scores[winner] >= cfg.winRounds) matchWinner = winner;
    events.add({'e': 'round', 'w': winner, 'why': reason, 'sc': [scores[0], scores[1]]});
  }

  void _checkElims() {
    if (phase != Phase.live && phase != Phase.planted) return;
    final atk = aliveCount(attackTeam), def = aliveCount(defenseTeam);
    if (phase == Phase.live) {
      if (atk == 0) {
        _endRound(defenseTeam, 'elimination');
      } else if (def == 0) {
        _endRound(attackTeam, 'elimination');
      }
    } else if (def == 0) {
      _endRound(attackTeam, 'elimination');
    }
  }

  // ------------------------------------------------------------- buying --
  /// Returns null on success, or an error message.
  String? buy(Player p, String item) {
    if (phase != Phase.buy) return 'Buy phase is over';
    if (!p.alive) return 'Dead';
    if (item == 'light' || item == 'heavy') {
      final value = item == 'light' ? lightShieldValue : heavyShieldValue;
      final cost = item == 'light' ? lightShieldCost : heavyShieldCost;
      if (p.shield >= value) return 'Already equipped';
      if (p.credits < cost) return 'Not enough credits';
      p.credits -= cost;
      p.shield = value.toDouble();
      return null;
    }
    if (item == 'q') {
      final q = p.agentDef.q;
      if (q.cost <= 0) return 'Not purchasable';
      if (p.qCharges >= q.maxCharges) return 'Max charges';
      if (p.credits < q.cost) return 'Not enough credits';
      p.credits -= q.cost;
      p.qCharges++;
      return null;
    }
    final id = WeaponId.values.where((w) => w.name == item).firstOrNull;
    if (id == null || id == WeaponId.knife) return 'Unknown item';
    final def = weapons[id]!;
    if (p.credits < def.cost) return 'Not enough credits';
    if (def.slot == WeaponSlot.primary) {
      if (p.primary == id) return 'Already owned';
      p.credits -= def.cost;
      p.primary = id;
      p.primMag = def.mag;
      p.primRes = def.reserve;
      p.slot = 0;
    } else {
      if (p.secondary == id) return 'Already owned';
      p.credits -= def.cost;
      p.secondary = id;
      p.secMag = def.mag;
      p.secRes = def.reserve;
      p.slot = 1;
    }
    p.equipTimer = def.equipTime * 0.5;
    p.reloadTimer = 0;
    return null;
  }

  // -------------------------------------------------------------- input --
  /// Applies one input frame. [predict]: client-side prediction (no damage,
  /// no ability spawns). [replay]: re-simulation after reconciliation (also
  /// suppresses effect events).
  void processInput(Player p, PlayerInput inp, {bool predict = false, bool replay = false}) {
    // Never trust raw numbers: NaN/Infinity would poison the whole sim.
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
    if (!p.alive) {
      p.prevButtons = inp.buttons;
      _useHeld[p.id] = false;
      return;
    }
    p.yaw = wrapAngle(inp.yaw);
    p.pitch = clampD(inp.pitch, -1.5, 1.5);
    _useHeld[p.id] = inp.has(Btn.use);

    // weapon switching
    var newSlot = p.slot;
    if (pressed & Btn.slot1 != 0 && p.primary != null) newSlot = 0;
    if (pressed & Btn.slot2 != 0) newSlot = 1;
    if (pressed & Btn.slot3 != 0) newSlot = 2;
    if (p.slot == 0 && p.primary == null) newSlot = 1;
    if (newSlot != p.slot) {
      p.slot = newSlot;
      p.equipTimer = p.weapon.equipTime;
      p.reloadTimer = 0;
      p.ads = false;
      p.recoilIndex = 0;
    }

    _move(p, inp, pressed, dt);
    _weapon(p, inp, pressed, dt, predict, replay);

    if (!predict && authoritative) {
      if (pressed & Btn.abilityQ != 0) _useAbility(p, inp, true);
      if (pressed & Btn.abilityE != 0) _useAbility(p, inp, false);
    }
    p.prevButtons = inp.buttons;
  }

  bool _isFrozen(Player p) =>
      phase == Phase.warmup ||
      phase == Phase.buy ||
      phase == Phase.matchEnd ||
      p.plantProgress > 0 ||
      defuserId == p.id;

  // ----------------------------------------------------------- movement --
  static const double runSpeed = 5.6;
  static const double jumpSpeed = 7.0;
  static const double gravity = 20.0;
  static const double dashSpeed = 17.0;

  /// Ledges up to this height are climbed automatically (no snagging on lips).
  static const double stepHeight = 0.4;

  /// Anti bunny-hop: hops started within this window after landing chain.
  static const double hopWindow = 0.3;

  /// Horizontal speed kept per chained hop (0.8 => 80%, 64%, ...).
  static const double hopKeep = 0.8;

  /// Speed multiplier for a short time after landing.
  static const double landSlow = 0.7, landSlowTime = 0.18;

  void _move(Player p, PlayerInput inp, int pressed, double dt) {
    final frozen = _isFrozen(p);
    final wasGround = p.onGround;
    if (p.jumpCooldown > 0) p.jumpCooldown -= dt;
    if (p.landPenalty > 0) p.landPenalty -= dt;
    if (p.onGround) p.groundTime += dt;

    // Standing up needs headroom, otherwise stay crouched (no head-in-ceiling).
    final wantCrouch = inp.has(Btn.crouch);
    if (wantCrouch) {
      p.crouch = true;
    } else if (p.crouch && !_overlapsSolid(p.pos.x, p.pos.y, p.pos.z, standHeight)) {
      p.crouch = false;
    }
    p.walking = inp.has(Btn.walk);
    final baseSpeed = runSpeed * p.weapon.moveSpeedMult;
    var maxSpeed = baseSpeed;
    if (p.walking) maxSpeed *= 0.52;
    if (p.crouch) maxSpeed *= 0.42;
    if (p.ads) maxSpeed *= 0.8;
    if (p.landPenalty > 0) maxSpeed *= landSlow;
    if (frozen) maxSpeed = 0;

    final sy = math.sin(p.yaw), cy = math.cos(p.yaw);
    var wx = cy * inp.moveX + sy * inp.moveZ;
    var wz = sy * inp.moveX - cy * inp.moveZ;
    final wl = math.sqrt(wx * wx + wz * wz);
    if (wl > 1) {
      wx /= wl;
      wz /= wl;
    }

    if (p.dashTime > 0 && !frozen) {
      p.dashTime -= dt;
      p.vel.x = p.dashX * dashSpeed;
      p.vel.z = p.dashZ * dashSpeed;
    } else {
      final tx = wx * maxSpeed, tz = wz * maxSpeed;
      final accel = p.onGround ? (wl > 0.01 ? 52.0 : 40.0) : 7.0;
      final dx = tx - p.vel.x, dz = tz - p.vel.z;
      final dl = math.sqrt(dx * dx + dz * dz);
      final step = accel * dt;
      if (!p.onGround && wl < 0.01) {
        // keep momentum in the air
      } else if (dl <= step) {
        p.vel.x = tx;
        p.vel.z = tz;
      } else {
        p.vel.x += dx / dl * step;
        p.vel.z += dz / dl * step;
      }
    }

    // Anti bunny-hop / momentum abuse: outside a dash, horizontal speed can
    // never be gained in the air, and anything above the run cap (e.g. left
    // over from a dash) bleeds off quickly.
    if (p.dashTime <= 0) {
      final cap = baseSpeed * 1.02;
      final sp = p.vel.lengthXZ;
      if (sp > cap) {
        final ns = math.max(cap, sp - (p.onGround ? 60.0 : 14.0) * dt);
        p.vel.x *= ns / sp;
        p.vel.z *= ns / sp;
      }
    }

    // Jump only on a fresh press (holding the key does not auto-hop).
    if (pressed & Btn.jump != 0 && p.onGround && !frozen && !p.crouch && p.jumpCooldown <= 0) {
      if (p.groundTime < hopWindow) {
        p.hopChain = math.min(p.hopChain + 1, 5);
        final keep = math.pow(hopKeep, p.hopChain).toDouble();
        p.vel.x *= keep;
        p.vel.z *= keep;
      } else {
        p.hopChain = 0;
      }
      p.vel.y = jumpSpeed;
      p.onGround = false;
      p.jumpCooldown = 0.12;
    }
    p.vel.y = math.max(p.vel.y - gravity * dt, -40);

    // Sub-step so fast movement (dash, lag spikes) can't tunnel through thin
    // walls or barriers: no single step moves more than 0.25 m.
    final dx = p.vel.x * dt, dy = p.vel.y * dt, dz = p.vel.z * dt;
    final maxD = math.max(dx.abs(), math.max(dy.abs(), dz.abs()));
    final steps = (maxD / 0.25).ceil().clamp(1, 16);
    for (var i = 0; i < steps; i++) {
      _moveAxis(p, 0, dx / steps, wasGround);
      _moveAxis(p, 2, dz / steps, wasGround);
      p.onGround = false;
      _moveAxis(p, 1, dy / steps, wasGround);
    }

    if (!wasGround && p.onGround) {
      p.groundTime = 0;
      p.landPenalty = landSlowTime;
    }
    _unstick(p, dt);
  }

  /// True if a player box with feet at (x,y,z) and height [h] hits geometry.
  bool _overlapsSolid(double x, double y, double z, double h) {
    const r = playerRadius;
    for (final b in _solidBoxes) {
      if (b.overlaps(x - r, y, z - r, x + r, y + h, z + r)) return true;
    }
    return false;
  }

  /// Anti-stuck: push a player out of any geometry they ended up inside
  /// (barrier spawned on them, snapshot rounding, map seams), clamp them to
  /// the map, and as a last resort move them to the nearest walkable cell.
  void _unstick(Player p, double dt) {
    final b = map.bounds;
    const r = playerRadius;
    p.pos.x = clampD(p.pos.x, b.minX + r, b.maxX - r);
    p.pos.z = clampD(p.pos.z, b.minZ + r, b.maxZ - r);

    for (var iter = 0; iter < 4; iter++) {
      Aabb? hit;
      for (final box in _solidBoxes) {
        if (box.overlaps(p.pos.x - r, p.pos.y, p.pos.z - r, p.pos.x + r, p.pos.y + p.height, p.pos.z + r)) {
          hit = box;
          break;
        }
      }
      if (hit == null) {
        p.stuckTime = 0;
        break;
      }
      // Smallest way out: left/right/front/back, or up if it's a short lip.
      final pushNegX = (p.pos.x + r) - hit.minX;
      final pushPosX = hit.maxX - (p.pos.x - r);
      final pushNegZ = (p.pos.z + r) - hit.minZ;
      final pushPosZ = hit.maxZ - (p.pos.z - r);
      final pushUp = hit.maxY - p.pos.y;
      final best = math.min(math.min(pushNegX, pushPosX), math.min(pushNegZ, pushPosZ));
      if (pushUp <= stepHeight + 0.2 && pushUp < best) {
        p.pos.y = hit.maxY + 1e-4;
        p.vel.y = 0;
        p.onGround = true;
      } else if (best == pushNegX) {
        p.pos.x -= pushNegX + 1e-4;
      } else if (best == pushPosX) {
        p.pos.x += pushPosX + 1e-4;
      } else if (best == pushNegZ) {
        p.pos.z -= pushNegZ + 1e-4;
      } else {
        p.pos.z += pushPosZ + 1e-4;
      }
      if (iter == 3) p.stuckTime += dt;
    }

    final fellOut = p.pos.y < -5;
    if (authoritative && (fellOut || p.stuckTime > 0.4)) {
      final safe = map.nav.nearestFreePoint(p.pos);
      p.pos.set(safe.x, 0, safe.z);
      p.vel.set(0, 0, 0);
      p.onGround = true;
      p.stuckTime = 0;
      events.add({'e': 'unstuck', 'p': p.id});
    }
  }

  Iterable<Aabb> get _solidBoxes sync* {
    for (final b in map.solids) {
      yield b.box;
    }
    for (final b in barriers) {
      yield b.box;
    }
  }

  void _moveAxis(Player p, int axis, double delta, bool grounded) {
    if (delta == 0) return;
    if (axis == 0) {
      p.pos.x += delta;
    } else if (axis == 1) {
      p.pos.y += delta;
    } else {
      p.pos.z += delta;
    }
    const r = playerRadius;
    final h = p.height;
    for (final b in _solidBoxes) {
      if (!b.overlaps(p.pos.x - r, p.pos.y, p.pos.z - r, p.pos.x + r, p.pos.y + h, p.pos.z + r)) continue;
      // Auto step-up onto low ledges instead of snagging on them.
      if (axis != 1 && grounded) {
        final rise = b.maxY - p.pos.y;
        if (rise > 0 && rise <= stepHeight && !_overlapsSolid(p.pos.x, b.maxY + 1e-4, p.pos.z, h)) {
          p.pos.y = b.maxY + 1e-4;
          continue;
        }
      }
      if (axis == 0) {
        p.pos.x = delta > 0 ? b.minX - r - 1e-4 : b.maxX + r + 1e-4;
        p.vel.x = 0;
      } else if (axis == 2) {
        p.pos.z = delta > 0 ? b.minZ - r - 1e-4 : b.maxZ + r + 1e-4;
        p.vel.z = 0;
      } else {
        if (delta < 0) {
          p.pos.y = b.maxY;
          p.onGround = true;
        } else {
          p.pos.y = b.minY - h - 1e-4;
        }
        p.vel.y = 0;
      }
    }
  }

  // ------------------------------------------------------------ weapons --
  double spreadFor(Player p) {
    final def = p.weapon;
    final speed = p.vel.lengthXZ;
    final moveFactor = clampD((speed - 0.8) / 4.2, 0, 1);
    var s = def.baseSpread + def.moveSpread * moveFactor;
    if (!p.onGround) s += def.airSpread;
    s += def.spraySpread * math.min(p.recoilIndex, 8) / 8;
    if (p.ads) s *= def.zoomSpreadMult;
    if (p.crouch) s *= 0.85;
    // Sniper unscoped is still inaccurate even when ADS mult is 0 for moving.
    if (p.ads && def.zoomSpreadMult == 0) s = def.moveSpread * moveFactor * 0.6 + (p.onGround ? 0 : def.airSpread);
    return s;
  }

  void _weapon(Player p, PlayerInput inp, int pressed, double dt, bool predict, bool replay) {
    final def = p.weapon;
    p.sinceShot += dt;
    if (p.fireCooldown > 0) p.fireCooldown -= dt;
    if (p.equipTimer > 0) p.equipTimer -= dt;
    if (p.sinceShot > 1 / def.fireRate + 0.06) {
      p.recoilIndex = math.max(0, p.recoilIndex - dt * 16);
    }

    if (p.reloadTimer > 0) {
      p.reloadTimer -= dt;
      if (p.reloadTimer <= 0) {
        final need = def.mag - p.mag;
        final take = math.min(need, p.reserve);
        p.mag = p.mag + take;
        p.reserve = p.reserve - take;
        p.reloadTimer = 0;
      }
    } else if (!def.isMelee &&
        p.mag < def.mag &&
        p.reserve > 0 &&
        (pressed & Btn.reload != 0 || (inp.has(Btn.fire) && p.mag == 0 && p.fireCooldown <= 0))) {
      p.reloadTimer = def.reloadTime;
      p.ads = false;
    }

    p.ads = inp.has(Btn.ads) && def.zoom > 1 && p.reloadTimer <= 0 && p.equipTimer <= 0;

    final wantFire = inp.has(Btn.fire) && (def.auto || pressed & Btn.fire != 0);
    if (wantFire &&
        p.fireCooldown <= 0 &&
        p.equipTimer <= 0 &&
        p.reloadTimer <= 0 &&
        (def.isMelee || p.mag > 0) &&
        shootingAllowed &&
        defuserId != p.id &&
        p.plantProgress <= 0) {
      p.fireCooldown = (p.fireCooldown > -dt ? p.fireCooldown : 0) + 1 / def.fireRate;
      _fire(p, def, inp.renderTick, predict, replay);
      if (!def.isMelee) p.mag = p.mag - 1;
      p.recoilIndex += 1;
      p.sinceShot = 0;
      p.shotSeq++;
    }
  }

  void _fire(Player p, WeaponDef def, double renderTick, bool predict, bool replay) {
    final spread = spreadFor(p);
    final (rp, ry) = def.recoilAt(p.recoilIndex);
    final rr = Rng(p.id * 100003 + p.shotSeq * 7919);
    final a = rr.nextDouble() * math.pi * 2;
    final rad = math.sqrt(rr.nextDouble()) * spread;
    final dir = dirFromAngles(p.yaw + ry + math.cos(a) * rad, p.pitch + rp + math.sin(a) * rad);
    final origin = p.eye;
    final range = def.range;

    var bestT = traceWorld(origin, dir, range) ?? double.infinity;
    final hitWall = bestT.isFinite;
    Player? victim;
    var part = 0; // 0 head, 1 body, 2 legs
    for (final q in players.values) {
      if (q.id == p.id || !q.alive || q.team == p.team) continue;
      final hp = _positionAt(q, renderTick);
      final boxes = hitboxes(hp[0], hp[1], hp[2], hp[3] > 0.5);
      for (var i = 0; i < 3; i++) {
        final t = boxes[i].rayHit(origin, dir, range);
        if (t != null && t < bestT) {
          bestT = t;
          victim = q;
          part = i;
        }
      }
    }
    final endT = bestT.isFinite ? bestT : range;
    final end = origin + dir * endT;
    if (!replay) {
      events.add({
        'e': 'shot',
        's': p.id,
        'w': def.id.index,
        'o': origin.toList(2),
        'p': end.toList(2),
        'h': victim != null ? (part == 0 ? 2 : 1) : (hitWall ? 0 : -1),
      });
    }
    if (victim != null && !predict && authoritative) {
      applyDamage(victim, def.damageAt(part, endT), p, def.id, part == 0);
    }
  }

  /// [head, body, legs] boxes for a player at the given feet position.
  static List<Aabb> hitboxes(double x, double y, double z, bool crouch) {
    final h = crouch ? crouchHeight : standHeight;
    final k = h / standHeight;
    return [
      Aabb(x - 0.17, y + h - 0.34, z - 0.17, x + 0.17, y + h, z + 0.17),
      Aabb(x - 0.3, y + 0.8 * k, z - 0.3, x + 0.3, y + h - 0.34, z + 0.3),
      Aabb(x - 0.24, y, z - 0.24, x + 0.24, y + 0.8 * k, z + 0.24),
    ];
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

  /// Distance to the first solid surface along a ray, or null.
  double? traceWorld(Vec3 o, Vec3 d, double maxDist) {
    double? best;
    for (final b in _solidBoxes) {
      final t = b.rayHit(o, d, best ?? maxDist);
      if (t != null && (best == null || t < best)) best = t;
    }
    return best;
  }

  bool lineClear(Vec3 a, Vec3 b, {bool smokeBlocks = true}) {
    final diff = b - a;
    final len = diff.length;
    if (len < 1e-6) return true;
    final d = diff * (1 / len);
    for (final box in _solidBoxes) {
      final t = box.rayHit(a, d, len);
      if (t != null && t < len - 0.05) return false;
    }
    if (smokeBlocks) {
      for (final s in smokes) {
        if (raySphere(a, d, s.pos, s.radius, len) != null) return false;
      }
    }
    return true;
  }

  void applyDamage(Player victim, double amount, Player? attacker, WeaponId? weapon, bool head) {
    if (!victim.alive || amount <= 0) return;
    final before = victim.hp + victim.shield;
    final shieldPart = math.min(victim.shield, amount * 0.66);
    victim.shield -= shieldPart;
    victim.hp -= amount - shieldPart;
    final dealt = math.min(before, amount);
    if (attacker != null) {
      attacker.damage += dealt.round();
      attacker.score += dealt.round();
      victim.damageFrom[attacker.id] = (victim.damageFrom[attacker.id] ?? 0) + dealt;
      brains[victim.id]?.onDamaged(attacker);
    }
    events.add({'e': 'hit', 'a': attacker?.id ?? -1, 'v': victim.id, 'd': dealt.round(), 'hd': head ? 1 : 0});
    if (victim.hp <= 0) _kill(victim, attacker, weapon, head);
  }

  void _kill(Player victim, Player? killer, WeaponId? weapon, bool head) {
    victim
      ..alive = false
      ..hp = 0
      ..shield = 0
      ..primary = null
      ..survived = false
      ..plantProgress = 0
      ..deaths += 1;
    if (killer != null && killer.id != victim.id) {
      killer
        ..kills += 1
        ..credits = math.min(9000, killer.credits + 200)
        ..score += 150;
      if (head) killer.headshots++;
    }
    for (final aid in victim.damageFrom.keys) {
      if (aid == killer?.id) continue;
      final a = players[aid];
      if (a != null && a.team != victim.team) {
        a.assists++;
        a.score += 50;
      }
    }
    if (coreCarrier == victim.id) {
      coreCarrier = null;
      coreState = CoreState.dropped;
      corePos.setFrom(victim.pos);
      events.add({'e': 'coreDrop'});
    }
    if (defuserId == victim.id) {
      defuserId = null;
      defuseProgress = defuseProgress >= cfg.defuseTime / 2 ? cfg.defuseTime / 2 : 0;
    }
    events.add({
      'e': 'kill',
      'k': killer?.id ?? -1,
      'v': victim.id,
      'w': weapon?.index ?? -1,
      'hd': head ? 1 : 0,
    });
    _checkElims();
  }

  // ---------------------------------------------------------- abilities --
  void _useAbility(Player p, PlayerInput inp, bool isQ) {
    if (phase != Phase.live && phase != Phase.planted && phase != Phase.roundEnd) return;
    final def = isQ ? p.agentDef.q : p.agentDef.e;
    if ((isQ ? p.qCharges : p.eCharges) <= 0) return;
    final dir = p.viewDir;
    final eye = p.eye;
    switch (def.kind) {
      case AbilityKind.dash:
        final sy = math.sin(p.yaw), cy = math.cos(p.yaw);
        var wx = cy * inp.moveX + sy * inp.moveZ;
        var wz = sy * inp.moveX - cy * inp.moveZ;
        var l = math.sqrt(wx * wx + wz * wz);
        if (l < 0.1) {
          wx = sy;
          wz = -cy;
          l = 1;
        }
        p.dashX = wx / l;
        p.dashZ = wz / l;
        p.dashTime = 0.2;
      case AbilityKind.smoke:
        projectiles.add(Projectile(p.id, def.kind, eye + dir * 0.6, dir * 24 + Vec3(0, 2, 0), 1.6));
      case AbilityKind.flash:
        projectiles.add(Projectile(p.id, def.kind, eye + dir * 0.6, dir * 17 + Vec3(0, 3, 0), 0.8));
      case AbilityKind.recon:
        projectiles.add(Projectile(p.id, def.kind, eye + dir * 0.6, dir * 20 + Vec3(0, 3, 0), 1.3));
      case AbilityKind.heal:
        Player target = p;
        for (final q in players.values) {
          if (q.id == p.id || !q.alive || q.team != p.team) continue;
          final b = hitboxes(q.pos.x, q.pos.y, q.pos.z, q.crouch);
          if (b.any((bb) => bb.rayHit(eye, dir, 14) != null)) {
            target = q;
            break;
          }
        }
        if (target.hp >= maxHp) return;
        target.healLeft = 60;
      case AbilityKind.barrier:
        final fx = math.sin(p.yaw), fz = -math.cos(p.yaw);
        final cx = p.pos.x + fx * 3, cz = p.pos.z + fz * 3;
        final alongX = fz.abs() > fx.abs();
        final hw = alongX ? 2.2 : 0.3, hd = alongX ? 0.3 : 2.2;
        barriers.add(Barrier(Aabb(cx - hw, 0, cz - hd, cx + hw, 2.6, cz + hd), 14));
    }
    if (isQ) {
      p.qCharges--;
    } else {
      p.eCharges--;
      if (def.recharge > 0) p.eRecharge = def.recharge;
    }
    events.add({'e': 'ability', 'p': p.id, 'k': def.kind.index, 'at': p.pos.toList(2)});
  }

  void _updateProjectiles(double dt) {
    for (final pj in projectiles.toList()) {
      pj.fuse -= dt;
      pj.vel.y -= 14 * dt;
      final step = pj.vel * dt;
      final len = step.length;
      var pop = pj.fuse <= 0;
      if (len > 1e-6) {
        final d = step * (1 / len);
        Aabb? hitBox;
        double? hitT;
        for (final b in _solidBoxes) {
          final t = b.rayHit(pj.pos, d, len);
          if (t != null && (hitT == null || t < hitT)) {
            hitT = t;
            hitBox = b;
          }
        }
        if (hitT != null && hitBox != null) {
          final hit = pj.pos + d * math.max(0, hitT - 0.05);
          pj.pos.setFrom(hit);
          if (pj.kind == AbilityKind.flash) {
            // reflect on the closest face axis
            final c = hitBox.center, s = hitBox.size;
            final nx = (hit.x - c.x) / (s.x / 2), ny = (hit.y - c.y) / (s.y / 2), nz = (hit.z - c.z) / (s.z / 2);
            if (nx.abs() >= ny.abs() && nx.abs() >= nz.abs()) {
              pj.vel.x *= -0.45;
            } else if (ny.abs() >= nz.abs()) {
              pj.vel.y *= -0.45;
            } else {
              pj.vel.z *= -0.45;
            }
            pj.vel.x *= 0.7;
            pj.vel.z *= 0.7;
          } else {
            pop = true;
          }
        } else {
          pj.pos.setFrom(pj.pos + step);
        }
      }
      if (pop) {
        projectiles.remove(pj);
        _popProjectile(pj);
      }
    }
  }

  void _popProjectile(Projectile pj) {
    final owner = players[pj.owner];
    switch (pj.kind) {
      case AbilityKind.smoke:
        final c = Vec3(pj.pos.x, math.max(pj.pos.y, 0) + 1.4, pj.pos.z);
        smokes.add(Smoke(c, 4.2, 15, owner?.team ?? 0));
        events.add({'e': 'smoke', 'at': c.toList(2)});
      case AbilityKind.flash:
        for (final q in players.values) {
          if (!q.alive) continue;
          final eye = q.eye;
          final to = pj.pos - eye;
          final dist = to.length;
          if (dist > 50 || !lineClear(eye, pj.pos)) continue;
          final cosA = q.viewDir.dot(to * (1 / math.max(dist, 1e-6)));
          final ang = math.acos(clampD(cosA, -1, 1));
          var dur = ang < 0.85 ? 2.3 : (ang < 1.6 ? 0.55 : 0.0);
          if (dist < 3) dur = math.max(dur, 0.9);
          if (dur > q.flashTime) q.flashTime = dur;
          if (dur > 0.5) brains[q.id]?.onFlashed();
        }
        events.add({'e': 'flash', 'at': pj.pos.toList(2)});
      case AbilityKind.recon:
        final team = owner?.team ?? 0;
        for (final q in players.values) {
          if (!q.alive || q.team == team) continue;
          if (q.pos.distanceTo(pj.pos) < 28 && lineClear(pj.pos, q.eye, smokeBlocks: false)) {
            q.revealTime = 3.5;
          }
        }
        events.add({'e': 'recon', 'at': pj.pos.toList(2)});
      default:
        break;
    }
  }

  // ------------------------------------------------------------- update --
  void update(double dt) {
    if (!authoritative) return;
    dt = clampD(dt, 0, 0.1);
    time += dt;
    tick++;

    // Bots think and act through the same input path as humans.
    for (final b in brains.values.toList()) {
      final p = players[b.id];
      if (p == null) continue;
      final inp = b.think(this, p, dt);
      if (inp != null) processInput(p, inp);
    }

    for (final p in players.values) {
      if (p.flashTime > 0) p.flashTime = math.max(0, p.flashTime - dt);
      if (p.revealTime > 0) p.revealTime = math.max(0, p.revealTime - dt);
      if (p.healLeft > 0 && p.alive) {
        final h = math.min(p.healLeft, 22 * dt);
        p.healLeft -= h;
        p.hp = math.min(maxHp, p.hp + h);
      }
      if (p.eRecharge > 0) {
        p.eRecharge -= dt;
        if (p.eRecharge <= 0) {
          p.eRecharge = 0;
          if (p.eCharges < p.agentDef.e.freeCharges) p.eCharges++;
        }
      }
    }
    for (final s in smokes.toList()) {
      s.life -= dt;
      if (s.life <= 0) smokes.remove(s);
    }
    for (final b in barriers.toList()) {
      b.life -= dt;
      if (b.life <= 0) barriers.remove(b);
    }
    _updateProjectiles(dt);
    _updateCore(dt);

    phaseTimer -= dt;
    switch (phase) {
      case Phase.warmup:
        if (phaseTimer <= 0) _startRound();
      case Phase.buy:
        if (phaseTimer <= 0) {
          phase = Phase.live;
          phaseTimer = cfg.roundTime;
          events.add({'e': 'live'});
        }
      case Phase.live:
        if (phaseTimer <= 0) _endRound(defenseTeam, 'time');
      case Phase.planted:
        if (phaseTimer <= 0) {
          coreState = CoreState.detonated;
          events.add({'e': 'detonate', 'at': corePos.toList(2)});
          _endRound(attackTeam, 'detonate');
          for (final q in players.values) {
            if (q.alive && q.pos.distanceTo(corePos) < 12) applyDamage(q, 500, null, null, false);
          }
        }
      case Phase.roundEnd:
        if (phaseTimer <= 0) {
          if (matchWinner != null) {
            phase = Phase.matchEnd;
            phaseTimer = 0;
            events.add({'e': 'match', 'w': matchWinner});
          } else {
            _startRound();
          }
        }
      case Phase.matchEnd:
        break;
    }

    if (tick % 4 == 0) _updateSpotting();
    _checkElims();
    _recordHistory();
  }

  void _updateCore(double dt) {
    if (coreState == CoreState.dropped && (phase == Phase.live)) {
      for (final p in teamOf(attackTeam)) {
        if (p.alive && p.pos.distanceXZ(corePos) < 1.3) {
          coreCarrier = p.id;
          coreState = CoreState.carried;
          events.add({'e': 'corePick', 'p': p.id});
          break;
        }
      }
    }
    for (final p in players.values) {
      final held = _useHeld[p.id] ?? false;
      if (!p.alive) continue;
      if (isAttacker(p)) {
        final canPlant = held &&
            phase == Phase.live &&
            coreCarrier == p.id &&
            p.onGround &&
            map.siteAt(p.pos) != null;
        if (canPlant) {
          p.plantProgress += dt;
          if (p.plantProgress >= cfg.plantTime) {
            p.plantProgress = 0;
            coreState = CoreState.planted;
            corePos.setFrom(p.pos);
            coreCarrier = null;
            coreSite = map.siteAt(p.pos)!.name;
            phase = Phase.planted;
            phaseTimer = cfg.coreTime;
            for (final m in teamOf(attackTeam)) {
              m.credits = math.min(9000, m.credits + 300);
            }
            p.score += 100;
            events.add({'e': 'plant', 'p': p.id, 'site': coreSite});
          }
        } else {
          p.plantProgress = 0;
        }
      } else if (phase == Phase.planted) {
        final near = p.pos.distanceTo(corePos) < 1.9;
        if (held && near && (defuserId == null || defuserId == p.id) && p.onGround) {
          if (defuserId == null) events.add({'e': 'defuseStart', 'p': p.id});
          defuserId = p.id;
          defuseProgress += dt;
          if (defuseProgress >= cfg.defuseTime) {
            coreState = CoreState.defused;
            p.score += 100;
            events.add({'e': 'defuse', 'p': p.id});
            _endRound(defenseTeam, 'defuse');
          }
        } else if (defuserId == p.id) {
          defuserId = null;
          defuseProgress = defuseProgress >= cfg.defuseTime / 2 ? cfg.defuseTime / 2 : 0;
        }
      }
    }
  }

  void _updateSpotting() {
    for (final p in players.values) {
      var mask = 0;
      if (p.alive) {
        if (p.revealTime > 0) mask |= 1 << (1 - p.team);
        final chest = Vec3(p.pos.x, p.pos.y + p.height * 0.7, p.pos.z);
        for (final o in players.values) {
          if (!o.alive || o.team == p.team || o.flashTime > 0.6) continue;
          if (mask & (1 << o.team) != 0) continue;
          if (canSee(o, chest)) mask |= 1 << o.team;
        }
      }
      p.spottedMask = mask;
    }
  }

  /// Whether [o] can see world point [target] (FOV + line of sight + smoke).
  bool canSee(Player o, Vec3 target, {double fovCos = 0.55, double maxDist = 80}) {
    final eye = o.eye;
    final to = target - eye;
    final dist = to.length;
    if (dist > maxDist) return false;
    if (dist > 1.5 && o.viewDir.dot(to * (1 / dist)) < fovCos) return false;
    return lineClear(eye, target);
  }

  void _recordHistory() {
    _history[tick] = {
      for (final p in players.values) p.id: [p.pos.x, p.pos.y, p.pos.z, p.crouch ? 1.0 : 0.0],
    };
    _history.remove(tick - 40);
  }

  // ------------------------------------------------------- serialization --
  Map<String, Object?> snapshot() => {
        't': 'snap',
        'tk': tick,
        'tm': r(time, 3),
        'ph': phase.index,
        'pt': r(phaseTimer, 2),
        'rd': round,
        'hf': half,
        'sc': [scores[0], scores[1]],
        'cs': coreState.index,
        'cc': coreCarrier ?? -1,
        'cp': corePos.toList(2),
        'dp': r(defuseProgress, 2),
        'di': defuserId ?? -1,
        'cst': coreSite,
        'mw': matchWinner ?? -1,
        'lw': lastRoundWinner,
        'lr': lastRoundReason,
        'pl': [for (final p in players.values) p.toNet()],
        'sm': [
          for (final s in smokes) [...s.pos.toList(2), s.radius, r(s.life, 1), s.team]
        ],
        'br': [
          for (final b in barriers) [...b.box.toList(), r(b.life, 1)]
        ],
        'pj': [
          for (final p in projectiles) [p.kind.index, ...p.pos.toList(2)]
        ],
      };

  /// Mirror update on the client.
  void applySnapshot(Map<String, dynamic> s) {
    tick = (s['tk'] as num).toInt();
    time = (s['tm'] as num).toDouble();
    phase = Phase.values[(s['ph'] as num).toInt()];
    phaseTimer = (s['pt'] as num).toDouble();
    round = (s['rd'] as num).toInt();
    half = (s['hf'] as num).toInt();
    final sc = s['sc'] as List;
    scores[0] = (sc[0] as num).toInt();
    scores[1] = (sc[1] as num).toInt();
    coreState = CoreState.values[(s['cs'] as num).toInt()];
    final cc = (s['cc'] as num).toInt();
    coreCarrier = cc < 0 ? null : cc;
    final cp = Vec3.fromList(s['cp'] as List);
    corePos.setFrom(cp);
    defuseProgress = (s['dp'] as num).toDouble();
    final di = (s['di'] as num).toInt();
    defuserId = di < 0 ? null : di;
    coreSite = s['cst'] as String?;
    final mw = (s['mw'] as num).toInt();
    matchWinner = mw < 0 ? null : mw;
    lastRoundWinner = (s['lw'] as num).toInt();
    lastRoundReason = s['lr'] as String? ?? '';

    final seen = <int>{};
    for (final raw in s['pl'] as List) {
      final l = raw as List;
      final id = (l[0] as num).toInt();
      seen.add(id);
      final existing = players[id];
      if (existing == null) {
        players[id] = Player.fromNet(l);
      } else {
        existing.applyNet(l);
      }
    }
    players.removeWhere((id, _) => !seen.contains(id));

    smokes
      ..clear()
      ..addAll([
        for (final raw in s['sm'] as List)
          Smoke(Vec3.fromList(raw as List), (raw[3] as num).toDouble(), (raw[4] as num).toDouble(),
              (raw[5] as num).toInt())
      ]);
    barriers
      ..clear()
      ..addAll([
        for (final raw in s['br'] as List) Barrier(Aabb.fromList(raw as List), (raw[6] as num).toDouble())
      ]);
    projectiles
      ..clear()
      ..addAll([
        for (final raw in s['pj'] as List)
          Projectile(-1, AbilityKind.values[(raw as List)[0] as int], Vec3.fromList(raw.sublist(1)), Vec3.zero(), 1)
      ]);
  }

  /// Final per-player stats for persistence.
  List<Map<String, Object?>> matchStats() => [
        for (final p in players.values)
          {
            'id': p.id,
            'accountId': p.accountId,
            'name': p.name,
            'bot': p.isBot,
            'team': p.team,
            'agent': p.agent.name,
            'kills': p.kills,
            'deaths': p.deaths,
            'assists': p.assists,
            'headshots': p.headshots,
            'damage': p.damage,
            'score': p.score,
            'won': matchWinner == p.team,
          }
      ];
}
