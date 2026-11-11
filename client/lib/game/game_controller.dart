import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:rps_shared/rps_shared.dart';

import '../engine/engine.dart';
import '../ui/settings.dart';
import 'net_client.dart';

part 'game_debug.dart';
part 'game_events.dart';

class KillFeedEntry {
  int killerId = -1, victimId = -1;

  /// Gun or skill id used ('' = environment).
  String weaponId = '';
  final String killer, victim;
  final int killerTeam, victimTeam;
  final String weapon;
  final bool head;
  final double time;
  KillFeedEntry(this.killer, this.killerTeam, this.victim, this.victimTeam, this.weapon, this.head, this.time);
}

class ScoreRow {
  final String name, charId;
  final int team, kills, deaths, assists;
  final int damage;
  final bool me;
  ScoreRow(Player p, this.me)
      : name = p.name,
        charId = p.charId,
        team = p.team,
        kills = p.kills,
        deaths = p.deaths,
        assists = p.assists,
        damage = p.damageDealt.round();
}

class MatchResult {
  final int winner, myTeam;
  final List<double> score;
  final List<ScoreRow> rows;
  final String mapId;
  final double seconds;
  MatchResult(this.winner, this.myTeam, this.score, this.rows, this.mapId, this.seconds);
}

/// Footstep surface per map (rps_sfx README).
const _surface = {
  'rps_arena': 'concrete',
  'desert_ruins': 'sand',
  'frost_harbor': 'snow',
  'neon_rooftops': 'metal',
  'jungle_temple': 'grass',
};

/// Skill id -> GLB path (catalog), for deployables and projectiles.
final Map<String, String> skillFiles = {
  for (final c in characterInfos)
    for (final s in c.skills) s.id: s.file,
};

/// How a deployable is drawn: 0 model, 1 ground area ring, 2 smoke ball, 3 dome, 4 wall.
const Map<String, int> _depShape = {
  'amp_shard': 1, 'mending_seal': 1, 'undying_lantern': 1, 'ink_puddle': 1, 'lava_flow': 1, //
  'steel_lockdown': 1, 'blade_rain': 1, 'crystal_sanctum': 1,
  'ink_cloud': 2, 'box_fort': 3, 'brush_wall': 4,
};

/// Damage sources that act on their own (no number popup for these).
const _autoDamage = {
  'rock_turret', 'staple_sentry', 'lava_flow', 'ink_puddle', 'blade_fence', 'parcel_drop', //
  'quake_trap', 'wire_snare', 'alarm_bot', 'steel_lockdown', 'spike_guard', 'spawn',
};

/// Traps the enemy team doesn't get to see.
const _hiddenTraps = {'quake_trap', 'wire_snare'};

const _sfx = [
  'dry_fire', 'kill_ding', 'headshot_ding', 'death_cat', 'death_dog', 'gun_launcher_explosion', //
  'gun_shotgun_pump', 'gun_sniper_bolt',
  'hit_tick', 'hurt', 'dash', 'heal_loop', 'shield_up', 'deploy', 'trap_trigger', 'explosion_small', //
  'point_captured', 'point_lost', 'ult_ready', 'ui_click', 'match_victory', 'match_defeat',
];

/// First-person motion when casting: thrown vs placed skills.
const _throwSkills = {
  'magma_slug', 'box_fort', 'tape_hook', 'recon_pebble', 'sticky_charge', 'phase_beacon', 'sleep_dart', //
  'stitch_grenade', 'ink_puddle', 'crane_scout', 'ink_cloud', 'blade_rain',
};
const _placeSkills = {
  'rock_bulwark', 'blade_fence', 'amp_shard', 'crystal_sanctum', 'mending_seal', 'undying_lantern', //
  'rock_turret', 'quake_trap', 'staple_sentry', 'wire_snare', 'alarm_bot', 'steel_lockdown', 'parcel_drop',
};
const _dashSkills = {'landslide_charge', 'gale_cut', 'paper_dash', 'paper_updraft', 'cleave_leap', 'crate_roll'};
const _shieldBuffs = {'ward_talisman', 'grand_scroll', 'cleanse_bell', 'nano_stitch', 'overheat'};
const _bigBlasts = {'launcher', 'sticky_charge', 'earth_rift', 'blade_rain', 'steel_lockdown'};

