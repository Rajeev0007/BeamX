import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/save_location.dart';
import 'services/settings_store.dart';
import 'services/transfer_service.dart';
import 'services/trust_store.dart';
import 'services/window_control.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowControl.init();
  final settings = await SettingsStore.load();
  final trust = await TrustStore.load();
  void applyDeviceSettings() {
    final s = settings.value;
    SaveLocation.custom = s.saveFolder;
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setPreferredOrientations(switch (s.orientation) {
        'portrait' => const [DeviceOrientation.portraitUp],
        'landscape' => const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        _ => const <DeviceOrientation>[],
      });
    }
  }

  applyDeviceSettings();
  settings.addListener(applyDeviceSettings);
  final discovery = DiscoveryService(settings, trust.deviceId);
  final pairing = PairingService();
  final transfers = TransferService();
  final connection = ConnectionService(settings, pairing, trust, transfers, discovery);
  runApp(BeamXApp(
    services: AppServices(
      settings: settings,
      discovery: discovery,
      pairing: pairing,
      connection: connection,
      trust: trust,
      transfers: transfers,
    ),
  ));
  discovery.start();
  connection.start();
}
