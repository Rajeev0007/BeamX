import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/peer_device.dart';
import 'beam_session.dart';
import 'data_link.dart';
import 'diag_log.dart';
import 'discovery_service.dart';
import 'pairing_service.dart';
import 'peerjs_relay.dart';
import 'password_auth.dart';
import 'relay_client.dart';
import 'screen_capture.dart';
import 'settings_store.dart';
import 'signaling.dart';
import 'transfer_service.dart';
import 'trust_store.dart';

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
    required this.alreadyTrusted,
  });

  final String name;
  final String platform;
  final String address;
  final StreamMode mode;

  /// True if this device is trusted already (no need to offer trust).
  final bool alreadyTrusted;

  /// Set by [accept]: let this device connect without a code next time.
  bool trust = false;

  /// Set by [accept]: let the viewer control this device.
  bool control = false;
  final _decision = Completer<bool>();

  /// Completes when the request is accepted, declined or expires.
  Future<bool> get decided => _decision.future;

  void accept({bool trust = false, bool control = false}) {
    this.trust = trust;
    this.control = control;
    if (!_decision.isCompleted) _decision.complete(true);
  }

  void decline() {
    if (!_decision.isCompleted) _decision.complete(false);
  }
}

/// Accepts incoming connections and makes outgoing ones.
///
/// Every BeamX device runs a small WebSocket server on the configured port.
/// The handshake is: challenge (nonce) → hello (proof of the pairing code,
/// or of a trust key) → user approval → accept. After that the
/// [BeamSession] takes over the channel.
class ConnectionService {
  ConnectionService(this._settings, this._pairing, this._trust,
      this._transfers, this._discovery) {
    _port = _settings.value.port;
    _relayUrl = _relayTarget();
    _settings.addListener(_onSettings);
  }

  InternetRelay? _relay;
  late String _relayUrl;
  final _lockout = PasswordLockout();

  static const _publicServer = 'public';

  /// Your own server's address, [_publicServer] for the free public one,
  /// or '' when "connect from anywhere" is off.
  String _relayTarget() {
    final s = _settings.value;
    if (!s.internetEnabled) return '';
    final own = s.signalingServer.trim();
    return own.isEmpty ? _publicServer : own;
  }

  /// True when using the free public server rather than your own.
  bool get usingPublicServer => _relayUrl == _publicServer;

  /// This device's 9-digit ID, shown to people who want to connect.
  String get myId => RelayClient.internetIdFor(_trust.deviceId);

  /// Internet server connection state (off if no server is set).
  final ValueNotifier<RelayStatus> relayStatus =
      ValueNotifier(const RelayStatus(RelayState.off));

  void _startRelay() {
    _relay?.status.removeListener(_onRelayStatus);
    _relay?.stop();
    _relay = null;
    relayStatus.value = const RelayStatus(RelayState.off);
    final url = _relayUrl.trim();
    if (url.isEmpty || kIsWeb) return;
    final InternetRelay r = url == _publicServer
        ? PeerJsRelay(
            internetId: myId,
            // A separate secret from the own-server key, so neither server
            // learns the other's.
            token: sha256
                .convert(utf8.encode('peerjs|${_trust.relayKey}'))
                .toString()
                .substring(0, 24),
            onIncoming: _onRelayIncoming,
          )
        : RelayClient(
            url: url,
            deviceId: _trust.deviceId,
            key: _trust.relayKey,
            onIncoming: _onRelayIncoming,
          );
    r.status.addListener(_onRelayStatus);
    _relay = r;
    r.start();
  }

  void _onRelayStatus() {
    final st = _relay!.status.value;
    DiagLog.add('internet: ${st.state.name}${st.message == null ? '' : ' (${st.message})'}');
    relayStatus.value = st;
  }

  Future<void> _onRelayIncoming(SignalingTransport t, String from) async {
    final ch = SignalingChannel(t);
    await _hostChannel(ch, 'Internet · ID ${RelayClient.format(from)}',
        iceServers: _relay?.iceServers ?? const []);
  }

