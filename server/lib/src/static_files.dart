import 'dart:io';

/// Minimal static file handler for the built web client.
class StaticFiles {
  final String root;
  StaticFiles(this.root);

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
    'glb': 'model/gltf-binary',
    'mp3': 'audio/mpeg',
    'ogg': 'audio/ogg',
    'wav': 'audio/wav',
    'otf': 'font/otf',
    'ttf': 'font/ttf',
    'woff2': 'font/woff2',
    'css': 'text/css',
    'bin': 'application/octet-stream',
  };

  Future<void> serve(HttpRequest req) async {
    final res = req.response;
    try {
      var path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      if (path.endsWith('/')) path += 'index.html';
      final f = File('$root$path');
      if (!await f.exists()) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final ext = path.split('.').last.toLowerCase();
      res.headers.set(HttpHeaders.contentTypeHeader, _types[ext] ?? 'application/octet-stream');
      // Game assets are large and immutable per build; html/js must refresh.
      final cache = path.startsWith('/game/') || path.startsWith('/vendor/') || path.startsWith('/canvaskit/');
      res.headers.set(HttpHeaders.cacheControlHeader, cache ? 'public, max-age=86400' : 'no-cache');
      await res.addStream(f.openRead());
    } catch (_) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close();
    }
  }
}
