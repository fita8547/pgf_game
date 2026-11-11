import 'package:web/web.dart' as web;

/// Player settings, kept in localStorage.
class Settings {
  Settings._();
  static final Settings I = Settings._()..load();

  /// Radians per mouse pixel.
  double sensitivity = 0.0022;
  double sfxVolume = 0.8;
  double musicVolume = 0.3;
  double fov = 70;
  String charId = 'pebble';
  String mapId = 'rps_arena';
  double botSkill = 0.5;
  String name = '플레이어';

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
      fov = d('fov', fov);
      botSkill = d('bot', botSkill);
      charId = s.getItem('rps.char') ?? charId;
      mapId = s.getItem('rps.map') ?? mapId;
      name = s.getItem('rps.name') ?? name;
      server = s.getItem('rps.server') ?? server;
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
      s.setItem('rps.fov', '$fov');
      s.setItem('rps.bot', '$botSkill');
      s.setItem('rps.char', charId);
      s.setItem('rps.map', mapId);
      s.setItem('rps.name', name);
      s.setItem('rps.server', server);
      s.setItem('rps.quality', '$quality');
    } catch (_) {}
  }
}