/// Offline practice match: you + 9 bots, running the shared authoritative
/// sim locally. Later the same controller will feed a server instead.
class GameController extends ChangeNotifier {
  /// Offline practice vs bots, or online when [serverUrl] is given.
  GameController(this.settings, {this.serverUrl}) {
    online ? _initOnline() : _init();
  }

  final Settings settings;
  final String? serverUrl;
  bool get online => serverUrl != null;
  NetClient? net;
  StreamSubscription<Map<String, dynamic>>? _netSub;
  int ping = 0;
  int? _myId;
  int _snapTick = 0;
  double _pingT = 0;
  final List<PlayerInput> _pending = [];
  final List<PlayerInput> _outbox = [];
  final Map<int, Vec3> _rpos = {};
  final Engine engine = Engine.I;
  GameSim? sim;
  Player? me;
  late MapDef def;

  bool loading = true;
  String status = '맵 불러오는 중...';
  String? error;

  double yaw = 0, pitch = 0;
  bool locked = false;
  bool shopOpen = false;

  /// Character picker (press B while dead).
  bool charPickerOpen = false;
  bool _ultWasReady = false;
  double _lastHurt = 0;
  bool scoreboard = false;
  String? toast;
  double toastTime = 0;

  final List<KillFeedEntry> feed = [];
  double hitmarker = 0;
  bool hitHead = false;
  double damageFlash = 0;
  double damageDir = 0;
  String? banner;
  double bannerTime = 0;
  int? killedBy;
  double ended = -1;
  void Function(MatchResult r)? onEnd;

  double _acc = 0;
  int _seq = 0;
  double _t = 0;
  String _vmKey = '';
  Vec3? _deathEye;
  double _deathYaw = 0, _deathPitch = 0;
  final Map<int, double> _stride = {};
  final Map<int, int> _stepN = {};
  bool _disposed = false;

  static const step = 1 / 60;

