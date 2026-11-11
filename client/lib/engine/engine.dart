/// Dart bindings for web/engine/rps_engine.js (three.js renderer, Web Audio,
/// raw input). Game logic stays in Dart; this only draws and plays sounds.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('rpsEngine')
external RpsEngine? get _engine;

extension type RpsEngine._(JSObject _) implements JSObject {
  // lobby
  external JSPromise<JSAny?> showLobby(String charId, String gunId);
  external void setLobbyOffset(double x);
  external void hideAll();

  // game
  external JSPromise<JSAny?> loadMap(String mapId);
  external JSPromise<JSAny?> preload(JSArray<JSString> paths);
  external void setCamera(double x, double y, double z, double yaw, double pitch, double fov);
  external void setGrayscale(bool on);

  // viewmodel
  external JSPromise<JSAny?> setViewmodel(
      String charId, String gunId, JSArray<JSNumber> hold, JSArray<JSNumber> sight, double eye);
  external void vmPlay(String name, double speed);
  external void vmPlayFor(String name, double seconds);
  external void vmFire(double fireRate, String? follow, double frac);
  external void vmPose(double adsT, double bobX, double bobY, double kick, bool visible);

  // world
  external void setPlayer(int id, String charId, String gunId, int team, bool friendly, double x, double y, double z,
      double yaw, double pitch, double speed, bool alive, bool crouch, bool revealed, int aura, String ball, bool onGround);
  external void playerAction(int id, String name);
  external JSPromise<JSAny?> vmSkill(String anim, String item);
  external JSPromise<JSAny?> vmMode(String mode);
  external void vmModeAttack();
  external JSPromise<JSAny?> matchEnd(bool won);
  external void setDeployable(int id, String file, int shape, double x, double y, double z, double yaw, double radius,
      int team, bool friendly, double hpFrac);
  external void pruneDeployables();
  external void setProjectile(int id, String file, double x, double y, double z);
  external void pruneProjectiles();
  external void setLinks(JSArray<JSNumber> flat);
  external void burst(double x, double y, double z, int color, double size, double life);
  external JSPromise<JSAny?> skillFx(
      String kind, double ax, double ay, double az, double bx, double by, double bz, double r);
  external void removePlayer(int id);
  external void clearPlayers();
  external void setProjectiles(JSArray<JSNumber> flat);
  external void tracer(double ox, double oy, double oz, double ex, double ey, double ez, int hit, JSAny? from);
  external void explosion(double x, double y, double z, double r);
  external JSPromise<JSAny?> killBadge(String kind);
  external JSPromise<JSAny?> deathGhost(String kind, double x, double y, double z, double yaw);
  external void clearFx();
  external void setCaptureZone(double x, double y, double z, double r, int color, bool contested);
  external void damageNumber(int victimId, double x, double y, double z, double amount, int kind);

  external RpsAudio get audio;
  external RpsInput get input;
  external set tick(JSFunction? f);
}

extension type RpsAudio._(JSObject _) implements JSObject {
  external JSObject? ensure();
  external void preload(JSArray<JSString> names);
  external JSPromise<JSAny?> play(String name, double vol, double rate, JSArray<JSNumber>? pos);
  external JSPromise<JSAny?> playMusic(String mapId);
  external void stopMusic();
  external void setVolumes(double sfx, double music);
}

extension type RpsInput._(JSObject _) implements JSObject {
  external InputFrame poll();
  external void lock();
  external void unlock();
  external bool locked();
}

extension type InputFrame._(JSObject _) implements JSObject {
  external double get dx;
  external double get dy;
  external double get wheel;
  external int get buttons;

  /// Comma separated KeyboardEvent.code values currently held / newly pressed.
  external String get keys;
  external String get pressed;
  external bool get locked;
}

/// Access point for the JS engine.
class Engine {
  Engine._(this.js);
  final RpsEngine js;

  static Engine? _instance;
  static Engine get I => _instance!;

  /// Waits for the engine module to finish loading.
  static Future<Engine> ready() async {
    if (_instance != null) return _instance!;
    var e = _engine;
    if (e == null) {
      final c = Completer<void>();
      void onReady(web.Event _) {
        if (!c.isCompleted) c.complete();
      }

      web.window.addEventListener('rps-engine-ready', onReady.toJS);
      // The module may have finished between the check and the listener.
      while (_engine == null && !c.isCompleted) {
        await Future.any([c.future, Future<void>.delayed(const Duration(milliseconds: 50))]);
      }
      e = _engine!;
    }
    return _instance = Engine._(e);
  }

  RpsAudio get audio => js.audio;
  RpsInput get input => js.input;

  void sfx(String name, {double vol = 1, double rate = 1, List<double>? pos}) {
    audio.play(name, vol, rate, pos == null ? null : [for (final v in pos) v.toJS].toJS);
  }

  void setTick(void Function(double dt)? f) => js.tick = f?.toJS;

  /// Fetches a file served from web/game/ as bytes.
  static Future<Uint8List> fetchBytes(String path) async {
    final r = await web.window.fetch('game/$path'.toJS).toDart;
    if (!r.ok) throw StateError('fetch $path: ${r.status}');
    final buf = await r.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  }
}

JSArray<JSNumber> jsNums(List<double> v) => [for (final x in v) x.toJS].toJS;
JSArray<JSString> jsStrs(List<String> v) => [for (final x in v) x.toJS].toJS;
