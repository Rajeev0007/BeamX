import 'package:flutter/widgets.dart';

import 'services/connection_service.dart';
import 'services/discovery_service.dart';
import 'services/pairing_service.dart';
import 'services/settings_store.dart';
import 'services/transfer_service.dart';
import 'services/trust_store.dart';

/// The app-wide services, created once at startup.
class AppServices {
  const AppServices({
    required this.settings,
    required this.discovery,
    required this.pairing,
    required this.connection,
    required this.trust,
    required this.transfers,
  });

  final SettingsStore settings;
  final DiscoveryService discovery;
  final PairingService pairing;
  final ConnectionService connection;
  final TrustStore trust;
  final TransferService transfers;
}

/// Makes [AppServices] available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  SettingsStore get settings => services.settings;
  DiscoveryService get discovery => services.discovery;
  PairingService get pairing => services.pairing;
  ConnectionService get connection => services.connection;
  TrustStore get trust => services.trust;
  TransferService get transfers => services.transfers;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
