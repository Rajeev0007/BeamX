import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';

/// Holds the current settings and saves every change to disk.
class SettingsStore extends ValueNotifier<BeamSettings> {
  SettingsStore._(this._prefs, super.value);

  static const _key = 'beamx.settings.v1';
  final SharedPreferences? _prefs;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var settings = BeamSettings(deviceName: defaultDeviceName());
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        settings = BeamSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('BeamX: ignoring unreadable settings ($e)');
      }
    }
    return SettingsStore._(prefs, settings);
  }

  /// In-memory store for tests.
  @visibleForTesting
  factory SettingsStore.memory([BeamSettings initial = const BeamSettings()]) =>
      SettingsStore._(null, initial);

  void update(BeamSettings Function(BeamSettings) change) {
    value = change(value);
    _prefs?.setString(_key, jsonEncode(value.toJson()));
  }

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(value.toJson());

  /// Returns false if [json] is not a valid settings export.
  bool importJson(String json) {
    try {
      final map = jsonDecode(json);
      if (map is! Map<String, dynamic>) return false;
      update((_) => BeamSettings.fromJson(map));
      return true;
    } catch (_) {
      return false;
    }
  }

  void reset() => update((_) => BeamSettings(deviceName: defaultDeviceName()));

  /// A friendly first-run name, e.g. "DESKTOP-42 (Windows)" or "Android phone".
  static String defaultDeviceName() {
    if (kIsWeb) return 'Browser';
    if (Platform.isAndroid) return 'Android phone';
    if (Platform.isIOS) return 'iPhone';
    final host = Platform.localHostname;
    final os = Platform.isWindows
        ? 'Windows'
        : Platform.isMacOS
            ? 'Mac'
            : 'Linux';
    return host.isEmpty || host == 'localhost' ? '$os PC' : '$host ($os)';
  }
}
