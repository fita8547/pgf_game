import 'dart:async';
import 'dart:io';

import 'package:rps_shared/rps_shared.dart';

/// One connected client.
class Client {
  final WebSocket ws;
  final String addr;
  final InputGuard guard = InputGuard();
  Player? player;

  /// Touch controls (from hello): kept across map changes.
  bool touch = false;
  Client(this.ws, this.addr);

  void send(Map<String, Object?> m) {
    if (ws.readyState == WebSocket.open) ws.add(Net.encode(m));
  }
}

/// A match: authoritative sim at [Net.tickHz], bots fill empty slots, a new
/// match starts on the next map when one ends.
class Room {
  final String assetsDir;
  final List<String> rotation;
  final SimConfig cfg;
  final void Function(String) log;

  final Set<Client> clients = {};
  late GameSim sim;
  int _mapIndex = 0;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  double _acc = 0;
  final List<Map<String, Object?>> _pending = [];
  double _restartIn = -1;

  Room({required this.assetsDir, required this.rotation, this.cfg = const SimConfig(), this.log = print});

  String get mapId => sim.map.def.id;

  void start() {
    _loadMap(rotation.first);
    _clock.start();
    var last = _clock.elapsedMicroseconds;
    _timer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final now = _clock.elapsedMicroseconds;
      _step((now - last) / 1e6);
      last = now;
    });
  }

  void stop() => _timer?.cancel();

  void _loadMap(String id) {
    final def = mapById(id);
    final map = GameMap.fromGlb(def, File('$assetsDir/${def.file}').readAsBytesSync());
    final old = clients.where((c) => c.player != null).toList();
    sim = GameSim(map, cfg: cfg, seed: DateTime.now().millisecondsSinceEpoch & 0x7fffffff);
    for (final c in old) {
      final p = c.player!;
      c.player = _join(p.name, p.charId)..touch = c.touch;
      c.send({'t': 'welcome', 'id': c.player!.id, 'map': id, 'tick': sim.tick, 'hz': Net.tickHz});
    }
    sim.fillBots();
    _pending.clear();
    log('map $id (${clients.length} clients)');
  }

  /// Puts a human on the team with fewer humans, replacing one of its bots.
  Player _join(String name, String charId) {
    int humans(int t) => sim.team(t).where((p) => !p.isBot).length;
    final t = humans(0) <= humans(1) ? 0 : 1;
    final bot = sim.team(t).where((p) => p.isBot).firstOrNull;
    if (bot != null) sim.removePlayer(bot.id);
    return sim.addPlayer(name, charId, teamId: t);
  }

  void _leave(Player p) {
    final t = p.team;
    sim.removePlayer(p.id);
    if (sim.team(t).length < cfg.teamSize) sim.fillBots();
  }

  // ------------------------------------------------------------ clients --
  void accept(WebSocket ws, String addr) {
    final c = Client(ws, addr);
    clients.add(c);
    ws.listen((data) {
      if (data is! String || data.length > 64 * 1024) return;
      try {
        _onMessage(c, Net.decode(data));
      } catch (e) {
        c.send({'t': 'err', 'm': 'bad message'});
      }
    }, onDone: () => _drop(c), onError: (_) => _drop(c));
  }

  void _drop(Client c) {
    if (!clients.remove(c)) return;
    final p = c.player;
    if (p != null && sim.players.containsKey(p.id)) _leave(p);
    log('left ${p?.name ?? c.addr}');
  }

  void _onMessage(Client c, Map<String, dynamic> m) {
    switch (m['t']) {
      case 'hello':
        if (c.player != null) return;
        if (m['v'] != Net.version) {
          c.send({'t': 'err', 'm': '버전이 맞지 않습니다. 새로고침 해주세요. / Version mismatch, please refresh.'});
          return;
        }
        var name = '${m['name'] ?? '플레이어'}'.trim();
        if (name.isEmpty || name.length > 16) name = name.isEmpty ? '플레이어' : name.substring(0, 16);
        final ch = '${m['char']}';
        c.touch = m['touch'] == true;
        c.player = _join(name, isCharacter(ch) ? ch : characters.first.id)..touch = c.touch;
        c.send({'t': 'welcome', 'id': c.player!.id, 'map': mapId, 'tick': sim.tick, 'hz': Net.tickHz});
        _broadcast({'t': 'msg', 'm': '$name 님이 참가했습니다', 'join': name});
        log('joined $name (${c.addr}) team ${c.player!.team}');
      case 'in':
        final p = c.player;
        if (p == null || !sim.players.containsKey(p.id)) return;
        final list = m['i'];
        if (list is! List || list.length > 32) return;
        for (final row in list) {
          final inp = c.guard.accept(PlayerInput.fromNet(row as List));
          if (inp != null) sim.processInput(p, inp);
        }
        if (c.guard.suspicious) {
          log('kick ${p.name}: input guard');
          c.ws.close(4001, 'input');
        }
      case 'buy':
        final p = c.player;
        if (p == null) return;
        final err = sim.buy(p, '${m['g']}');
        if (err != null) c.send({'t': 'err', 'm': err, 'code': err});
      case 'char':
        final p = c.player;
        if (p == null) return;
        final err = sim.pickCharacter(p, '${m['c']}');
        if (err != null) c.send({'t': 'err', 'm': err});
      case 'ping':
        c.send({'t': 'pong', 'c': m['c'], 's': sim.tick});
    }
  }

  void _broadcast(Map<String, Object?> m) {
    final s = Net.encode(m);
    for (final c in clients) {
      if (c.ws.readyState == WebSocket.open) c.ws.add(s);
    }
  }

  // --------------------------------------------------------------- tick --
  void _step(double dt) {
    const step = 1 / Net.tickHz;
    _acc = (_acc + dt).clamp(0, step * 10);
    while (_acc >= step) {
      _acc -= step;
      for (final c in clients) {
        c.guard.tick(step);
      }
      sim.update(step);
      _pending.addAll(sim.events);
      sim.events.clear();
      if (sim.tick % Net.snapEvery == 0) _snapshot();
      if (sim.phase == Phase.ended) {
        if (_restartIn < 0) _restartIn = 10;
        _restartIn -= step;
        if (_restartIn <= 0) {
          _restartIn = -1;
          _mapIndex = (_mapIndex + 1) % rotation.length;
          _loadMap(rotation[_mapIndex]);
        }
      }
    }
  }

  void _snapshot() {
    if (clients.isEmpty) {
      _pending.clear();
      return;
    }
    final snap = sim.snapshot();
    final ev = List.of(_pending);
    _pending.clear();
    for (final c in clients) {
      final p = c.player;
      if (p == null) continue;
      c.send({'t': 'snap', 's': snap, 'ev': ev, 'ack': c.guard.lastSeq});
    }
  }
}
