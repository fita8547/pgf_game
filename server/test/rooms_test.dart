import 'dart:io';

import 'package:rps_server/rps_server.dart';
import 'package:rps_shared/rps_shared.dart';
import 'package:test/test.dart';

void main() {
  test('players fill room 1 first, then room 2, then the emptiest', () async {
    // teamSize 1: two seats per room.
    final rooms = [
      for (var n = 1; n <= 2; n++)
        Room(
          assetsDir: '../rps_assets',
          rotation: ['rps_arena'],
          cfg: const SimConfig(pregame: 0, teamSize: 1),
          number: n,
          log: (_) {},
        )..start(),
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (WebSocketTransformer.isUpgradeRequest(req))
        pickRoom(rooms).accept(await WebSocketTransformer.upgrade(req), 't');
    });
    final sockets = <WebSocket>[];
    final got = <int>[];
    for (var i = 0; i < 5; i++) {
      final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}${Net.path}');
      sockets.add(ws);
      final msgs = ws.map((d) => Net.decode(d as String)).asBroadcastStream();
      ws.add(Net.encode(Net.hello('p$i', 'snip')));
      final w = await msgs.firstWhere((m) => m['t'] == 'welcome').timeout(const Duration(seconds: 5));
      got.add(w['room'] as int);
    }
    expect(got, [1, 1, 2, 2, 1]);
    expect(rooms[0].clients.length, 3);
    expect(rooms[1].clients.length, 2);
    for (final ws in sockets) {
      await ws.close();
    }
    for (final r in rooms) {
      r.stop();
    }
    await server.close(force: true);
  });
}
