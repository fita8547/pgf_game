// Copies game assets into the web client and builds icons/logos.
//   cd client && dart run tool/sync_assets.dart
//
// web/game/glb/...      <- ../rps_assets/glb   (three.js loads these)
// web/game/music/*.ogg  <- ../song/rps_music/ogg (+ mp3 fallback)
// web/game/sfx/*.mp3    <- ../song/rps_sfx/mp3
// assets/logo/*.png     <- ../logo (resized for the UI)
// assets/icons/**       <- ../rps_assets/icons (character/skill/gun/role)
// web/favicon.png, web/icons/*  <- ../logo/앱아이콘_1024.png
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final root = Directory('..');
  var files = 0;
  void copyDir(String from, String to, {bool Function(String)? where}) {
    final src = Directory('${root.path}/$from');
    if (!src.existsSync()) {
      stderr.writeln('missing $from');
      return;
    }
    for (final f in src.listSync(recursive: true).whereType<File>()) {
      final rel = f.path.substring(src.path.length + 1).replaceAll('\\', '/');
      if (where != null && !where(rel)) continue;
      final out = File('$to/$rel');
      if (out.existsSync() && out.lengthSync() == f.lengthSync()) continue;
      out.parent.createSync(recursive: true);
      f.copySync(out.path);
      files++;
    }
  }

  copyDir('rps_assets/glb', 'web/game/glb', where: (p) => p.endsWith('.glb'));
  copyDir('song/rps_music/ogg', 'web/game/music');
  copyDir('song/rps_music/mp3', 'web/game/music');
  copyDir('song/rps_sfx/mp3', 'web/game/sfx');
  copyDir('rps_assets/icons', 'assets/icons', where: (p) => p.endsWith('.png'));
  stdout.writeln('copied $files files');

  void resize(String from, String to, int width) {
    final out = File(to);
    if (out.existsSync()) return;
    final src = img.decodePng(File('${root.path}/$from').readAsBytesSync())!;
    final r = img.copyResize(src, width: width, interpolation: img.Interpolation.average);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(img.encodePng(r, level: 9));
    stdout.writeln('wrote $to (${r.width}x${r.height})');
  }

  resize('logo/메인로고.png', 'assets/logo/main.png', 720);
  resize('logo/가로형로고.png', 'assets/logo/wide.png', 1080);
  resize('logo/오리가미_일러스트_투명배경.png', 'assets/logo/origami.png', 640);
  resize('logo/앱아이콘_1024.png', 'assets/logo/icon.png', 256);

  const icon = 'logo/앱아이콘_1024.png';
  final done = File('tool/.icons_generated');
  if (!done.existsSync()) {
    for (final f in ['web/favicon.png', 'web/icons/Icon-192.png', 'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png', 'web/icons/Icon-maskable-512.png']) {
      final size = f.contains('512') ? 512 : (f.contains('192') ? 192 : 48);
      if (File(f).existsSync()) File(f).deleteSync();
      resize(icon, f, size);
    }
    done.writeAsStringSync('icons generated from $icon; delete this file to regenerate');
  }
}
