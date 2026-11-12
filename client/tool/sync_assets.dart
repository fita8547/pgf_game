// Copies game assets into the web client and builds icons/logos.
//   cd client && dart run tool/sync_assets.dart
//
// web/game/glb/...      <- ../rps_assets/glb   (three.js loads these)
// web/game/music/*.ogg  <- ../song/rps_music/ogg (+ mp3 fallback)
// web/game/sfx/*.mp3    <- ../song/rps_sfx/mp3
// web/game/music/bgm/   <- ../song/bgm/*.mp3 (BGM playlist, ascii names + list.json)
// web/game/voice/       <- ../song/voice (agent lines: voice_lines.json + <agent>/<id>.mp3)
// assets/logo/*.png     <- ../logo (resized for the UI)
// assets/icons/**       <- ../rps_assets/icons (character/skill/gun/role)
// web/favicon.png, web/icons/*  <- ../logo/앱아이콘_1024.png
import 'dart:convert';
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
      // Skip only if same size and not older than the source (same-size edits
      // still get copied).
      if (out.existsSync() &&
          out.lengthSync() == f.lengthSync() &&
          !f.lastModifiedSync().isAfter(out.lastModifiedSync())) {
        continue;
      }
      out.parent.createSync(recursive: true);
      f.copySync(out.path);
      files++;
    }
  }

  copyDir('rps_assets/glb', 'web/game/glb', where: (p) => p.endsWith('.glb'));
  copyDir('song/rps_music/ogg', 'web/game/music');
  copyDir('song/rps_music/mp3', 'web/game/music');
  copyDir('song/rps_sfx/mp3', 'web/game/sfx');
  copyDir('song/voice', 'web/game/voice', where: (p) => p.endsWith('.mp3') || p == 'voice_lines.json');
  syncPlaylist(root);
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

/// BGM playlist: every mp3 in song/bgm, copied under a URL-safe name, plus
/// list.json ([{file, title}]) that the audio engine shuffles through.
/// Drop an mp3 into song/bgm and re-run to add a song; delete it to remove.
void syncPlaylist(Directory root) {
  final src = Directory('${root.path}/song/bgm');
  final out = Directory('web/game/music/bgm');
  out.createSync(recursive: true);
  final tracks = <Map<String, String>>[];
  final keep = <String>{'list.json'};
  if (src.existsSync()) {
    final files = src.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.mp3')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final title = f.uri.pathSegments.last.replaceAll(RegExp(r'\.mp3$', caseSensitive: false), '');
      var slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
      if (slug.isEmpty || keep.contains('$slug.mp3')) slug = 'track${tracks.length + 1}';
      final dst = File('${out.path}/$slug.mp3');
      if (!dst.existsSync() || dst.lengthSync() != f.lengthSync()) f.copySync(dst.path);
      keep.add('$slug.mp3');
      tracks.add({'file': 'bgm/$slug.mp3', 'title': title});
    }
  }
  for (final f in out.listSync().whereType<File>()) {
    if (!keep.contains(f.uri.pathSegments.last)) f.deleteSync();
  }
  File('${out.path}/list.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(tracks));
  stdout.writeln('bgm playlist: ${tracks.length} tracks');
}
