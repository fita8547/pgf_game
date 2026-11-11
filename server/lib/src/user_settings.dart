import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Per-player UI settings kept on the server (requirement: dark mode and
/// font size are stored on the back end and survive restarts).
///
/// Players are anonymous: the browser makes a random client id once and
/// sends it with every request. Data lives in one JSON file:
///   { "<clientId>": { "dark": true, "fontScale": 1.0, "updated": "..." } }
///
/// HTTP API (JSON, CORS open so a dev client on another port works):
///   GET  /api/health                 -> {"ok": true}
///   GET  /api/settings?cid=<id>      -> {"dark": bool, "fontScale": num}  (defaults if unknown)
///   PUT  /api/settings?cid=<id>      body {"dark"?: bool, "fontScale"?: num} -> saved values
class UserSettingsStore {
  final File file;
  final int maxClients;
  final Map<String, Map<String, Object?>> _data = {};
  Timer? _flush;

  static const double minFont = 0.85, maxFont = 1.3;
  static const Map<String, Object?> defaults = {'dark': true, 'fontScale': 1.0};
  static final _cid = RegExp(r'^[A-Za-z0-9-]{8,64}$');

  UserSettingsStore(String path, {this.maxClients = 20000}) : file = File(path) {
    try {
      if (file.existsSync()) {
        final m = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final e in m.entries) {
          if (e.value is Map) _data[e.key] = Map<String, Object?>.from(e.value as Map);
        }
      }
    } catch (_) {
      // Corrupt file: start empty, keep the bad copy for inspection.
      try {
        file.renameSync('${file.path}.bad');
      } catch (_) {}
    }
  }

  int get length => _data.length;

  Map<String, Object?> get(String cid) {
    final d = _data[cid];
    return {
      'dark': d?['dark'] ?? defaults['dark'],
      'fontScale': d?['fontScale'] ?? defaults['fontScale'],
    };
  }

  /// Validates and stores; returns the saved values or null if [cid] is bad.
  Map<String, Object?>? put(String cid, Map<String, dynamic> body) {
    if (!_cid.hasMatch(cid)) return null;
    if (!_data.containsKey(cid) && _data.length >= maxClients) return null;
    final cur = {...get(cid)};
    final dark = body['dark'];
    if (dark is bool) cur['dark'] = dark;
    final fs = body['fontScale'];
    if (fs is num && fs.isFinite) cur['fontScale'] = (fs.toDouble().clamp(minFont, maxFont) * 100).round() / 100;
    cur['updated'] = DateTime.now().toUtc().toIso8601String();
    _data[cid] = cur;
    _scheduleSave();
    return get(cid);
  }

  void _scheduleSave() {
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 300), saveNow);
  }

  /// Writes atomically (temp file + rename) so a crash never leaves half a file.
  void saveNow() {
    _flush?.cancel();
    _flush = null;
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_data));
    if (file.existsSync()) file.deleteSync();
    tmp.renameSync(file.path);
  }

  /// Handles /api/* requests. Returns false if the path is not an API route.
  Future<bool> handle(HttpRequest req) async {
    final path = req.uri.path;
    if (!path.startsWith('/api/')) return false;
    final res = req.response;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, PUT, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
    void send(int code, Object body) {
      res.statusCode = code;
      res.write(jsonEncode(body));
    }

    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
      } else if (path == '/api/health') {
        send(200, {'ok': true});
      } else if (path == '/api/settings') {
        final cid = req.uri.queryParameters['cid'] ?? '';
        if (!_cid.hasMatch(cid)) {
          send(400, {'error': 'bad cid'});
        } else if (req.method == 'GET') {
          send(200, get(cid));
        } else if (req.method == 'PUT' || req.method == 'POST') {
          final text = await utf8.decoder.bind(req).take(64).join();
          if (text.length > 2000) {
            send(413, {'error': 'too large'});
          } else {
            final body = jsonDecode(text);
            final saved = body is Map<String, dynamic> ? put(cid, body) : null;
            saved == null ? send(400, {'error': 'bad request'}) : send(200, saved);
          }
        } else {
          send(405, {'error': 'method'});
        }
      } else {
        send(404, {'error': 'not found'});
      }
    } catch (_) {
      send(400, {'error': 'bad request'});
    } finally {
      await res.close();
    }
    return true;
  }
}
