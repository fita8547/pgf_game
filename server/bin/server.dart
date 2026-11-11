// RPS match server: WebSocket game server + static file server for the web
// client, in one process so LAN players only need a browser.
//
//   cd server && dart run bin/server.dart [--port 8080] [--maps rps_arena,desert_ruins]
//                                         [--web ../client/build/web] [--assets ../rps_assets]
//                                         [--bots 0.5] [--team 5] [--data data/user_settings.json]
import 'dart:io';

import 'package:rps_server/rps_server.dart';
import 'package:rps_shared/rps_shared.dart';

Future<void> main(List<String> args) async {
  String opt(String name, String def) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : def;
  }

  final port = int.parse(opt('port', '8080'));
  final web = opt('web', '../client/build/web');
  final assets = opt('assets', '../rps_assets');
  final rotation = opt('maps', 'rps_arena,desert_ruins,frost_harbor,jungle_temple').split(',');
  final room = Room(
    assetsDir: assets,
    rotation: rotation,
    cfg: SimConfig(botSkill: double.parse(opt('bots', '0.5')), teamSize: int.parse(opt('team', '5'))),
    log: (m) => stdout.writeln('[${DateTime.now().toIso8601String().substring(11, 19)}] $m'),
  )..start();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  final statics = StaticFiles(web);
  final userSettings = UserSettingsStore(opt('data', 'data/user_settings.json'));
  stdout.writeln('user settings: ${userSettings.file.path} (${userSettings.length} players)');
  ProcessSignal.sigint.watch().listen((_) {
    userSettings.saveNow();
    exit(0);
  });
  stdout.writeln('RPS server on http://localhost:$port  (game: ws://<host>:$port${Net.path})');
  for (final ip in await _lanAddresses()) {
    stdout.writeln('  LAN: http://$ip:$port');
  }

  await for (final req in server) {
    if (req.uri.path == Net.path && WebSocketTransformer.isUpgradeRequest(req)) {
      final addr = req.connectionInfo?.remoteAddress.address ?? '?';
      WebSocketTransformer.upgrade(req).then((ws) => room.accept(ws, addr), onError: (_) {});
    } else if (!await userSettings.handle(req)) {
      statics.serve(req);
    }
  }
}

Future<List<String>> _lanAddresses() async {
  final out = <String>[];
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      if (!a.isLoopback) out.add(a.address);
    }
  }
  return out;
}
