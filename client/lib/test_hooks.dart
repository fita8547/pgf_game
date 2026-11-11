import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/semantics.dart';

import 'game/game_controller.dart';
import 'ui/settings.dart';

/// Integration-test hooks, only with `?test` in the URL
/// (client/tool/integration/emulator_test.py drives the app through them).
///
/// - Turns on Flutter semantics, so every button/label is a DOM node the test
///   can find by its text and tap at its real position.
/// - `window.rpsTest.state()` returns a JSON snapshot of app state the test
///   asserts on (screen, theme, font size, dialogs, skeletons, match state).
abstract final class TestHooks {
  static final bool enabled = Uri.base.queryParameters.containsKey('test');

  // Filled in by the app.
  static String screen = '';
  static String bootStatus = '';
  static double bootProgress = 0;
  static String dialog = '';
  static int shimmers = 0; // skeleton shimmers created
  static int hudSkeletons = 0; // HUD skeleton frames built while a match loads
  static GameController? game;

  static void install() {
    if (!enabled) return;
    SemanticsBinding.instance.ensureSemantics();
    final o = JSObject();
    o['state'] = (() => jsonEncode(_state()).toJS).toJS;
    globalContext['rpsTest'] = o;
  }

  static Map<String, Object?> _state() {
    final s = Settings.I;
    final g = game;
    final p = g?.me;
    final sim = g?.sim;
    return {
      'screen': screen,
      'boot': bootStatus,
      'bootProgress': bootProgress,
      'dialog': dialog,
      'dark': s.dark,
      'fontScale': s.fontScale,
      'lang': s.lang,
      'cid': s.clientId,
      'shimmers': shimmers,
      'hudSkeletons': hudSkeletons,
      if (g != null)
        'game': {
          'loading': g.loading,
          'error': g.error,
          'locked': g.locked,
          'shopOpen': g.shopOpen,
          if (sim != null) 'phase': sim.phase.name,
          if (sim != null) 'time': sim.time,
          if (p != null) ...{
            'char': p.charId,
            'alive': p.alive,
            'hp': p.hp,
            'armor': p.armor,
            'credits': p.credits,
            'pos': [p.pos.x, p.pos.y, p.pos.z],
            'yaw': g.yaw,
            'mag': p.mag,
            'reserve': p.reserve,
            'shotSeq': p.shotSeq,
            'spawnProtect': p.spawnProtect,
            'skillCharges': p.skillCharges,
            'inSpawn': sim?.map.inSpawnRoom(p.team, p.pos),
          },
        },
    };
  }
}
