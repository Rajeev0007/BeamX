import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final discovery = DiscoveryService(settings);
  final pairing = PairingService();
  final connection = ConnectionService(settings, pairing, discovery);
  runApp(BeamXApp(
    settings: settings,
    discovery: discovery,
    pairing: pairing,
    connection: connection,
  ));
  discovery.start();
  connection.start();
}
