import 'package:flutter/widgets.dart';

import 'services/discovery_service.dart';
import 'services/settings_store.dart';

/// Makes the app-wide services available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.discovery,
    required super.child,
  });

  final SettingsStore settings;
  final DiscoveryService discovery;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      settings != oldWidget.settings || discovery != oldWidget.discovery;
}
