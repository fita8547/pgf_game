import 'dart:convert';
import 'dart:io';

import 'package:rps_server/rps_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('rps-us-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('settings persist across a restart (new store on the same file)', () {
    final path = '${dir.path}/s.json';
    final a = UserSettingsStore(path);
    expect(a.get('client-0001'), {'dark': true, 'fontScale': 1.0});
    expect(a.put('client-0001', {'dark': false, 'fontScale': 1.2}), {'dark': false, 'fontScale': 1.2});
    a.saveNow();
    final b = UserSettingsStore(path);
    expect(b.get('client-0001'), {'dark': false, 'fontScale': 1.2});
  });

  test('validation: bad ids rejected, font scale clamped, wrong types ignored', () {
    final s = UserSettingsStore('${dir.path}/s.json');
    expect(s.put('x', {'dark': false}), isNull);
    expect(s.put('../../etc', {'dark': false}), isNull);
    expect(s.put('client-0002', {'fontScale': 9})!['fontScale'], UserSettingsStore.maxFont);
    expect(s.put('client-0002', {'dark': 'yes', 'fontScale': 'big'}), {'dark': true, 'fontScale': UserSettingsStore.maxFont});
  });

  test('HTTP API', () async {
    final store = UserSettingsStore('${dir.path}/s.json');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      if (!await store.handle(r)) {
        r.response.statusCode = 404;
        await r.response.close();
      }
    });
    final c = HttpClient();
    Future<(int, Object?)> call(String method, String path, [Object? body]) async {
      final rq = await c.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
      if (body != null) rq.write(jsonEncode(body));
      final rs = await rq.close();
      final t = await utf8.decoder.bind(rs).join();
      return (rs.statusCode, t.isEmpty ? null : jsonDecode(t));
    }

    Future<void> check(String method, String path, Object? body, int code, Object json) async {
      final (c0, j) = await call(method, path, body);
      expect(c0, code);
      expect(j, json);
    }

    await check('GET', '/api/health', null, 200, {'ok': true});
    await check('GET', '/api/settings?cid=abc', null, 400, {'error': 'bad cid'});
    await check('PUT', '/api/settings?cid=client-0003', {'dark': false, 'fontScale': 1.15}, 200,
        {'dark': false, 'fontScale': 1.15});
    await check('GET', '/api/settings?cid=client-0003', null, 200, {'dark': false, 'fontScale': 1.15});
    c.close();
    await server.close(force: true);
  });
}
