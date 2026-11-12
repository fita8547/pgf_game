import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Player settings, kept in localStorage. Dark mode and font size are also
/// stored on the server (per anonymous client id) and loaded from there at
/// startup, so they survive restarts and cleared caches of the server side.
class Settings {
  Settings._();

  /// Bumped when the language / theme / font size changes; the app rebuilds on it.
  static final ValueNotifier<int> langChanged = ValueNotifier(0);

  /// Dark mode (whole app). Saved on the server.
  bool dark = true;

  /// UI text scale 0.85..1.3. Saved on the server.
  double fontScale = 1.0;
  static const fontScales = [0.85, 1.0, 1.15, 1.3];

  /// Random id for this browser, used as the key on the server.
  String clientId = '';
  static final Settings I = Settings._()..load();

  /// Radians per mouse pixel.
  double sensitivity = 0.0022;
  double sfxVolume = 0.8;
  double musicVolume = 0.3;

  /// Agent voice lines.
  double voiceVolume = 0.9;
  double fov = 70;
  String charId = 'pebble';
  String mapId = 'rps_arena';
  double botSkill = 0.5;
  String name = '플레이어';

  /// UI language: 'ko' or 'en'.
  String lang = 'ko';

  /// Last online server (empty = the host that served this page).
  String server = '';

  /// Graphics: 0 low, 1 medium, 2 high.
  int quality = 2;
  bool qualitySaved = false;

  void load() {
    try {
      final s = web.window.localStorage;
      double d(String k, double v) => double.tryParse(s.getItem('rps.$k') ?? '') ?? v;
      sensitivity = d('sens', sensitivity);
      sfxVolume = d('sfx', sfxVolume);
      musicVolume = d('music', musicVolume);
      voiceVolume = d('voice', voiceVolume);
      fov = d('fov', fov);
      botSkill = d('bot', botSkill);
      charId = s.getItem('rps.char') ?? charId;
      mapId = s.getItem('rps.map') ?? mapId;
      name = s.getItem('rps.name') ?? name;
      server = s.getItem('rps.server') ?? server;
      dark = s.getItem('rps.dark') != 'false';
      fontScale = (double.tryParse(s.getItem('rps.font') ?? '') ?? 1.0).clamp(0.85, 1.3);
      clientId = s.getItem('rps.cid') ?? '';
      if (clientId.length < 8) {
        final r = math.Random.secure();
        clientId = List.generate(24, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[r.nextInt(36)]).join();
        s.setItem('rps.cid', clientId);
      }
      lang = s.getItem('rps.lang') ?? (web.window.navigator.language.startsWith('ko') ? 'ko' : 'en');
      final q = int.tryParse(s.getItem('rps.quality') ?? '');
      qualitySaved = q != null;
      quality = q ?? quality;
    } catch (_) {
      // Private mode / blocked storage: defaults are fine.
    }
  }

  void save() {
    try {
      final s = web.window.localStorage;
      s.setItem('rps.sens', '$sensitivity');
      s.setItem('rps.sfx', '$sfxVolume');
      s.setItem('rps.music', '$musicVolume');
      s.setItem('rps.voice', '$voiceVolume');
      s.setItem('rps.fov', '$fov');
      s.setItem('rps.bot', '$botSkill');
      s.setItem('rps.char', charId);
      s.setItem('rps.map', mapId);
      s.setItem('rps.name', name);
      s.setItem('rps.server', server);
      s.setItem('rps.lang', lang);
      s.setItem('rps.dark', '$dark');
      s.setItem('rps.font', '$fontScale');
      s.setItem('rps.quality', '$quality');
    } catch (_) {}
  }

  // ------------------------------------------------------------ server --
  /// Built with `--dart-define=STANDALONE=true`: no game server (hosted as a
  /// static page). Bot practice only; settings stay in this browser.
  static const bool standalone = bool.fromEnvironment('STANDALONE');

  /// API base: the server that served this page.
  static String get apiBase => web.window.location.origin;

  static Future<String> _fetch(String method, String path, [Object? body]) async {
    final init = web.RequestInit(method: method, cache: 'no-store');
    if (body != null) {
      init.body = jsonEncode(body).toJS;
      init.headers = {'Content-Type': 'application/json'}.jsify() as web.HeadersInit;
    }
    final res = await web.window.fetch('$apiBase$path'.toJS, init).toDart.timeout(const Duration(seconds: 5));
    if (!res.ok) throw StateError('HTTP ${res.status}');
    return (await res.text().toDart).toDart;
  }

  /// True if the game server answers.
  static Future<bool> serverReachable() async {
    if (standalone) return true;
    try {
      final m = jsonDecode(await _fetch('GET', '/api/health'));
      return m is Map && m['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Loads dark mode / font size from the server (server wins over local).
  Future<bool> pullFromServer() async {
    if (standalone) return true;
    try {
      final m = jsonDecode(await _fetch('GET', '/api/settings?cid=$clientId')) as Map<String, dynamic>;
      if (m['dark'] is bool) dark = m['dark'] as bool;
      if (m['fontScale'] is num) fontScale = (m['fontScale'] as num).toDouble().clamp(0.85, 1.3);
      save();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves dark mode / font size locally and on the server.
  Future<bool> pushToServer() async {
    save();
    if (standalone) return true;
    try {
      await _fetch('PUT', '/api/settings?cid=$clientId', {'dark': dark, 'fontScale': fontScale});
      return true;
    } catch (_) {
      return false;
    }
  }
}
