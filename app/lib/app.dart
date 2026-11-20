import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'screens/shell.dart';
import 'services/prompts.dart';
import 'theme/app_theme.dart';

class BeamXApp extends StatelessWidget {
  const BeamXApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final settings = services.settings;
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, child) {
          final s = settings.value;
          final seed = AppTheme.accent(s.accentIndex);
          return MaterialApp(
            title: 'BeamX',
            navigatorKey: navigatorKey,
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
