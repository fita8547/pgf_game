import 'dart:async';
import 'dart:js_interop';

import 'package:rps_shared/rps_shared.dart';
import 'package:web/web.dart' as web;

/// WebSocket connection to rps_server.
class NetClient {
  NetClient(this.url);
  final String url;
  web.WebSocket? _ws;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  bool open = false;
  String? closedReason;

  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Default server: the host that served this page (rps_server serves both).
  static String defaultUrl() {
    final loc = web.window.location;
    final scheme = loc.protocol == 'https:' ? 'wss' : 'ws';
    return '$scheme://${loc.host}${Net.path}';
  }

  Future<void> connect() {
    final c = Completer<void>();
    final ws = web.WebSocket(url);
    _ws = ws;
    ws.addEventListener('open', ((web.Event _) {
      open = true;
      if (!c.isCompleted) c.complete();
    }).toJS);
    ws.addEventListener('message', ((web.MessageEvent e) {
      final d = e.data;
      if (d.isA<JSString>()) {
        try {
          _messages.add(Net.decode((d as JSString).toDart));
        } catch (_) {}
      }
    }).toJS);
    ws.addEventListener('close', ((web.CloseEvent e) {
      open = false;
      closedReason = e.reason.isEmpty ? '연결 종료 (${e.code})' : e.reason;
      if (!c.isCompleted) c.completeError(StateError('서버에 연결할 수 없습니다: $url'));
      _messages.add({'t': 'closed', 'm': closedReason});
    }).toJS);
    return c.future.timeout(const Duration(seconds: 6), onTimeout: () {
      ws.close();
      throw StateError('서버 응답 없음: $url');
    });
  }

  void send(Map<String, Object?> m) {
    if (open) _ws?.send(Net.encode(m).toJS);
  }

  void close() {
    _ws?.close();
    _messages.close();
  }
}
