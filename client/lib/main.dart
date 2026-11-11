import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'engine/engine.dart';
import 'game/game_controller.dart';
import 'game/net_client.dart';
import 'screens/game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/result_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/title_screen.dart';
import 'ui/i18n.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Rps.dark = Settings.I.dark;
  runApp(const RpsApp());
}

enum Screen { splash, title, lobby, game, result, exited }

class RpsApp extends StatefulWidget {
  const RpsApp({super.key});

  @override
  State<RpsApp> createState() => _RpsAppState();
}

class _RpsAppState extends State<RpsApp> {
  Screen screen = Screen.splash;
  final _nav = GlobalKey<NavigatorState>();

  // Splash progress.
  double _bootProgress = 0;
  String _bootStatus = '';

  // Network watch: offline event or the server not answering -> alert, exit.
  Timer? _netTimer;
  int _netFails = 0;
  bool _exiting = false;
  JSFunction? _offlineFn;

  void _onSettings() => setState(() {
    Rps.dark = Settings.I.dark;
    _applyPageBackground();
  });

  @override
  void dispose() {
    Settings.langChanged.removeListener(_onSettings);
    _netTimer?.cancel();
    if (_offlineFn != null) web.window.removeEventListener('offline', _offlineFn);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Settings.langChanged.addListener(_onSettings);
    _applyPageBackground();
    _boot();
  }

  /// Page colour behind the 3D canvas (the lobby shows through it).
  void _applyPageBackground() {
    try {
      web.document.body?.style.background = Rps.dark ? '#0d1233' : '#f7f3ea';
    } catch (_) {}
  }

  void _step(double p, String status) {
    if (!mounted) return;
    setState(() {
      _bootProgress = p;
      _bootStatus = status;
    });
  }

  /// Splash: engine -> server check -> saved settings -> images -> title.
  Future<void> _boot() async {
    final started = DateTime.now();
    _step(0.1, tr('엔진 불러오는 중...', 'Loading engine...'));
    await Engine.ready();
    final s = Settings.I;
    // Phones: start on low graphics unless the player picked something.
    if (Engine.I.input.isTouch() && !s.qualitySaved) s.quality = 0;
    Engine.I.audio.setVolumes(s.sfxVolume, s.musicVolume);
    Engine.I.js.setQuality(s.quality);

    _step(0.4, tr('서버 연결 확인 중...', 'Checking the server...'));
    if (!await Settings.serverReachable()) {
      _fatalNetwork();
      return;
    }
    _step(0.6, tr('설정 불러오는 중...', 'Loading settings...'));
    await s.pullFromServer();
    _onSettings();

    _step(0.8, tr('이미지 불러오는 중...', 'Loading images...'));
    if (mounted) {
      await Future.wait([
        for (final a in ['assets/logo/origami.png', 'assets/logo/wide.png'])
          precacheImage(AssetImage(a), context).catchError((_) {}),
      ]);
    }
    _step(1, tr('준비 완료', 'Ready'));
    final wait = const Duration(milliseconds: 1400) - DateTime.now().difference(started);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (!mounted || _exiting) return;

    _startNetWatch();
    // Dev shortcuts: ?screen=lobby | ?screen=game[&map=<id>][&char=<id>]
    final q = Uri.base.queryParameters;
    if (q['map'] != null) s.mapId = q['map']!;
    if (q['char'] != null) s.charId = q['char']!;
    setState(() {
      switch (q['screen']) {
        case 'lobby':
          screen = Screen.lobby;
        case 'game':
          final srv = q['server'];
          game = GameController(s, serverUrl: srv == null ? null : (srv.isEmpty ? NetClient.defaultUrl() : srv));
          screen = Screen.game;
        default:
          screen = Screen.title;
      }
    });
  }

  void _startNetWatch() {
    _offlineFn = ((web.Event _) {
      _fatalNetwork();
    }).toJS;
    web.window.addEventListener('offline', _offlineFn);
    _netTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_exiting) return;
      if (await Settings.serverReachable()) {
        _netFails = 0;
      } else if (++_netFails >= 2) {
        _fatalNetwork();
      }
    });
  }

  /// No network: tell the player, then shut the app down.
  Future<void> _fatalNetwork() async {
    if (_exiting) return;
    _exiting = true;
    _netTimer?.cancel();
    try {
      Engine.I.input.unlock();
    } catch (_) {}
    final ctx = _nav.currentContext;
    if (ctx != null) {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.wifi_off, size: 40),
          title: Text(tr('네트워크 연결 불가', 'No network connection')),
          content: Text(
            tr('서버에 연결할 수 없습니다.\n확인을 누르면 앱을 종료합니다.', 'Cannot reach the server.\nPress OK to close the app.'),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('확인', 'OK')))],
        ),
      );
    }
    _exit();
  }

  void _exit() {
    game?.dispose();
    game = null;
    try {
      Engine.I.audio.stopMusic();
    } catch (_) {}
    if (mounted) setState(() => screen = Screen.exited);
    // Closes the tab when the browser allows it (opened by script / PWA).
    web.window.close();
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
      navigatorKey: _nav,
      theme: Rps.theme(),
      builder: (context, child) => _UiScale(fontScale: Settings.I.fontScale, child: child!),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (screen) {
            Screen.splash => SplashScreen(key: const ValueKey('splash'), progress: _bootProgress, status: _bootStatus),
            Screen.exited => const ExitedScreen(key: ValueKey('exited')),
            Screen.title => TitleScreen(key: const ValueKey('title'), onStart: () => _go(Screen.lobby)),
            Screen.lobby => LobbyScreen(
              key: const ValueKey('lobby'),
              onPlay: _startMatch,
              onPlayOnline: () => _startMatch(online: true),
              onBack: () => _go(Screen.title),
            ),
            Screen.game => GameScreen(key: const ValueKey('game'), game: game!, onEnd: _endMatch, onLeave: _leaveMatch),
            Screen.result => ResultScreen(
              key: const ValueKey('result'),
              result: result!,
              onContinue: () => _go(Screen.lobby),
            ),
          },
        ),
      ),
    );
  }
}

/// Small screens (phones): lay the UI out on a larger virtual canvas and
/// scale it down, so the HUD and menus keep their desktop proportions.
/// Also applies the player's font size setting to all text.
class _UiScale extends StatelessWidget {
  const _UiScale({required this.child, required this.fontScale});
  final Widget child;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final mq0 = MediaQuery.of(context);
    final mq = mq0.copyWith(textScaler: TextScaler.linear(fontScale));
    final size = mq.size;
    final fit = math.min(size.width / 1280, size.height / 720);
    if (fit >= 0.95 || size.isEmpty) return MediaQuery(data: mq, child: child);
    final scale = math.max(0.6, fit);
    final virtual = size / scale;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: virtual,
        child: MediaQuery(
          data: mq.copyWith(size: virtual, padding: mq.padding / scale),
          child: child,
        ),
      ),
    );
  }
}
