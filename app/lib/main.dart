import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'app_scope.dart';
import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/settings_store.dart';
import 'services/transfer_service.dart';
import 'services/trust_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final trust = await TrustStore.load();
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
