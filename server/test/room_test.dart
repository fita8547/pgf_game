import 'dart:async';
import 'dart:io';

import 'package:rps_server/rps_server.dart';
import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

void main() {
  late Room room;
  late HttpServer server;

  setUpAll(() async {
    room = Room(assetsDir: '../rps_assets', rotation: ['rps_arena'], cfg: const SimConfig(pregame: 0), log: (_) {})
      ..start();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) room.accept(await WebSocketTransformer.upgrade(req), 'test');
    });
  });

  tearDownAll(() async {
    room.stop();
    await server.close(force: true);
  });

  Future<(WebSocket, Stream<Map<String, dynamic>>)> connect() async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}${Net.path}');
    final stream = ws.map((d) => Net.decode(d as String)).asBroadcastStream();
    return (ws, stream);
  }

  test('join replaces a bot, snapshots arrive, inputs move the player', () async {
    final (ws, msgs) = await connect();
    ws.add(Net.encode(Net.hello('tester', 'snip')));
    final welcome = await msgs.firstWhere((m) => m['t'] == 'welcome').timeout(const Duration(seconds: 5));
    final id = welcome['id'] as int;
    expect(welcome['map'], 'rps_arena');
    expect(room.sim.players.length, 10, reason: 'a bot made room for the human');
    expect(room.sim.players[id]!.isBot, isFalse);

    List row(Map<String, dynamic> snap) => (snap['s']['p'] as List).firstWhere((r) => r[0] == id) as List;
    final first = await msgs.firstWhere((m) => m['t'] == 'snap');
    final z0 = (row(first)[7] as num).toDouble();

    // Walk forward for ~1 s in real time (60 frames of 1/60 s).
    var seq = 0;
    for (var k = 0; k < 20; k++) {
      ws.add(Net.encode(Net.inputs([
        for (var j = 0; j < 3; j++) PlayerInput(seq: ++seq, dt: 1 / 60, moveZ: 1, yaw: room.sim.players[id]!.yaw),
      ])));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final later = await msgs.firstWhere((m) => m['t'] == 'snap' && (m['ack'] as int) >= seq);
    final z1 = (row(later)[7] as num).toDouble();
    expect((z1 - z0).abs(), greaterThan(2), reason: 'moved from $z0 to $z1');
    await ws.close();
  });

  test('speedhack frames are dropped by the input guard', () async {
    final (ws, msgs) = await connect();
    ws.add(Net.encode(Net.hello('cheater', 'pebble')));
    final id = (await msgs.firstWhere((m) => m['t'] == 'welcome'))['id'] as int;
    final p = room.sim.players[id]!;
    final start = p.pos.copy();
    // 5 seconds of movement sent in one burst.
    var seq = 0;
    for (var k = 0; k < 10; k++) {
      ws.add(Net.encode(Net.inputs([
        for (var j = 0; j < 30; j++) PlayerInput(seq: ++seq, dt: 1 / 60, moveZ: 1, yaw: p.yaw),
      ])));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final moved = p.pos.distanceXZ(start);
    expect(moved, lessThan(3.5), reason: 'only ~0.55 s of movement may be applied, moved $moved');
    await ws.close();
  });

  test('leaving puts a bot back', () async {
    final (ws, msgs) = await connect();
    ws.add(Net.encode(Net.hello('brief', 'gem')));
    await msgs.firstWhere((m) => m['t'] == 'welcome');
    await ws.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(room.sim.players.length, 10);
  });
}
