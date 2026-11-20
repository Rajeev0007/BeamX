import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A device allowed to connect to this one without a pairing code.
@immutable
class TrustedDevice {
  const TrustedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.secret,
    required this.added,
  });

  final String id;
  final String name;
  final String platform;

  /// 256-bit random key, exchanged once over the encrypted WebRTC channel.
  final String secret;
  final DateTime added;

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'secret': secret,
        'added': added.toIso8601String(),
      };

  static TrustedDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], platform = j['platform'];
    final secret = j['secret'], added = j['added'];
    if (id is! String || name is! String || platform is! String ||
        secret is! String || added is! String) {
      return null;
    }
    return TrustedDevice(
      id: id,
      name: name,
      platform: platform,
      secret: secret,
      added: DateTime.tryParse(added) ?? DateTime.now(),
    );
  }
}

/// Stores this device's permanent ID and two lists of trusted keys:
/// - [trustedByMe]: devices that may connect to me without a code.
/// - keys other devices gave me, so I can connect to them without a code.
class TrustStore {
  TrustStore._(this._prefs, this.deviceId, this.relayKey, this._mine, this._theirs)
      : trustedByMe = ValueNotifier(List.unmodifiable(_mine.values)),
        trustsMe = ValueNotifier(List.unmodifiable(_theirs.values));

  static const _idKey = 'beamx.deviceId';
  static const _relayKeyKey = 'beamx.relayKey';
  static const _passwordKeyKey = 'beamx.passwordKey';
  static const _mineKey = 'beamx.trustedByMe';
  static const _theirsKey = 'beamx.trustedMe';

  final SharedPreferences _prefs;
  final String deviceId;

  /// Proves to internet relay servers that this device owns [deviceId].
  final String relayKey;
  final Map<String, TrustedDevice> _mine;
  final Map<String, TrustedDevice> _theirs;
  final ValueNotifier<List<TrustedDevice>> trustedByMe;

  /// Devices that let this device connect to them without a code.
  final ValueNotifier<List<TrustedDevice>> trustsMe;

  /// A store with a fixed device ID, for running two devices in one test.
  @visibleForTesting
  static Future<TrustStore> forTest(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    return TrustStore._(prefs, deviceId, randomHex(32), {}, {});
  }

  static Future<TrustStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id == null || id.length != 32) {
      id = randomHex(16);
      await prefs.setString(_idKey, id);
    }
    var relayKey = prefs.getString(_relayKeyKey);
    if (relayKey == null || relayKey.length != 64) {
      relayKey = randomHex(32);
      await prefs.setString(_relayKeyKey, relayKey);
    }
    return TrustStore._(
        prefs, id, relayKey, _read(prefs, _mineKey), _read(prefs, _theirsKey));
  }

  static Map<String, TrustedDevice> _read(SharedPreferences p, String key) {
    final out = <String, TrustedDevice>{};
    try {
      final list = jsonDecode(p.getString(key) ?? '[]');
      if (list is List) {
        for (final j in list) {
          final d = TrustedDevice.fromJson(j);
          if (d != null) out[d.id] = d;
        }
      }
    } catch (_) {}
    return out;
  }

  void _save() {
    _prefs.setString(
        _mineKey, jsonEncode([for (final d in _mine.values) d.toJson()]));
    _prefs.setString(
        _theirsKey, jsonEncode([for (final d in _theirs.values) d.toJson()]));
    trustedByMe.value = List.unmodifiable(_mine.values);
    trustsMe.value = List.unmodifiable(_theirs.values);
  }

  /// PBKDF2 key of the owner's access password (never the password itself).
  String? get passwordKey => _prefs.getString(_passwordKeyKey);
  bool get hasPassword => passwordKey != null;

  Future<void> setPasswordKey(String? key) async {
    if (key == null) {
      await _prefs.remove(_passwordKeyKey);
    } else {
      await _prefs.setString(_passwordKeyKey, key);
    }
  }

  /// Key to check when device [id] connects without a code.
  String? secretFor(String id) => _mine[id]?.secret;

  /// Key to use when connecting to device [id] without a code.
  String? keyFor(String id) => _theirs[id]?.secret;

  /// Creates a new key letting [id] connect to me without a code.
  String trust({required String id, required String name, required String platform}) {
    final secret = randomHex(32);
    _mine[id] = TrustedDevice(
        id: id, name: name, platform: platform, secret: secret, added: DateTime.now());
    _save();
    return secret;
  }

  /// Saves a key another device gave me.
  void rememberKey({
    required String id,
    required String name,
    required String platform,
    required String secret,
  }) {
    _theirs[id] = TrustedDevice(
        id: id, name: name, platform: platform, secret: secret, added: DateTime.now());
    _save();
  }

  void untrust(String id) {
    _mine.remove(id);
    _save();
  }

  void forgetKey(String id) {
    _theirs.remove(id);
    _save();
  }

  static String randomHex(int bytes) {
    final r = Random.secure();
    return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
