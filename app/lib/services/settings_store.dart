import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';

/// Holds the current settings and saves every change to disk.
class SettingsStore extends ValueNotifier<BeamSettings> {
  SettingsStore._(this._prefs, super.value);

  static const _key = 'beamx.settings.v1';
  static const _profilesKey = 'beamx.customProfiles.v1';

  /// Profiles the user saved: name → streaming settings.
  final ValueNotifier<List<CustomProfile>> customProfiles = ValueNotifier(const []);

  void _loadProfiles() {
    try {
      final list = jsonDecode(_prefs?.getString(_profilesKey) ?? '[]');
      if (list is List) {
        customProfiles.value = List.unmodifiable([
          for (final j in list)
            if (j is Map<String, dynamic> && j['name'] is String && j['s'] is Map<String, dynamic>)
              CustomProfile(j['name'] as String, j['s'] as Map<String, dynamic>),
        ]);
      }
    } catch (_) {}
  }

  void _saveProfiles() => _prefs?.setString(_profilesKey,
      jsonEncode([for (final p in customProfiles.value) {'name': p.name, 's': p.values}]));

  /// Saves the current streaming settings as a profile called [name].
  void saveProfile(String name) {
    final v = value.toJson();
    final picked = {for (final k in CustomProfile.keys) k: v[k]};
    customProfiles.value = List.unmodifiable([
      ...customProfiles.value.where((p) => p.name != name),
      CustomProfile(name, picked),
    ]);
    _saveProfiles();
    update((s) => s.copyWith(activeProfile: name));
  }

  void deleteProfile(String name) {
    customProfiles.value =
        List.unmodifiable(customProfiles.value.where((p) => p.name != name));
    _saveProfiles();
  }

  void applyProfile(CustomProfile p) {
    final merged = {...value.toJson(), ...p.values, 'activeProfile': p.name};
    update((_) => BeamSettings.fromJson(merged));
  }
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
    return SettingsStore._(prefs, settings).._loadProfiles();
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

/// A user-saved set of streaming settings.
class CustomProfile {
  const CustomProfile(this.name, this.values);

  /// The settings a profile stores.
  static const keys = [
    'resolution', 'fps', 'autoBitrate', 'bitrateMbps', 'codec', //
    'audioEnabled', 'audioOutput', 'micSharing', 'showStatsOverlay', 'viewOnly',
  ];

  final String name;
  final Map<String, dynamic> values;

  String get summary {
    final r = values['resolution'], f = values['fps'];
    return '${r == 2160 ? '4K' : '${r}p'} · $f FPS · '
        '${values['autoBitrate'] == true ? 'auto bitrate' : '${(values['bitrateMbps'] as num?)?.round()} Mbps'}';
  }
}
