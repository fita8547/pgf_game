import 'package:flutter/material.dart';

import 'engine/engine.dart';
import 'game/game_controller.dart';
import 'game/net_client.dart';
import 'screens/game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/result_screen.dart';
import 'screens/title_screen.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Engine.ready();
  final s = Settings.I;
  Engine.I.audio.setVolumes(s.sfxVolume, s.musicVolume);
  runApp(const RpsApp());
}

enum Screen { title, lobby, game, result }

class RpsApp extends StatefulWidget {
  const RpsApp({super.key});

  @override
  State<RpsApp> createState() => _RpsAppState();
}

class _RpsAppState extends State<RpsApp> {
  Screen screen = Screen.title;

  @override
  void initState() {
    super.initState();
    // Dev shortcuts: ?screen=lobby | ?screen=game[&map=<id>][&char=<id>]
    final q = Uri.base.queryParameters;
    if (q['map'] != null) Settings.I.mapId = q['map']!;
    if (q['char'] != null) Settings.I.charId = q['char']!;
    switch (q['screen']) {
      case 'lobby':
        screen = Screen.lobby;
      case 'game':
        final srv = q['server'];
        game = GameController(Settings.I, serverUrl: srv == null ? null : (srv.isEmpty ? NetClient.defaultUrl() : srv));
        screen = Screen.game;
    }
  }

  GameController? game;
  MatchResult? result;

  void _go(Screen s) => setState(() => screen = s);

  Future<void> _startMatch({bool online = false}) async {
    final s = Settings.I;
    final g = GameController(s, serverUrl: online ? (s.server.isEmpty ? NetClient.defaultUrl() : s.server) : null);
    setState(() {
      game = g;
      screen = Screen.game;
    });
  }

  void _endMatch(MatchResult r) {
    game?.dispose();
    setState(() {
      game = null;
      result = r;
      screen = Screen.result;
    });
  }

  void _leaveMatch() {
    game?.dispose();
    setState(() {
      game = null;
      screen = Screen.lobby;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RPS',
      debugShowCheckedModeBanner: false,
      theme: Rps.theme(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (screen) {
            Screen.title => TitleScreen(key: const ValueKey('title'), onStart: () => _go(Screen.lobby)),
            Screen.lobby => LobbyScreen(
                key: const ValueKey('lobby'),
                onPlay: _startMatch,
                onPlayOnline: () => _startMatch(online: true),
                onBack: () => _go(Screen.title)),
            Screen.game => GameScreen(key: const ValueKey('game'), game: game!, onEnd: _endMatch, onLeave: _leaveMatch),
            Screen.result => ResultScreen(key: const ValueKey('result'), result: result!, onContinue: () => _go(Screen.lobby)),
          },
        ),
      ),
    );
  }
}
