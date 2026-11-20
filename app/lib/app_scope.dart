import 'package:flutter/widgets.dart';

import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/settings_store.dart';

/// Makes the app-wide services available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.discovery,
    required this.pairing,
    required this.connection,
    required super.child,
  });

  final SettingsStore settings;
  final DiscoveryService discovery;
  final PairingService pairing;
  final ConnectionService connection;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
