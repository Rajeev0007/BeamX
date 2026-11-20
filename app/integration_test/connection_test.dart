// End-to-end test: two BeamX "devices" in one process connect over the
// machine's network, stream the (virtual) screen and stay connected.
// Run in CI under Xvfb:  flutter test integration_test -d linux
import 'dart:async';
import 'dart:io';

import 'package:beamx/models/peer_device.dart';
import 'package:beamx/models/settings.dart';
import 'package:beamx/services/beam_session.dart';
import 'package:beamx/services/connection_service.dart';
import 'package:beamx/services/diag_log.dart';
import 'package:beamx/services/discovery_service.dart';
import 'package:beamx/services/pairing_service.dart';
import 'package:beamx/services/settings_store.dart';
import 'package:beamx/services/transfer_service.dart';
import 'package:beamx/services/trust_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Device {
  _Device(this.name, this.settings, this.trust, this.pairing, this.connection);
  final String name;
  final SettingsStore settings;
  final TrustStore trust;
  final PairingService pairing;
  final ConnectionService connection;

  static Future<_Device> create(String name, String id, int port) async {
    final settings = SettingsStore.memory(BeamSettings(
      deviceName: name,
      port: port,
      requireApproval: false,
      audioEnabled: false,
      clipboardSync: ClipboardSync.off,
      discoverable: false,
      resolution: 720,
      fps: 30,
    ));
    final trust = await TrustStore.forTest(id);
    final pairing = PairingService();
    final discovery = DiscoveryService(settings, trust.deviceId);
    final connection = ConnectionService(
        settings, pairing, trust, TransferService(), discovery);
    await connection.start();
    return _Device(name, settings, trust, pairing, connection);
  }
}

Future<String> _lanAddress() async {
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      if (!a.isLoopback) return a.address;
    }
  }
  return '127.0.0.1';
}

Future<void> _waitFor(bool Function() ok, Duration timeout, String what) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two devices connect, stream and stay connected', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final host = await _Device.create('Host PC', 'a' * 32, 47900);
    final client = await _Device.create('Client', 'b' * 32, 47901);
    final address = await _lanAddress();
    DiagLog.add('test: host at $address:47900');

    // The client views the host's screen.
    final viewer = await client.connection.connect(
      peer: PeerDevice(
        id: 'host',
        name: 'Host PC',
        platform: 'linux',
        address: address,
        port: 47900,
        lastSeen: DateTime.now(),
      ),
      code: host.pairing.code.value,
      mode: StreamMode.view,
    );
    final sharer = host.connection.session.value!;
    expect(sharer.isSharer, isTrue);

    try {
      await _waitFor(() => viewer.phase == SessionPhase.live || viewer.phase == SessionPhase.ended,
          const Duration(seconds: 30), 'viewer connecting');
      expect(viewer.endReason, isNull, reason: 'viewer ended: ${viewer.endReason}');
      expect(viewer.phase, SessionPhase.live);
      DiagLog.add('test: connected');

      // Video frames arrive and keep arriving for a minute.
      double? lastFps;
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final st = viewer.stats.value;
        lastFps = st.fps;
        DiagLog.add('test: t=${(i + 1) * 5}s viewer ${st.width}x${st.height} '
            'fps=${st.fps?.toStringAsFixed(1)} '
            'kbps=${st.kbps?.round()} rtt=${st.rttMs?.round()} '
            'viewer=${viewer.phase.name} sharer=${sharer.phase.name}');
        expect(viewer.phase, isNot(SessionPhase.ended),
            reason: 'viewer ended: ${viewer.endReason}');
        expect(sharer.phase, isNot(SessionPhase.ended),
            reason: 'sharer ended: ${sharer.endReason}');
      }
      expect(viewer.stats.value.width, greaterThan(0), reason: 'no video received');
      expect(lastFps, isNotNull);
      expect(viewer.link.ready.value, isTrue, reason: 'data channel not open');
    } finally {
      // ignore: avoid_print
      print('===== BeamX diagnostics log =====\n${DiagLog.text}\n=====');
      await viewer.close('test done');
      await sharer.close('test done');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
