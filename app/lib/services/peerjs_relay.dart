import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'relay_client.dart';
import 'signaling.dart';

/// "Connect from anywhere" with no setup, through the free public PeerJS
/// server (0.peerjs.com), run by the PeerJS open-source project.
///
/// The server only routes small messages by ID; it sets the sender of every
/// message itself, so senders can't be faked. BeamX's own handshake
/// (password / code / trust proof, authenticated offer and answer) runs on
/// top, so the server can't read or alter sessions.
///
/// Limits: it's a free community service with no guarantee, and there is
/// no TURN relay, so some mobile networks can't connect. For those, run
/// your own server (server/README.md).
class PeerJsRelay implements InternetRelay {
  PeerJsRelay({
    required this.internetId,
    required this._token,
    required this.onIncoming,
  });

  static const host = '0.peerjs.com';
  static const _idPrefix = 'beamx1-';

  /// This device's 9-digit ID.
  final String internetId;

  /// Keeps our ID ours while we're connected (PeerJS ID token).
  final String _token;
  final void Function(SignalingTransport transport, String fromInternetId) onIncoming;

  @override
  final ValueNotifier<RelayStatus> status =
      ValueNotifier(const RelayStatus(RelayState.off));

  @override
  List<Map<String, dynamic>> get iceServers => const [
        {
          'urls': ['stun:stun.l.google.com:19302', 'stun:stun.cloudflare.com:3478'],
        },
      ];

  WebSocket? _ws;
  Timer? _heartbeat;
  Timer? _retry;
  bool _stopped = false;
  int _attempt = 0;
  final Map<String, _PeerJsTransport> _sessions = {};
  final Map<String, Completer<String?>> _dialing = {};

  static String peerIdFor(String internetId) => '$_idPrefix$internetId';

