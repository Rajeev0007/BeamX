import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'signaling.dart';

enum RelayState { off, connecting, online, error }

@immutable
class RelayStatus {
  const RelayStatus(this.state, {this.internetId, this.message});
  final RelayState state;

  /// This device's 9-digit Internet ID while online.
  final String? internetId;
  final String? message;
}

/// A way to reach devices over the internet: your own BeamX server
/// ([RelayClient]) or the free public server ([PeerJsRelay]).
abstract class InternetRelay {
  ValueNotifier<RelayStatus> get status;

  /// STUN/TURN servers to use for internet sessions.
  List<Map<String, dynamic>> get iceServers;

  void start();
  void stop();

  /// Rings the device with [internetId]. Throws if it's offline or busy.
  Future<SignalingTransport> dial(String internetId);
}

/// Keeps this device reachable through a BeamX internet relay server
/// (see server/README.md) and opens relayed signaling sessions.
///
/// The server only passes messages along. The pairing proof and the
/// authenticated offer/answer protect the session end to end, exactly as on
/// the local network.
class RelayClient implements InternetRelay {
  RelayClient({
    required this.url,
    required this.deviceId,
    required this.key,
    required this.onIncoming,
  });

  static const protocolVersion = 1;

  final String url;
  final String deviceId;

  /// Proves to the server that this device owns [deviceId].
  final String key;

  /// Called when another device rings us.
  final void Function(SignalingTransport transport, String fromInternetId) onIncoming;

  @override
  final ValueNotifier<RelayStatus> status =
      ValueNotifier(const RelayStatus(RelayState.off));

  /// STUN/TURN servers from the relay, used for internet sessions.
  @override
  List<Map<String, dynamic>> iceServers = const [];

  WebSocket? _ws;
  bool _stopped = false;
  int _attempt = 0;
  Timer? _retry;
  final Map<String, RelayTransport> _sessions = {};
  final Map<String, Completer<String?>> _dialing = {};

  /// The 9-digit ID for a device ID. Must match the server's formula.
  static String internetIdFor(String id) {
    final bytes = sha256.convert(utf8.encode(id)).bytes;
    var v = BigInt.zero;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | BigInt.from(bytes[i]);
    }
    return (v % BigInt.from(1000000000)).toString().padLeft(9, '0');
  }

  static String format(String internetId) => internetId.length == 9
      ? '${internetId.substring(0, 3)} ${internetId.substring(3, 6)} ${internetId.substring(6)}'
      : internetId;

  @override
  void start() {
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    status.value = const RelayStatus(RelayState.connecting);
    try {
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
      ws.pingInterval = const Duration(seconds: 20);
      _ws = ws;
      ws.add(jsonEncode({'t': 'hello', 'v': protocolVersion, 'id': deviceId, 'key': key}));
      ws.listen(
        (d) {
          if (d is String && d.length <= SignalingChannel.maxMessageBytes + 1024) {
            _onMessage(d);
          }
        },
        onDone: () => _lost(ws.closeReason),
        onError: (Object _) => _lost(null),
        cancelOnError: true,
      );
    } catch (e) {
      _lost(e is TimeoutException ? 'Server did not respond' : 'Can\'t reach the server');
    }
  }

  void _lost(String? reason) {
    _ws = null;
    for (final t in _sessions.values.toList()) {
      t._remoteClosed('Internet server connection lost');
    }
    _sessions.clear();
    for (final c in _dialing.values) {
      if (!c.isCompleted) c.complete('Internet server connection lost');
    }
    _dialing.clear();
    if (_stopped) {
      status.value = const RelayStatus(RelayState.off);
      return;
    }
    status.value = RelayStatus(RelayState.error,
        message: reason == null || reason.isEmpty ? 'Disconnected, retrying…' : reason);
    // Retry with backoff: 2, 4, 8 … 60 seconds.
    final delay = min(60, 2 << min(_attempt++, 5));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: delay), _connect);
  }

  void _send(Map<String, Object?> m) => _ws?.add(jsonEncode(m));

  void _onMessage(String raw) {
    Object? m;
    try {
      m = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    final sid = m['sid'];
    switch (m['t']) {
      case 'welcome':
        _attempt = 0;
        final ice = m['ice'];
        iceServers = ice is List
            ? [for (final s in ice) if (s is Map) Map<String, dynamic>.from(s)]
            : const [];
        final id = m['shortId'];
        status.value = RelayStatus(RelayState.online,
            internetId: id is String ? id : internetIdFor(deviceId));
      case 'ring' when sid is String:
        final from = m['from'];
        final t = RelayTransport._(this, sid);
        _sessions[sid] = t;
        onIncoming(t, from is String ? from : 'unknown');
      case 'ringing' when sid is String:
        _dialing.remove(sid)?.complete(null);
      case 'relay' when sid is String:
        final d = m['d'];
        if (d is String) _sessions[sid]?._incoming.add(d);
      case 'hangup' when sid is String:
        final reason = m['reason'];
        final text = switch (reason) {
          'offline' => 'That device is not online. Check that BeamX is open on it '
              'and uses the same internet server.',
          'busy' => 'That device is busy',
          _ => 'The other device disconnected',
        };
        _dialing.remove(sid)?.complete(text);
        _sessions.remove(sid)?._remoteClosed(text);
    }
  }

  @override
  Future<RelayTransport> dial(String internetId) async {
    if (status.value.state != RelayState.online) {
      throw SignalingException('Not connected to the internet server');
    }
    final r = Random.secure();
    final sid = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    final t = RelayTransport._(this, sid);
    _sessions[sid] = t;
    final answer = Completer<String?>();
    _dialing[sid] = answer;
    _send({'t': 'dial', 'sid': sid, 'to': internetId});
    final error = await answer.future.timeout(const Duration(seconds: 10),
        onTimeout: () => 'The internet server did not respond');
    _dialing.remove(sid);
    if (error != null) {
      _sessions.remove(sid);
      throw SignalingException(error);
    }
    return t;
  }

  @override
  void stop() {
    _stopped = true;
    _retry?.cancel();
    _ws?.close(WebSocketStatus.normalClosure, 'stopped');
    _lost(null);
  }
}

/// One relayed signaling session with another device.
class RelayTransport implements SignalingTransport {
  RelayTransport._(this._client, this.sid);

  final RelayClient _client;
  final String sid;
  final _incoming = StreamController<String>();
  String? _closeReason;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String data) {
    if (_closeReason == null) _client._send({'t': 'relay', 'sid': sid, 'd': data});
  }

  @override
  void close(String reason) {
    if (_closeReason != null) return;
    _closeReason = reason;
    _client._send({'t': 'hangup', 'sid': sid});
    _client._sessions.remove(sid);
    _incoming.close();
  }

  void _remoteClosed(String reason) {
    if (_closeReason != null) return;
    _closeReason = reason;
    _incoming.close();
  }

  @override
  String? get closeReason => _closeReason;
}
