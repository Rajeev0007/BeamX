import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';

/// Carries signaling text messages: a direct WebSocket on the local network,
/// or a session through the internet relay server.
abstract class SignalingTransport {
  /// Incoming messages. Listened to once.
  Stream<String> get messages;
  void send(String data);
  void close(String reason);
  String? get closeReason;
}

/// A direct WebSocket between two devices on the same network.
class WebSocketTransport implements SignalingTransport {
  WebSocketTransport(this._ws);
  final WebSocket _ws;

  @override
  Stream<String> get messages =>
      _ws.map((d) => d is String ? d : ''); // binary → invalid → closed

  @override
  void send(String data) => _ws.add(data);

  @override
  void close(String reason) => _ws.close(WebSocketStatus.normalClosure,
      reason.length > 100 ? reason.substring(0, 100) : reason);

  @override
  String? get closeReason => _ws.closeReason;
}

/// A JSON message channel used to set up WebRTC.
///
/// Messages are buffered in order, so none are lost between the pairing
/// handshake and the WebRTC session taking over the channel.
///
/// Incoming messages are untrusted: anything that is not a small JSON
/// object with a string `t` (type) field closes the connection.
class SignalingChannel {
  SignalingChannel(this._ws) {
    _sub = _ws.messages.listen(
      (data) {
        if (data.length > maxMessageBytes) {
          close('message too large');
          return;
        }
        Object? m;
        try {
          m = jsonDecode(data);
        } catch (_) {}
        if (m is Map<String, dynamic> && m['t'] is String) {
          _incoming.add(m);
        } else {
          close('invalid message');
        }
      },
      onDone: () => _finish(_ws.closeReason ?? 'connection closed'),
      onError: (Object e) => _finish('connection error'),
      cancelOnError: true,
    );
    _queue = StreamQueue(_incoming.stream);
  }

  static const maxMessageBytes = 64 * 1024;
  static const protocolVersion = 1;

  final SignalingTransport _ws;
  late final StreamSubscription<String> _sub;
  final _incoming = StreamController<Map<String, dynamic>>();
  late final StreamQueue<Map<String, dynamic>> _queue;
  final _closed = Completer<String>();

  /// Completes with the reason when the channel closes.
  Future<String> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  void send(Map<String, Object?> message) {
    if (!isClosed) _ws.send(jsonEncode(message));
  }

  /// Reads the next message, which must be of [type]. A `reject` or `bye`
  /// message, a different type, a timeout or a closed connection all throw.
  Future<Map<String, dynamic>> next(String type,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final Map<String, dynamic> m;
    try {
      m = await _queue.next.timeout(timeout);
    } on TimeoutException {
      throw SignalingException('The other device did not respond');
    } on StateError {
      throw SignalingException('Connection closed');
    }
    if (m['t'] == type) return m;
    final reason = m['reason'];
    final code = m['code'];
    throw SignalingException(
        reason is String && reason.length <= 200 ? reason : 'Connection refused',
        code: code is String && code.length <= 32 ? code : null);
  }

  /// All remaining messages, for the WebRTC session after the handshake.
  Stream<Map<String, dynamic>> rest() => _queue.rest;

  static Future<SignalingChannel> connect(String host, int port) async {
    final uri = Uri(scheme: 'ws', host: host, port: port, path: '/beamx');
    final ws = await WebSocket.connect(uri.toString())
        .timeout(const Duration(seconds: 8));
    ws.pingInterval = const Duration(seconds: 5);
    return SignalingChannel(WebSocketTransport(ws));
  }

  void close([String reason = 'closed']) {
    if (isClosed) return;
    _ws.close(reason);
    _finish(reason);
  }

  void _finish(String reason) {
    if (_closed.isCompleted) return;
    _closed.complete(reason);
    _sub.cancel();
    _incoming.close();
  }
}

class SignalingException implements Exception {
  SignalingException(this.message, {this.code});
  final String message;

  /// Machine-readable reason, e.g. `untrusted` or `need-code`.
  final String? code;
  @override
  String toString() => message;
}
