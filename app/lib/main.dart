import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'services/discovery_service.dart';
import 'services/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final discovery = DiscoveryService(settings);
  runApp(BeamXApp(settings: settings, discovery: discovery));
  discovery.start();
}