  @override
  void start() {
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    status.value = const RelayStatus(RelayState.connecting);
    final url = Uri(
      scheme: 'wss',
      host: host,
      port: 443,
      path: '/peerjs',
      queryParameters: {
        'key': 'peerjs',
        'id': peerIdFor(internetId),
        'token': _token,
        'version': '1.5.4',
      },
    );
    try {
      final ws = await WebSocket.connect(url.toString())
          .timeout(const Duration(seconds: 10));
      _ws = ws;
      ws.listen(
        (d) {
          if (d is String && d.length <= SignalingChannel.maxMessageBytes * 2) {
            _onMessage(d);
          }
        },
        onDone: () => _lost(null),
        onError: (Object _) => _lost(null),
        cancelOnError: true,
      );
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 5),
          (_) => _ws?.add(jsonEncode({'type': 'HEARTBEAT'})));
    } catch (_) {
      _lost('Can\'t reach the public server');
    }
  }

  void _lost(String? reason) {
    _heartbeat?.cancel();
    _ws = null;
    for (final t in _sessions.values.toList()) {
      t._remoteClosed('Internet connection lost');
    }
    _sessions.clear();
    for (final c in _dialing.values) {
      if (!c.isCompleted) c.complete('Internet connection lost');
    }
    _dialing.clear();
    if (_stopped) {
      status.value = const RelayStatus(RelayState.off);
      return;
    }
    if (status.value.state != RelayState.error || reason != null) {
      status.value = RelayStatus(RelayState.error,
          message: reason ?? 'Disconnected, retrying…');
    }
    final delay = min(60, 2 << min(_attempt++, 5));
    _retry?.cancel();
    _retry = Timer(Duration(seconds: delay), _connect);
  }

  /// The public server only forwards messages shaped like PeerJS ICE
  /// candidates, and closes connections for messages over ~16 KB. So BeamX
  /// messages travel as JSON text inside a candidate, in parts if needed.
  static const _maxPart = 12000;

  void _send(String toInternetId, Map<String, Object?> payload) {
    _ws?.add(jsonEncode({
      'type': 'CANDIDATE',
      'dst': peerIdFor(toInternetId),
      'payload': {
        'candidate': {
          'candidate': jsonEncode({'beamx': 1, ...payload}),
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
        'type': 'data',
        'connectionId': 'dc_beamx',
      },
    }));
  }

  void _sendData(String to, String sid, String data) {
    if (data.length <= _maxPart) {
      _send(to, {'k': 'relay', 'sid': sid, 'd': data});
      return;
    }
    final n = (data.length / _maxPart).ceil();
    for (var i = 0; i < n; i++) {
      final end = min(data.length, (i + 1) * _maxPart);
      _send(to, {'k': 'part', 'sid': sid, 'i': i, 'n': n, 'd': data.substring(i * _maxPart, end)});
    }
  }

  /// Unwraps a BeamX message from a PeerJS candidate payload.
  static Map<dynamic, dynamic>? _unwrap(Object? payload) {
    if (payload is! Map) return null;
    final c = payload['candidate'];
    final text = c is Map ? c['candidate'] : null;
    if (text is! String || text.length > SignalingChannel.maxMessageBytes) return null;
    try {
      final m = jsonDecode(text);
      return m is Map && m['beamx'] == 1 ? m : null;
    } catch (_) {
      return null;
    }
  }

  /// The 9-digit ID of a PeerJS sender, or null if it isn't BeamX.
  static String? _senderId(Object? src) {
    if (src is! String || !src.startsWith(_idPrefix)) return null;
    final id = src.substring(_idPrefix.length);
    return RegExp(r'^\d{9}$').hasMatch(id) ? id : null;
  }

  void _onMessage(String raw) {
    Object? m;
    try {
      m = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    switch (m['type']) {
      case 'OPEN':
        _attempt = 0;
        status.value = RelayStatus(RelayState.online, internetId: internetId);
        return;
      case 'ID-TAKEN':
        _stopped = true;
        _ws?.close();
        status.value = const RelayStatus(RelayState.error,
            message: 'This ID is in use on another connection. Restart BeamX.');
        return;
      case 'ERROR':
        final p = m['payload'];
        final msg = p is Map && p['msg'] is String ? p['msg'] as String : 'Server error';
        _lost(msg.length > 120 ? msg.substring(0, 120) : msg);
        return;
      case 'EXPIRE':
        // A message to a device that isn't online expired.
        final from = _senderId(m['src']);
        if (from == null) return;
        for (final e in _dialing.entries.toList()) {
          if (_sessions[e.key]?.peer == from && !e.value.isCompleted) {
            e.value.complete(_offline);
          }
        }
        return;
      case 'CANDIDATE':
        break;
      default:
        return;
    }

    final from = _senderId(m['src']);
    final p = _unwrap(m['payload']);
    if (from == null || p == null) return;
    final sid = p['sid'];
    if (sid is! String || !RegExp(r'^[0-9a-f]{16}$').hasMatch(sid)) return;
    switch (p['k']) {
      case 'dial':
        if (_sessions.length >= 4) {
          _send(from, {'k': 'hangup', 'sid': sid, 'reason': 'busy'});
          return;
        }
        final t = _PeerJsTransport._(this, sid, from);
        _sessions[sid] = t;
        _send(from, {'k': 'ringing', 'sid': sid});
        onIncoming(t, from);
      case 'ringing':
        if (_sessions[sid]?.peer == from) _dialing.remove(sid)?.complete(null);
      case 'relay':
        final d = p['d'];
        final t = _sessions[sid];
        if (t != null && t.peer == from && d is String &&
            d.length <= SignalingChannel.maxMessageBytes) {
          t._incoming.add(d);
        }
      case 'part':
        final t = _sessions[sid];
        final i = p['i'], n = p['n'], d = p['d'];
        if (t == null || t.peer != from || i is! int || n is! int || d is! String) return;
        if (n < 2 || n > 8 || i < 0 || i >= n) return;
        if (i == 0) t._parts.clear();
        if (t._parts.length != i) return; // out of order: drop
        t._parts.add(d);
        if (t._parts.length == n) {
          final whole = t._parts.join();
          t._parts.clear();
          if (whole.length <= SignalingChannel.maxMessageBytes) t._incoming.add(whole);
        }
      case 'hangup':
        final t = _sessions[sid];
        if (t == null || t.peer != from) return;
        final reason = p['reason'] == 'busy'
            ? 'That device is busy'
            : 'The other device disconnected';
        _dialing.remove(sid)?.complete(reason);
        _sessions.remove(sid)?._remoteClosed(reason);
    }
  }

  static const _offline =
      'That device is not online. Check that BeamX is open on it and '
      '"Connect from anywhere" is on.';

  @override
  Future<SignalingTransport> dial(String targetId) async {
    if (status.value.state != RelayState.online) {
      throw SignalingException('Not connected to the internet yet');
    }
    final r = Random.secure();
    final sid = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
    final t = _PeerJsTransport._(this, sid, targetId);
    _sessions[sid] = t;
    final answer = Completer<String?>();
    _dialing[sid] = answer;
    _send(targetId, {'k': 'dial', 'sid': sid});
    final error = await answer.future
        .timeout(const Duration(seconds: 10), onTimeout: () => _offline);
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
    _ws?.close();
    _lost(null);
  }
}

class _PeerJsTransport implements SignalingTransport {
  _PeerJsTransport._(this._relay, this.sid, this.peer);

  final PeerJsRelay _relay;
  final String sid;

  /// The other device's 9-digit ID.
  final String peer;
  final _incoming = StreamController<String>();
  final List<String> _parts = [];
  String? _closeReason;

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String data) {
    if (_closeReason == null) _relay._sendData(peer, sid, data);
  }

  @override
  void close(String reason) {
    if (_closeReason != null) return;
    _closeReason = reason;
    _relay._send(peer, {'k': 'hangup', 'sid': sid});
    _relay._sessions.remove(sid);
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
