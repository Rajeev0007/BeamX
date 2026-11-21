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
import 'package:beamx/services/password_auth.dart';
import 'package:beamx/services/relay_client.dart';
import 'package:beamx/services/settings_store.dart';
import 'package:beamx/services/transfer_service.dart';
import 'package:beamx/services/trust_store.dart';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
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

  static Future<_Device> create(String name, String id, int port,
      {bool internet = false, int resolution = 720, int fps = 30}) async {
    final settings = SettingsStore.memory(BeamSettings(
      internetEnabled: internet,
      passwordAccess: internet,
      deviceName: name,
      port: port,
      requireApproval: false,
      audioEnabled: false,
      clipboardSync: ClipboardSync.off,
      discoverable: false,
      resolution: resolution,
      fps: fps,
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

/// Fills the window with constantly changing coloured blocks, so the
/// stream has real motion to encode (a still screen needs almost no data).
class _Motion extends StatefulWidget {
  const _Motion();
  @override
  State<_Motion> createState() => _MotionState();
}

class _MotionState extends State<_Motion> {
  late final Timer _t =
      Timer.periodic(const Duration(milliseconds: 33), (_) => setState(() => _seed++));
  int _seed = 0;
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _Blocks(_seed), size: Size.infinite);
}

class _Blocks extends CustomPainter {
  _Blocks(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(seed);
    for (var i = 0; i < 300; i++) {
      canvas.drawRect(
        Rect.fromLTWH(r.nextDouble() * size.width, r.nextDouble() * size.height,
            20 + r.nextDouble() * 120, 20 + r.nextDouble() * 120),
        Paint()..color = Color(0xFF000000 | r.nextInt(0xFFFFFF)),
      );
    }
  }

  @override
  bool shouldRepaint(_Blocks old) => old.seed != seed;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('quality: sharp picture and real bitrate with motion', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: _Motion()));
    final host = await _Device.create('Host PC', 'e' * 32, 47920);
    final client = await _Device.create('Client', 'f' * 32, 47921, resolution: 1080);
    final address = await _lanAddress();
    final viewer = await client.connection.connect(
      peer: PeerDevice(id: 'host', name: 'Host PC', platform: 'linux',
          address: address, port: 47920, lastSeen: DateTime.now()),
      code: host.pairing.code.value,
      mode: StreamMode.view,
    );
    final sharer = host.connection.session.value!;
    try {
      await _waitFor(() => viewer.phase == SessionPhase.live, const Duration(seconds: 30), 'connect');
      int short() {
        final st = viewer.stats.value;
        return min(st.width ?? 0, st.height ?? 0);
      }

      var bestKbps = 0.0, bestShort = 0;
      double? fps;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final st = viewer.stats.value;
        bestKbps = max(bestKbps, st.kbps ?? 0);
        bestShort = max(bestShort, short());
        fps = st.fps;
        DiagLog.add('test: 1080p t=${i + 1}s ${st.width}x${st.height} fps=${st.fps} '
            'kbps=${st.kbps?.round()} codec=${st.codec}');
      }
      // The old bugs: ~486 px pictures and a ~2.5 Mbps ceiling.
      expect(bestShort, greaterThanOrEqualTo(720), reason: 'picture too small');
      expect(bestKbps, greaterThan(1000), reason: 'bitrate too low with motion');
      expect(fps ?? 0, greaterThanOrEqualTo(10), reason: 'frame rate too low');

      // Changing the quality on the viewer takes effect on the sharer.
      viewer.requestQuality(const StreamQuality(
          resolution: 480, fps: 30, autoBitrate: true, mbps: 8,
          codec: VideoCodec.h264, audio: false));
      await _waitFor(() => short() > 0 && short() <= 480,
          const Duration(seconds: 15), 'switch to 480p');
      DiagLog.add('test: switched to ${viewer.stats.value.width}x${viewer.stats.value.height}');
    } finally {
      // ignore: avoid_print
      print('===== BeamX diagnostics log =====\n${DiagLog.text}\n=====');
      await viewer.close('test done');
      await sharer.close('test done');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

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
    await _streamFor(viewer, sharer, const Duration(seconds: 60));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('connect from anywhere: ID + password over the public server', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final host = await _Device.create('Remote PC', 'c' * 32, 47910, internet: true);
    final client = await _Device.create('Phone', 'd' * 32, 47911, internet: true);
    const password = 'correct horse battery';
    await host.trust.setPasswordKey(
        await PasswordAuth.deriveKey(password, host.trust.deviceId));

    await _waitFor(
        () => host.connection.relayStatus.value.state == RelayState.online &&
            client.connection.relayStatus.value.state == RelayState.online,
        const Duration(seconds: 30),
        'both devices online on the public server');
    DiagLog.add('test: both online, host ID ${host.connection.myId}');

    // Wrong password is refused.
    final peer = await client.connection.resolveId(host.connection.myId);
    expect(peer.viaInternet, isTrue);
    await expectLater(
      client.connection.connect(
          peer: peer, code: null, password: 'wrong password!', mode: StreamMode.view),
      throwsA(predicate((e) => '$e'.contains('Wrong password'))),
    );

    final viewer = await client.connection.connect(
        peer: peer, code: null, password: password, mode: StreamMode.view);
    final sharer = host.connection.session.value!;
    await _streamFor(viewer, sharer, const Duration(seconds: 30));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _streamFor(BeamSession viewer, BeamSession sharer, Duration time) async {
    try {
      await _waitFor(() => viewer.phase == SessionPhase.live || viewer.phase == SessionPhase.ended,
          const Duration(seconds: 30), 'viewer connecting');
      expect(viewer.endReason, isNull, reason: 'viewer ended: ${viewer.endReason}');
      expect(viewer.phase, SessionPhase.live);
      DiagLog.add('test: connected');

      // Video frames arrive and keep arriving.
      double? lastFps;
      for (var i = 0; i < time.inSeconds ~/ 5; i++) {
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
      await Future<void>.delayed(const Duration(seconds: 2));
    }
}
