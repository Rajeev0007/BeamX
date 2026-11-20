import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'screens/shell.dart';
import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/settings_store.dart';
import 'theme/app_theme.dart';

class BeamXApp extends StatelessWidget {
  const BeamXApp({
    super.key,
    required this.settings,
    required this.discovery,
    required this.pairing,
    required this.connection,
  });

  final SettingsStore settings;
  final DiscoveryService discovery;
  final PairingService pairing;
  final ConnectionService connection;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      discovery: discovery,
      pairing: pairing,
      connection: connection,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, child) {
          final s = settings.value;
          final seed = AppTheme.accent(s.accentIndex);
          return MaterialApp(
            title: 'BeamX',
            debugShowCheckedModeBanner: false,
            themeMode: s.themeMode,
            theme: AppTheme.build(seed, Brightness.light),
            darkTheme: AppTheme.build(seed, Brightness.dark),
            themeAnimationDuration: const Duration(milliseconds: 350),
            home: child,
          );
        },
        // Built once, so theme changes don't reset navigation state.
        child: const AppShell(),
      ),
    );
  }
}
