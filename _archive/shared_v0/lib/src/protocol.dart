import 'dart:convert';

import 'agents.dart';
import 'input.dart';

/// Wire protocol shared by client and server. Every message is a JSON object
/// with a `t` (type) field. Snapshots use [GameSim.snapshot] (`t: 'snap'`).
const int protocolVersion = 1;

/// Server tick rate and snapshot rate (Hz).
const int serverTickRate = 60;
const int snapshotRate = 20;

abstract final class MsgType {
  // client -> server
  static const hello = 'hello';
  static const input = 'in';
  static const buy = 'buy';
  static const chat = 'chat';
  static const ping = 'ping';

  // server -> client
  static const welcome = 'welcome';
  static const snapshot = 'snap';
  static const events = 'ev';
  static const buyResult = 'buyRes';
  static const chatMsg = 'chatMsg';
  static const pong = 'pong';
  static const error = 'err';
}

String encodeMsg(Map<String, Object?> msg) => jsonEncode(msg);

Map<String, dynamic>? decodeMsg(String raw) {
  try {
    final v = jsonDecode(raw);
    return v is Map<String, dynamic> && v['t'] is String ? v : null;
  } catch (_) {
    return null;
  }
}

// ------------------------------------------------------- client -> server --
Map<String, Object?> helloMsg(String name, AgentId agent, {String? token}) => {
      't': MsgType.hello,
      'v': protocolVersion,
      'name': name,
      'agent': agent.name,
      if (token != null) 'token': token,
    };

/// Inputs are batched: the client sends every unacknowledged frame.
Map<String, Object?> inputMsg(List<PlayerInput> inputs) => {
      't': MsgType.input,
      'i': [for (final i in inputs) i.toNet()],
    };

List<PlayerInput> parseInputs(Map<String, dynamic> m) => [
      for (final raw in (m['i'] as List? ?? const [])) PlayerInput.fromNet(raw as List),
    ];

Map<String, Object?> buyMsg(String item) => {'t': MsgType.buy, 'item': item};
Map<String, Object?> chatMsg(String text) => {'t': MsgType.chat, 'text': text};
Map<String, Object?> pingMsg(double clientTime) => {'t': MsgType.ping, 'ct': clientTime};

// ------------------------------------------------------- server -> client --
Map<String, Object?> welcomeMsg(int playerId, String mapId, {int tickRate = serverTickRate}) => {
      't': MsgType.welcome,
      'v': protocolVersion,
      'id': playerId,
      'map': mapId,
      'rate': tickRate,
    };

Map<String, Object?> eventsMsg(List<Map<String, Object?>> events) => {'t': MsgType.events, 'e': events};
Map<String, Object?> buyResultMsg(String item, String? error) =>
    {'t': MsgType.buyResult, 'item': item, 'ok': error == null, if (error != null) 'msg': error};
Map<String, Object?> chatBroadcast(int from, String name, String text) =>
    {'t': MsgType.chatMsg, 'from': from, 'name': name, 'text': text};
Map<String, Object?> pongMsg(double clientTime, double serverTime) =>
    {'t': MsgType.pong, 'ct': clientTime, 'st': serverTime};
Map<String, Object?> errorMsg(String message) => {'t': MsgType.error, 'msg': message};

AgentId? agentByName(String? name) => AgentId.values.where((a) => a.name == name).firstOrNull;