  final SettingsStore _settings;
  final PairingService _pairing;
  final TrustStore _trust;
  final TransferService _transfers;
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
    if (_relay == null) _startRelay();
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
    final url = _relayTarget();
    if (url != _relayUrl) {
      _relayUrl = url;
      _startRelay();
    }
  }

  Future<void> _onRequest(HttpRequest req) async {
    if (req.uri.path != '/beamx' || !WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 30);
    final ch = SignalingChannel(WebSocketTransport(ws));
    final address = req.connectionInfo?.remoteAddress.address ?? 'unknown';
    await _hostChannel(ch, address);
  }

  /// Runs the host side of the handshake on [ch], from the local network or
  /// the internet relay.
  Future<void> _hostChannel(SignalingChannel ch, String address,
      {List<Map<String, dynamic>> iceServers = const []}) async {
    if (busy) {
      ch.send({'t': 'reject', 'reason': 'The device is busy with another session'});
      ch.close('busy');
      return;
    }
    _handshaking = true;
    DiagLog.add('incoming connection from $address');
    try {
      await _handshakeAsHost(ch, address, iceServers);
      DiagLog.add('incoming connection accepted');
    } on SignalingException catch (e) {
      DiagLog.add('incoming connection refused: ${e.message}');
      ch.close(e.message);
    } catch (e) {
      DiagLog.add('incoming connection failed: $e');
      ch.close('handshake failed');
    } finally {
      _handshaking = false;
      pending.value = null;
    }
  }

  Map<String, Object> _me() {
    final s = _settings.value;
    return {
      'id': _trust.deviceId,
      'name': s.deviceName,
      'platform': DiscoveryService.platform,
    };
  }

  Future<void> _handshakeAsHost(SignalingChannel ch, String address,
      List<Map<String, dynamic>> iceServers) async {
    final s = _settings.value;
    final nonce = PairingService.newNonce();
    ch.send({
      't': 'challenge',
      'v': SignalingChannel.protocolVersion,
      'nonce': nonce,
      ..._me(),
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
    final safePlatform = _clean(platform, 16);

    // A trust key, the owner's password, or the current pairing code.
    final String key;
    final bool usedTrust;
    var usedPassword = false;
    final auth = hello['auth'] ?? (hello['trusted'] == true ? 'trust' : 'code');
    if (auth == 'password') {
      final pk = _trust.passwordKey;
      if (!s.passwordAccess || pk == null) {
        _reject(ch, '${s.deviceName} doesn\'t accept passwords. '
            'Use its pairing code.', code: 'no-password');
      }
      if (_lockout.locked) {
        _reject(ch, 'Too many wrong passwords. Try again in 10 minutes.',
            code: 'locked');
      }
      if (!PairingService.constantTimeEquals(
          PairingService.proof(pk, nonce, id), proof)) {
        _lockout.fail();
        // A short delay slows down guessing even before the lock.
        await Future<void>.delayed(const Duration(seconds: 2));
        _reject(ch, 'Wrong password', code: 'bad-password');
      }
      _lockout.success();
      key = pk;
      usedTrust = false;
      usedPassword = true;
    } else if (auth == 'trust') {
      final secret = _trust.secretFor(id);
      if (secret == null ||
          !PairingService.constantTimeEquals(
              PairingService.proof(secret, nonce, id), proof)) {
        _reject(ch, '${s.deviceName} no longer trusts this device. '
            'Enter its pairing code.', code: 'untrusted');
      }
      key = secret;
      usedTrust = true;
    } else {
      key = _pairing.code.value;
      usedTrust = false;
      if (!_pairing.verify(nonce, id, proof)) {
        _reject(ch, 'Wrong pairing code');
      }
    }
    if (mode == StreamMode.view && !ScreenCapture.supported) {
      _reject(ch, ScreenCapture.unsupportedReason);
    }

    var grantTrust = false;
    var allowControl = usedPassword && s.passwordControl;
    final skipApproval = (usedTrust && s.autoConnectTrusted) ||
        (usedPassword && !s.passwordAsk);
    if (s.requireApproval && !skipApproval) {
      final req = IncomingRequest(
        name: safeName,
        platform: safePlatform,
        address: address,
        mode: mode,
        alreadyTrusted: usedTrust,
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
      grantTrust = req.trust && !usedTrust;
      allowControl = req.control || allowControl;
    }

    // One-time code: the next pairing needs a new one.
    if (!usedTrust && !usedPassword) _pairing.regenerate();

    final own = StreamQuality.fromSettings(_settings.value);
    ch.send({
      't': 'accept',
      'name': s.deviceName,
      if (mode == StreamMode.share) 'quality': own.toJson(),
    });

    final role = mode == StreamMode.view ? SessionRole.sharer : SessionRole.viewer;
    Map<String, Object>? trustPayload;
    if (grantTrust) {
      final secret = _trust.trust(id: id, name: safeName, platform: safePlatform);
      trustPayload = {..._me(), 'secret': secret};
    }
    _begin(BeamSession(
      role: role,
      peerName: safeName,
      channel: ch,
      code: key,
      quality: role == SessionRole.sharer
          ? StreamQuality.fromJson(hello['quality'], own)
          : own,
      link: DataLink(
        peerName: safeName,
        settings: _settings,
        transfers: _transfers,
        trust: _trust,
        isSharer: role == SessionRole.sharer,
        allowControl: allowControl && role == SessionRole.sharer,
        expectedPeerId: id,
        trustToSend: trustPayload,
      ),
      iceServers: iceServers,
      wantMic: role == SessionRole.viewer && s.micSharing,
    ));
  }

  /// Finds the device with [internetId]: on the local network first (even
  /// if it's hidden), otherwise through the internet server.
  Future<PeerDevice> resolveId(String internetId) async {
    if (internetId == myId) {
      throw SignalingException('That\'s this device\'s own ID');
    }
    final local = await _discovery.findById(internetId);
    if (local != null) return local;
    if (relayStatus.value.state == RelayState.online) {
      return PeerDevice(
        id: 'internet-$internetId',
        name: 'BeamX ${RelayClient.format(internetId)}',
        platform: 'unknown',
        address: 'internet',
        port: 0,
        lastSeen: DateTime.now(),
        internetId: internetId,
      );
    }
    throw SignalingException(
        relayStatus.value.state == RelayState.off
            ? 'No device with that ID on this network. To reach devices '
                'elsewhere, turn on Connect from anywhere in Settings.'
            : 'No device with that ID on this network, and the internet '
                'server isn\'t connected right now.');
  }

  /// True if [peer] gave this device a trust key, so no code is needed.
  bool isTrustedBy(PeerDevice peer) => _trust.keyFor(peer.id) != null;

  /// Connects to [peer] with the pairing [code] shown on it, or with a
  /// saved trust key if [code] is null. Completes when the other device
  /// accepts; throws a [SignalingException] with a readable message otherwise.
  Future<BeamSession> connect({
    required PeerDevice peer,
    required String? code,
    required StreamMode mode,
    bool allowControl = false,
    String? password,
  }) async {
    if (busy) throw SignalingException('Finish the current session first');
    if (mode == StreamMode.share && !ScreenCapture.supported) {
      throw SignalingException(ScreenCapture.unsupportedReason);
    }
    _handshaking = true;
    DiagLog.add('connecting to ${peer.viaInternet ? 'internet ID ${peer.internetId}' : peer.address} '
        '(${mode.name}, ${password != null ? 'password' : code != null ? 'code' : 'trusted'})');
    try {
      final SignalingChannel ch;
      final internetId = peer.internetId;
      if (internetId != null) {
        final relay = _relay;
        if (relay == null) {
          throw SignalingException(
              'Set an internet server in Settings → Connection first');
        }
        ch = SignalingChannel(await relay.dial(internetId));
      } else {
        try {
          ch = await SignalingChannel.connect(peer.address, peer.port);
        } catch (_) {
          throw SignalingException(
              'Can\'t reach ${peer.name}. Check that both devices are on the '
              'same Wi-Fi and BeamX is open on it.');
        }
      }
      try {
        final session = await _handshakeAsClient(ch, peer, code, password, mode,
            allowControl,
            internetId != null ? (_relay?.iceServers ?? const []) : const []);
        DiagLog.add('connected, starting stream');
        return session;
      } catch (e) {
        DiagLog.add('connection failed: $e');
        ch.close('failed');
        rethrow;
      }
    } finally {
      _handshaking = false;
    }
  }

  Future<BeamSession> _handshakeAsClient(
      SignalingChannel ch,
      PeerDevice peer,
      String? code,
      String? password,
      StreamMode mode,
      bool allowControl,
      List<Map<String, dynamic>> iceServers) async {
    final challenge =
        await ch.next('challenge', timeout: const Duration(seconds: 10));
    final nonce = challenge['nonce'];
    final hostId = challenge['id'];
    if (nonce is! String || nonce.length > 100 ||
        hostId is! String || hostId.length > 64) {
      throw SignalingException('Not a BeamX device, or an older BeamX version');
    }
    // Over the internet, make sure the answering device really owns the ID
    // we dialed before sending any proof. An impostor holding the ID on the
    // server doesn't know the device ID it's derived from.
    final dialed = peer.internetId;
    if (dialed != null && RelayClient.internetIdFor(hostId) != dialed) {
      throw SignalingException(
          'Security check failed: the device answering isn\'t the real '
          '${RelayClient.format(dialed)}. Nothing was sent.');
    }
    final trustKey = code == null && password == null ? _trust.keyFor(hostId) : null;
    final passwordKey =
        password == null ? null : await PasswordAuth.deriveKey(password, hostId);
    final key = code ?? passwordKey ?? trustKey;
    if (key == null) {
      throw SignalingException(
          'Enter the password or pairing code of ${peer.name}',
          code: 'need-code');
    }
    final auth = passwordKey != null
        ? 'password'
        : trustKey != null
            ? 'trust'
            : 'code';

    final s = _settings.value;
    final own = StreamQuality.fromSettings(s);
    ch.send({
      't': 'hello',
      'v': SignalingChannel.protocolVersion,
      ..._me(),
      'mode': mode.name,
      'trusted': trustKey != null,
      'auth': auth,
      'proof': PairingService.proof(key, nonce, _trust.deviceId),
      if (mode == StreamMode.view) 'quality': own.toJson(),
    });

    // Waits while the other person decides.
    final Map<String, dynamic> accept;
    try {
      accept = await ch.next('accept', timeout: const Duration(seconds: 75));
    } on SignalingException catch (e) {
      if (e.code == 'untrusted') _trust.forgetKey(hostId);
      rethrow;
    }
    final role =
        mode == StreamMode.view ? SessionRole.viewer : SessionRole.sharer;
    final acceptName = accept['name'];
    final peerName = acceptName is String ? _clean(acceptName, 40) : peer.name;
    final session = BeamSession(
      role: role,
      peerName: peerName,
      channel: ch,
      code: key,
      quality: role == SessionRole.sharer
          ? StreamQuality.fromJson(accept['quality'], own)
          : own,
      link: DataLink(
        peerName: peerName,
        settings: _settings,
        transfers: _transfers,
        trust: _trust,
        isSharer: role == SessionRole.sharer,
        allowControl: allowControl && role == SessionRole.sharer,
        expectedPeerId: hostId,
      ),
      iceServers: iceServers,
      wantMic: role == SessionRole.viewer && s.micSharing,
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

  Never _reject(SignalingChannel ch, String reason, {String? code}) {
    ch.send({'t': 'reject', 'reason': reason, 'code': ?code});
    throw SignalingException(reason, code: code);
  }

  static String _clean(String s, int max) {
    final c = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    final short = c.length > max ? c.substring(0, max) : c;
    return short.isEmpty ? 'Unnamed device' : short;
  }
}