  Future<void> _init() async {
    try {
      def = mapById(settings.mapId);
      status = '맵 불러오는 중... (${def.name})';
      notifyListeners();
      final bytes = await Engine.fetchBytes(def.file);
      final map = GameMap.fromGlb(def, bytes);
      final s = GameSim(map,
          cfg: SimConfig(botSkill: settings.botSkill), seed: DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
      final p = s.addPlayer(settings.name, settings.charId, teamId: 0);
      s.fillBots();
      sim = s;
      me = p;
      yaw = p.yaw;
      await _prepareScene(s, p);
    } catch (e, st) {
      error = '불러오기 실패: $e';
      debugPrint('$e\n$st');
      notifyListeners();
    }
  }

  Future<void> _prepareScene(GameSim s, Player p) async {
    {
      status = '모델 불러오는 중...';
      notifyListeners();
      final models = <String>{
        for (final q in s.players.values) 'glb/characters/${q.charId}.glb',
        for (final g in guns) 'glb/guns/${g.id}.glb',
        'glb/fp_rigs/pistol.glb',
        'glb/fp_arms/${p.charId}.glb',
        'glb/fx/death_cat.glb',
        'glb/fx/death_dog.glb',
        'glb/fx/kill_paw.glb',
        'glb/fx/kill_headshot.glb',
      };
      await engine.js.loadMap(def.id).toDart;
      await engine.js.preload(jsStrs(models.toList())).toDart;
      final surf = _surface[def.id] ?? 'concrete';
      engine.audio.preload(jsStrs([
        ..._sfx,
        for (final g in guns) ...['gun_${g.id}_fire', 'gun_${g.id}_reload'],
        for (final m in ['walk', 'run'])
          for (var i = 1; i <= 4; i++) 'step_${surf}_${m}_$i',
      ]));
      engine.audio.playMusic(def.id);
      if (_disposed) return;
      loading = false;
      status = '';
      engine.setTick(_tick);
      if (Uri.base.queryParameters.containsKey('debug')) _debugHooks();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ online --
  Future<void> _initOnline() async {
    try {
      status = '서버 연결 중... $serverUrl';
      notifyListeners();
      final n = net = NetClient(serverUrl!);
      await n.connect();
      final welcome = n.messages.firstWhere((m) => m['t'] == 'welcome' || m['t'] == 'err');
      _netSub = n.messages.listen(_onNet);
      n.send(Net.hello(settings.name, settings.charId));
      final w = await welcome.timeout(const Duration(seconds: 8));
      if (w['t'] == 'err') throw StateError(w['m'] as String);
      await _loadWorld(w['map'] as String, w['id'] as int);
    } catch (e, st) {
      error = '온라인 접속 실패: $e';
      debugPrint('$e\n$st');
      notifyListeners();
    }
  }

  Future<void> _loadWorld(String mapId, int myId) async {
    loading = true;
    engine.setTick(null);
    def = mapById(mapId);
    status = '맵 불러오는 중... (${def.name})';
    notifyListeners();
    final map = GameMap.fromGlb(def, await Engine.fetchBytes(def.file));
    final s = GameSim(map, authoritative: false);
    _myId = myId;
    _pending.clear();
    _rpos.clear();
    engine.js.clearPlayers();
    sim = s;
    me = null;
    // Wait for the first snapshot so we know where we are.
    final snap = await net!.messages.firstWhere((m) => m['t'] == 'snap').timeout(const Duration(seconds: 8));
    _applySnap(snap);
    final p = me;
    if (p == null) throw StateError('서버 스냅샷에 내 플레이어가 없습니다');
    yaw = p.yaw;
    pitch = 0;
    _vmKey = '';
    ended = -1;
    await _prepareScene(s, p);
  }

  void _onNet(Map<String, dynamic> m) {
    switch (m['t']) {
      case 'snap':
        if (!loading) _applySnap(m);
      case 'welcome':
        if (sim == null) break; // first welcome is handled by _initOnline
        if (m['map'] != def.id || m['id'] != _myId) _loadWorld(m['map'] as String, m['id'] as int);
      case 'err' || 'msg':
        _toast('${m['m']}');
      case 'pong':
        ping = DateTime.now().millisecondsSinceEpoch - (m['c'] as num).toInt();
      case 'closed':
        error = '서버 연결이 끊겼습니다 (${m['m']})';
        engine.setTick(null);
        notifyListeners();
    }
  }

  /// Server state wins; then re-apply inputs the server hasn't seen yet.
  void _applySnap(Map<String, dynamic> m) {
    final s = sim;
    if (s == null) return;
    s.applySnapshot(m['s'] as Map<String, dynamic>);
    _snapTick = s.tick;
    final p = me = s.players[_myId];
    if (p == null) return;
    final ack = (m['ack'] as num).toInt();
    _pending.removeWhere((i) => i.seq <= ack);
    for (final i in _pending) {
      s.processInput(p, PlayerInput.fromNet(i.toNet()), predict: true, replay: true);
    }
    s.events.clear();
    final ev = [
      for (final e in (m['ev'] as List).cast<Map<String, dynamic>>())
        if (!_isOwnPredicted(e, p.id)) e,
    ];
    _handle(ev, s, p);
  }

  /// Shots and reloads of the local player are already played from prediction.
  static bool _isOwnPredicted(Map<String, Object?> e, int me) =>
      (e['e'] == 'shot' && e['s'] == me) ||
      (e['e'] == 'reload' && e['p'] == me) ||
      (e['e'] == 'blink' && e['p'] == me) ||
      (e['e'] == 'skill' && e['p'] == me && (skillImpls[e['id']]?.predictable ?? false));

  // ------------------------------------------------------------- input --
  void requestLock() => engine.input.lock();

  void toggleShop() {
    final s = sim, p = me;
    if (s == null || p == null) return;
    if (!p.alive) {
      // Dead: B opens the character picker instead.
      charPickerOpen = !charPickerOpen;
      charPickerOpen ? engine.input.unlock() : engine.input.lock();
      notifyListeners();
      return;
    }
    if (!shopOpen && !(p.alive && s.map.inSpawnRoom(p.team, p.pos))) {
      _toast('상점은 스폰룸에서만 열립니다');
      return;
    }
    shopOpen = !shopOpen;
    if (shopOpen) {
      engine.input.unlock();
    } else {
      engine.input.lock();
    }
    notifyListeners();
  }

  /// Switch character (dead or in your spawn room); applies at respawn.
  void pickCharacter(String id) {
    final s = sim, p = me;
    if (s == null || p == null) return;
    settings.charId = id;
    settings.save();
    if (online) {
      net?.send({'t': 'char', 'c': id});
    } else {
      final err = s.pickCharacter(p, id);
      if (err != null) _toast(err);
    }
    charPickerOpen = false;
    engine.input.lock();
    _toast('${characterById(id).name}(으)로 변경');
    notifyListeners();
  }

  /// Where the capture point is on screen: (x, y in 0..1, distance m,
  /// onScreen). Off-screen markers are pushed to the screen edge.
  (double, double, double, bool)? objectiveOnScreen(double aspect) {
    final s = sim, p = me;
    if (s == null || p == null) return null;
    final c = s.map.capture;
    final eye = p.alive ? p.eye : (_deathEye ?? p.eye);
    final d = Vec3(c.x, c.y + 1.5, c.z) - eye;
    final dist = d.length;
    final f = dirFromAngles(yaw, pitch);
    final rgt = Vec3(math.cos(yaw), 0, math.sin(yaw));
    final up = rgt.cross(f);
    final z = d.dot(f), x = d.dot(rgt), y = d.dot(up);
    final tv = math.tan(_fov(p) * math.pi / 360), th = tv * aspect;
    var sx = 0.5 + (x / math.max(z, 0.01)) / th * 0.5;
    var sy = 0.5 - (y / math.max(z, 0.01)) / tv * 0.5;
    var on = z > 0 && sx > 0.03 && sx < 0.97 && sy > 0.08 && sy < 0.92;
    if (!on) {
      // Clamp along the direction to the target.
      var ax = x, ay = -y;
      if (z <= 0 && ax.abs() < 1e-3) ax = 1;
      final l = math.sqrt(ax * ax + ay * ay);
      ax /= l;
      ay /= l;
      final k = math.min(0.45 / math.max(ax.abs(), 1e-3), 0.40 / math.max(ay.abs(), 1e-3));
      sx = 0.5 + ax * k;
      sy = 0.5 + ay * k;
      on = false;
    }
    return (sx, sy, dist, on);
  }

  String? buy(String gunId) {
    final s = sim, p = me;
    if (s == null || p == null) return null;
    if (online) {
      net?.send({'t': 'buy', 'g': gunId});
      return null;
    }
    final err = s.buy(p, gunId);
    if (err != null) _toast(err);
    notifyListeners();
    return err;
  }

  void _toast(String t) {
    toast = t;
    toastTime = 2.2;
  }

  // -------------------------------------------------------------- tick --
  void _tick(double dt) {
    final s = sim, p = me;
    if (_disposed || s == null || p == null) return;
    _t += dt;
    final inp = engine.input.poll();
    locked = inp.locked;
    final keys = inp.keys.isEmpty ? const <String>{} : inp.keys.split(',').toSet();
    final pressed = inp.pressed.isEmpty ? const <String>{} : inp.pressed.split(',').toSet();
    // A key tapped and released within one frame still counts as down once.
    final down = {...keys, ...pressed};
    scoreboard = keys.contains('Tab');
    if (pressed.contains('KeyB')) toggleShop();
    if (shopOpen && (!p.alive || !s.map.inSpawnRoom(p.team, p.pos))) {
      shopOpen = false;
    }

    // Look: scale by zoom so ADS feels consistent.
    final g = p.gun;
    final fov = _fov(p);
    final zoomScale = math.tan(fov * math.pi / 360) / math.tan(settings.fov * math.pi / 360);
    if (locked) {
      yaw = wrapAngle(yaw + inp.dx * settings.sensitivity * zoomScale);
      pitch = clampD(pitch - inp.dy * settings.sensitivity * zoomScale, -1.5, 1.5);
    }

    var buttons = 0;
    double mx = 0, mz = 0;
    if (locked) {
      if (down.contains('KeyW')) mz += 1;
      if (down.contains('KeyS')) mz -= 1;
      if (down.contains('KeyD')) mx += 1;
      if (down.contains('KeyA')) mx -= 1;
      if (inp.buttons & 1 != 0) buttons |= Btn.fire;
      if (inp.buttons & 4 != 0) buttons |= Btn.ads;
      if (down.contains('Space')) buttons |= Btn.jump;
      if (down.contains('ShiftLeft')) buttons |= Btn.crouch; // Shift only (Ctrl+W would close the tab)
      if (down.contains('AltLeft')) buttons |= Btn.walk;
      if (down.contains('KeyR')) buttons |= Btn.reload;
      if (down.contains('Digit1')) buttons |= Btn.slotPrimary;
      if (down.contains('Digit2')) buttons |= Btn.slotSecondary;
      if (inp.wheel != 0) buttons |= p.slot == 0 ? Btn.slotSecondary : Btn.slotPrimary;
      if (down.contains('KeyQ')) buttons |= Btn.skillQ;
      if (down.contains('KeyE')) buttons |= Btn.skillE;
      if (down.contains('KeyC')) buttons |= Btn.skillShift; // 3rd skill
      if (down.contains('KeyV')) buttons |= Btn.ult;
      if ((buttons & Btn.fire) != 0 && (p.prevButtons & Btn.fire) == 0 && p.alive && p.mag == 0 && p.reserve == 0) {
        engine.sfx('dry_fire', vol: 0.7);
      }
    }

    _acc = math.min(_acc + dt, step * 6);
    while (_acc >= step) {
      _acc -= step;
      final raw = PlayerInput(
          seq: ++_seq,
          dt: step,
          moveX: mx,
          moveZ: mz,
          yaw: yaw,
          pitch: pitch,
          buttons: buttons,
          renderTick: online ? _snapTick - 1.0 : -1);
      if (online) {
        // Predict with exactly what the server will receive (wire rounding).
        final wire = PlayerInput.fromNet(raw.toNet());
        _pending.add(wire);
        _outbox.add(PlayerInput.fromNet(raw.toNet()));
        if (_pending.length > 180) _pending.removeAt(0);
        s.processInput(p, PlayerInput.fromNet(raw.toNet()), predict: true);
        s.update(step);
        _handle([for (final e in s.events) if (_isOwnPredicted(e, p.id)) e], s, p);
        s.events.clear();
      } else {
        s.processInput(p, raw);
        s.update(step);
        _handle(s.events, s, p);
        s.events.clear();
      }
    }
    if (online && _outbox.isNotEmpty) {
      net?.send(Net.inputs(_outbox));
      _outbox.clear();
    }
    if (online && (_pingT += dt) > 2) {
      _pingT = 0;
      net?.send({'t': 'ping', 'c': DateTime.now().millisecondsSinceEpoch});
    }
    _footsteps(s, p, dt);
    _render(s, p, g, dt);
    if (p.alive && charPickerOpen) {
      charPickerOpen = false;
    }
    final ultReady = p.alive && s.ultReady(p);
    if (ultReady && !_ultWasReady) {
      _banner('궁극기 준비! (V) ${p.character.info.skill(SkillKey.ult).name}');
      engine.sfx('ult_ready', vol: 0.8);
    }
    _ultWasReady = ultReady;

    hitmarker = math.max(0, hitmarker - dt);
    damageFlash = math.max(0, damageFlash - dt);
    if (bannerTime > 0) bannerTime -= dt;
    if (toastTime > 0) toastTime -= dt;
    feed.removeWhere((e) => _t - e.time > 6);
    if (ended >= 0) {
      ended += dt;
      if (ended > 4 && onEnd != null) {
        final cb = onEnd!;
        onEnd = null;
        cb(result());
      }
    }
    notifyListeners();
  }

  /// Status ring under/over a player: shield, disabled, buffed, invulnerable, slowed.
  int _aura(GameSim s, Player q) {
    if (s.has(q, 'invuln') || s.has(q, 'undying')) return 4;
    if (s.disabled(q) || s.has(q, 'root')) return 2;
    if ((q.fx['shield'] ?? 0) > 0) return 1;
    if (s.has(q, 'amp') || s.has(q, 'haste') || s.has(q, 'prot')) return 3;
    if (s.has(q, 'slow')) return 5;
    return 0;
  }

  double _fov(Player p) {
    final a = p.gun.info.adsFov;
    final t = Curves.easeOut.transform(p.adsT);
    return settings.fov + (a - settings.fov) * t;
  }

  bool get scoped => (me?.gun.info.overlay ?? false) && (me?.adsT ?? 0) > 0.92 && (me?.alive ?? false);

  void _render(GameSim s, Player p, GunDef g, double dt) {
    final js = engine.js;
    // Viewmodel model follows character + current gun.
    final key = '${p.charId}/${p.gunId}';
    if (key != _vmKey) {
      _vmKey = key;
      js.setViewmodel(p.charId, g.id, jsNums(g.info.adsHold), jsNums(g.info.adsSight), g.info.adsEye);
    }

    js.vmMode(p.alive && const {'shuriken', 'twin', 'guard'}.contains(p.mode) ? p.mode : '');
    if (p.alive) {
      final (rp, _) = g.recoilAt(p.recoilIndex);
      final kick = rp * 0.25;
      final e = p.eye;
      js.setCamera(e.x, e.y, e.z, yaw, pitch + kick, _fov(p));
      final sp = p.onGround ? math.min(p.vel.lengthXZ / 5.5, 1.0) : 0.0;
      final bx = math.sin(_t * 9) * 0.008 * sp, by = -(math.cos(_t * 18).abs()) * 0.008 * sp;
      // Rolling: no gun in hand.
      js.vmPose(p.adsT, bx, by, rp, !scoped && p.mode != 'roll');
    } else {
      final e = _deathEye ?? p.eye;
      js.setCamera(e.x, e.y, e.z, _deathYaw, _deathPitch, settings.fov);
      js.vmPose(0, 0, 0, 0, false);
    }

    for (final q in s.players.values) {
      if (q.id == p.id) continue;
      // Online: smooth the 20 Hz snapshot positions of other players.
      var rp = q.pos;
      if (online) {
        final cur = _rpos[q.id];
        if (cur == null || cur.distanceTo(q.pos) > 4 || !q.alive) {
          _rpos[q.id] = q.pos.copy();
        } else {
          final k = 1 - math.exp(-dt * 18);
          cur.set(cur.x + (q.pos.x - cur.x) * k, cur.y + (q.pos.y - cur.y) * k, cur.z + (q.pos.z - cur.z) * k);
        }
        rp = _rpos[q.id]!;
      }
      js.setPlayer(q.id, q.charId, q.gunId, q.team, q.team == p.team, rp.x, rp.y, rp.z, q.yaw, q.pitch,
          q.vel.lengthXZ, q.alive, q.crouch, q.revealed > 0 && q.team != p.team, _aura(s, q),
          q.mode == 'roll' ? (skillFiles['crate_roll'] ?? '') : '', q.onGround);
    }
    for (final pj in s.projectiles) {
      js.setProjectile(pj.id, skillFiles[pj.gun] ?? '', pj.pos.x, pj.pos.y, pj.pos.z);
    }
    js.pruneProjectiles();
    for (final d in s.deployables) {
      if (d.team != p.team && _hiddenTraps.contains(d.kind)) continue;
      final shape = _depShape[d.kind] ?? 0;
      final r = d.kind == 'ink_cloud' ? (skillImpls['ink_cloud']?.smokeRadius(d) ?? d.radius) : d.radius;
      js.setDeployable(d.id, shape == 2 || shape == 4 ? '' : (skillFiles[d.kind] ?? ''), shape, d.pos.x, d.pos.y,
          d.pos.z, d.yaw, r, d.team, d.team == p.team, d.maxHp > 0 ? d.hp / d.maxHp : 1);
    }
    js.pruneDeployables();
    final links = <double>[];
    for (final q in s.players.values) {
      final t = q.fx['linkTo'];
      if (!q.alive || t == null) continue;
      final o = s.players[t.toInt()];
      if (o == null || !o.alive) continue;
      final a = q.id == p.id ? p.eye + p.viewDir * 0.6 : Vec3(q.pos.x, q.pos.y + 1.3, q.pos.z);
      links.addAll([a.x, a.y - 0.25, a.z, o.pos.x, o.pos.y + 1.1, o.pos.z]);
    }
    js.setLinks(jsNums(links));
    final c = s.map.capture;
    final zoneColor = s.owner < 0 ? 0xf4eee2 : (s.owner == p.team ? 0x4d8cf0 : 0xff5a4a);
    js.setCaptureZone(c.x, c.y, c.z, s.map.captureRadius, zoneColor, s.contested);
  }

  void _footsteps(GameSim s, Player me, double dt) {
    final surf = _surface[def.id] ?? 'concrete';
    for (final q in s.players.values) {
      if (!q.alive || !q.onGround || q.crouch) continue;
      final sp = q.vel.lengthXZ;
      if (sp < 1) continue;
      final d = me.pos.distanceTo(q.pos);
      if (q.id != me.id && d > 35) continue;
      final run = sp > 4 && !q.walking;
      _stride[q.id] = (_stride[q.id] ?? 0) + sp * dt;
      if (_stride[q.id]! < (run ? 2.0 : 1.5)) continue;
      _stride[q.id] = 0;
      final n = (_stepN[q.id] = ((_stepN[q.id] ?? 0) % 4) + 1);
      final rate = 0.95 + 0.1 * math.Random().nextDouble();
      final name = 'step_${surf}_${run ? 'run' : 'walk'}_$n';
      if (q.id == me.id) {
        engine.sfx(name, vol: 0.35, rate: rate);
      } else {
        engine.sfx(name, vol: q.walking ? 0.25 : 0.7, rate: rate, pos: [q.pos.x, q.pos.y, q.pos.z]);
      }
    }
  }

  void _banner(String t) {
    banner = t;
    bannerTime = 3;
  }

  MatchResult result() {
    final s = sim!;
    return MatchResult(
      s.winner,
      me!.team,
      [...s.score],
      [for (final p in s.players.values) ScoreRow(p, p.id == me!.id)]..sort((a, b) => b.kills.compareTo(a.kills)),
      def.id,
      s.time,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _netSub?.cancel();
    net?.close();
    final js = engine.js;
    engine.setTick(null);
    js.clearPlayers();
    js.clearFx();
    js.setGrayscale(false);
    engine.input.unlock();
    engine.audio.playMusic('rps_arena');
    super.dispose();
  }
}
