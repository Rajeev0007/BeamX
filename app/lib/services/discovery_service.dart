import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer_device.dart';
import 'settings_store.dart';

/// Finds other BeamX devices on the same local network.
///
/// Each device broadcasts a small JSON announcement over UDP every
/// [_interval] and listens for announcements from others. Packets are
/// untrusted input, so they are size-limited and strictly validated.
///
/// Note: iOS blocks UDP broadcast unless Apple grants a special entitlement,
/// so on iOS this service only listens; pairing by QR code or IP address is
/// used there instead.
class DiscoveryService {
  DiscoveryService(this._settings, this.selfId);

  static const discoveryPort = 47801;
  static const _magic = 'beamx';
  static const _protocolVersion = 1;
  static const _maxPacketBytes = 1024;
  static const _interval = Duration(seconds: 2);
  static const _expireAfter = Duration(seconds: 8);

  final SettingsStore _settings;
  /// This device's permanent ID (see TrustStore).
  final String selfId;

  final ValueNotifier<List<PeerDevice>> peers = ValueNotifier(const []);
  final ValueNotifier<String?> error = ValueNotifier(null);

  final Map<String, PeerDevice> _peers = {};
  RawDatagramSocket? _socket;
  Timer? _timer;

  static String get platform =>
      kIsWeb ? 'web' : Platform.operatingSystem.toLowerCase();

  static bool get canBroadcast => !kIsWeb && !Platform.isIOS;

  Future<void> start() async {
    if (kIsWeb || _socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) _handle(dg);
        }
      });
      _socket = socket;
      error.value = null;
      _timer = Timer.periodic(_interval, (_) => _tick());
      _tick();
    } on SocketException catch (e) {
      error.value = 'Local discovery unavailable: ${e.message}';
    }
  }

  void _tick() {
    final s = _settings.value;
    if (canBroadcast && s.discoverable) {
      final packet = utf8.encode(jsonEncode({
        'app': _magic,
        'v': _protocolVersion,
        'id': selfId,
        'name': s.deviceName,
        'platform': platform,
        'port': s.port,
      }));
      try {
        _socket?.send(
            packet, InternetAddress('255.255.255.255'), discoveryPort);
      } on SocketException catch (e) {
        error.value = 'Broadcast failed: ${e.message}';
      }
    }
    _prune();
  }

  void _handle(Datagram dg) {
    if (dg.data.length > _maxPacketBytes) return;
    final peer = parseAnnouncement(dg.data, dg.address.address, selfId);
    if (peer == null) return;
    _peers[peer.id] = peer;
    _publish();
  }

  /// Parses and validates an announcement packet. Returns null if invalid
  /// or if it came from this device.
  @visibleForTesting
  static PeerDevice? parseAnnouncement(
      List<int> data, String address, String selfId) {
    try {
      final j = jsonDecode(utf8.decode(data));
      if (j is! Map) return null;
      if (j['app'] != _magic || j['v'] != _protocolVersion) return null;
      final id = j['id'];
      final name = j['name'];
      final platform = j['platform'];
      final port = j['port'];
      if (id is! String || id.length > 64 || id == selfId) return null;
      if (name is! String || platform is! String || port is! int) return null;
      if (port < 1 || port > 65535) return null;
      return PeerDevice(
        id: id,
        name: _clean(name, 40),
        platform: _clean(platform, 16).toLowerCase(),
        address: address,
        port: port,
        lastSeen: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Removes control characters and limits length of untrusted text.
  static String _clean(String s, int maxLen) {
    final cleaned = s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    final short = cleaned.length > maxLen ? cleaned.substring(0, maxLen) : cleaned;
    return short.isEmpty ? 'Unnamed device' : short;
  }

  void _prune() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere((_, p) => now.difference(p.lastSeen) > _expireAfter);
    if (_peers.length != before) _publish();
  }

  void _publish() {
    final list = _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    peers.value = List.unmodifiable(list);
  }

  void dispose() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }
}
