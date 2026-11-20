import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer_device.dart';
import 'beam_session.dart';
import 'discovery_service.dart';
import 'pairing_service.dart';
import 'screen_capture.dart';
import 'settings_store.dart';
import 'signaling.dart';

enum StreamMode {
  /// The connecting device wants to see this device's screen.
  view,

  /// The connecting device wants to show its screen on this device.
  share,
}

/// A device asking to connect, waiting for the user to accept or decline.
class IncomingRequest {
  IncomingRequest({
    required this.name,
    required this.platform,
    required this.address,
    required this.mode,
  });

  final String name;
  final String platform;
  final String address;
  final StreamMode mode;
  final _decision = Completer<bool>();

  /// Completes when the request is accepted, declined or expires.
  Future<bool> get decided => _decision.future;

  void accept() {
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void decline() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

/// Accepts incoming connections and makes outgoing ones.
///
/// Every BeamX device runs a small WebSocket server on the configured port.
/// The handshake is: challenge (nonce) → hello (pairing proof) → user
/// approval → accept. After that the [BeamSession] takes over the channel.
class ConnectionService {
  ConnectionService(this._settings, this._pairing, this._discovery) {
    _port = _settings.value.port;
    _settings.addListener(_onSettings);
  }

  final SettingsStore _settings;
  final PairingService _pairing;
  final DiscoveryService _discovery;

  final ValueNotifier<IncomingRequest?> pending = ValueNotifier(null);
  final ValueNotifier<BeamSession?> session = ValueNotifier(null);
  final ValueNotifier<String?> serverError = ValueNotifier(null);

  HttpServer? _server;
  late int _port;
  bool _handshaking = false;

  bool get busy => session.value != null || _handshaking;

  Future<void> start() async {
    if (kIsWeb) return;
    await _server?.close(force: true);
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server = server;
      serverError.value = null;
      server.listen(_onRequest, onError: (Object e) {});
    } on SocketException catch (e) {
      serverError.value =
          'Can\'t receive connections on port $_port (${e.message}). '
          'Change the port in Settings.';
    }
  }

  void _onSettings() {
    final port = _settings.value.port;
    if (port != _port) {
      _port = port;
      start();
    }
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (req.uri.path != '/beamx' || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 5);
    final ch = SignalingChannel(ws);
    final address = req.connectionInfo?.remoteAddress.address ?? 'unknown';

    if (busy) {
      ch.send({'t': 'reject', 'reason': 'The device is busy with another session'});
      ch.close('busy');
      return;
    }
    _handshaking = true;
    try {
      await _handshakeAsHost(ch, address);
    } on SignalingException catch (e) {
      ch.close(e.message);
    } catch (e) {
      ch.close('handshake failed');
    } finally {
      _handshaking = false;
      pending.value = null;
    }
  }

  Future<void> _handshakeAsHost(SignalingChannel ch, String address) async {
    final s = _settings.value;
    final nonce = PairingService.newNonce();
    ch.send({
      't': 'challenge',
      'v': SignalingChannel.protocolVersion,
      'nonce': nonce,
      'name': s.deviceName,
      'platform': DiscoveryService.platform,
    });

    final hello = await ch.next('hello', timeout: const Duration(seconds: 20));
    final id = hello['id'];
    final name = hello['name'];
    final platform = hello['platform'];
    final proof = hello['proof'];
    final mode = switch (hello['mode']) {
      'view' => StreamMode.view,
      'share' => StreamMode.share,
      _ => null,
    };
    if (hello['v'] != SignalingChannel.protocolVersion) {
      _reject(ch, 'Update BeamX on both devices to the same version');
    }
    if (id is! String || id.length > 64 || name is! String ||
        platform is! String || proof is! String || mode == null) {
      _reject(ch, 'Invalid request');
    }
    final safeName = _clean(name, 40);
    final code = _pairing.code.value;
    if (!_pairing.verify(nonce, id, proof)) {
      _reject(ch, 'Wrong pairing code');
    }
    if (mode == StreamMode.view && !ScreenCapture.supported) {
      _reject(ch, ScreenCapture.unsupportedReason);
    }

    if (s.requireApproval) {
      final req = IncomingRequest(
        name: safeName,
        platform: _clean(platform, 16),
        address: address,
        mode: mode,
      );
      pending.value = req;
      // If the other device gives up while waiting, close the prompt.
      unawaited(ch.closed.then((_) => req.decline()));
      final ok = await req._decision.future
          .timeout(const Duration(seconds: 60), onTimeout: () {
        req.decline();
        return false;
      });
      pending.value = null;
      if (!ok) _reject(ch, '${s.deviceName} declined the request');
    }

    // One-time code: the next pairing needs a new one.
    _pairing.regenerate();

    final own = StreamQuality.fromSettings(_settings.value);
    ch.send({
      't': 'accept',
      'name': s.deviceName,
      if (mode == StreamMode.share) 'quality': own.toJson(),
    });

    final role = mode == StreamMode.view ? SessionRole.sharer : SessionRole.viewer;
    final quality = role == SessionRole.sharer
        ? StreamQuality.fromJson(hello['quality'], own)
        : own;
    _begin(BeamSession(
      role: role,
      peerName: safeName,
      channel: ch,
      code: code,
      quality: quality,
    ));
  }

  /// Connects to [peer] using the pairing [code] shown on it.
  /// Completes when the other device accepts; throws with a readable
  /// message otherwise.
  Future<BeamSession> connect({
    required PeerDevice peer,
    required String code,
    required StreamMode mode,
  }) async {
    if (busy) throw SignalingException('Finish the current session first');
    if (mode == StreamMode.share && !ScreenCapture.supported) {
      throw SignalingException(ScreenCapture.unsupportedReason);
    }
    _handshaking = true;
    try {
      final SignalingChannel ch;
      try {
        ch = await SignalingChannel.connect(peer.address, peer.port);
      } catch (_) {
        throw SignalingException(
            'Can\'t reach ${peer.name}. Check that both devices are on the '
            'same Wi-Fi and BeamX is open on it.');
      }
      try {
        return await _handshakeAsClient(ch, peer, code, mode);
      } catch (_) {
        ch.close('failed');
        rethrow;
      }
    } finally {
      _handshaking = false;
    }
  }

  Future<BeamSession> _handshakeAsClient(SignalingChannel ch, PeerDevice peer,
      String code, StreamMode mode) async {
    final challenge =
        await ch.next('challenge', timeout: const Duration(seconds: 10));
    final nonce = challenge['nonce'];
    if (nonce is! String || nonce.length > 100) {
      throw SignalingException('Not a BeamX device');
    }
    final s = _settings.value;
    final own = StreamQuality.fromSettings(s);
    ch.send({
      't': 'hello',
      'v': SignalingChannel.protocolVersion,
      'id': _discovery.selfId,
      'name': s.deviceName,
      'platform': DiscoveryService.platform,
      'mode': mode.name,
      'proof': PairingService.proof(code, nonce, _discovery.selfId),
      if (mode == StreamMode.view) 'quality': own.toJson(),
    });

    // Waits while the other person decides.
    final accept =
        await ch.next('accept', timeout: const Duration(seconds: 75));
    final role =
        mode == StreamMode.view ? SessionRole.viewer : SessionRole.sharer;
    final acceptName = accept['name'];
    final session = BeamSession(
      role: role,
      peerName: acceptName is String ? _clean(acceptName, 40) : peer.name,
      channel: ch,
      code: code,
      quality: role == SessionRole.sharer
          ? StreamQuality.fromJson(accept['quality'], own)
          : own,
    );
    _begin(session);
    return session;
  }

  void _begin(BeamSession s) {
    session.value = s;
    unawaited(s.start());
    s.ended.then((_) {
      if (session.value == s) session.value = null;
    });
  }

  Never _reject(SignalingChannel ch, String reason) {
    ch.send({'t': 'reject', 'reason': reason});
    throw SignalingException(reason);
  }

  static String _clean(String s, int max) {
    final c = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    final short = c.length > max ? c.substring(0, max) : c;
    return short.isEmpty ? 'Unnamed device' : short;
  }
}
