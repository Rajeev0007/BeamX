import 'package:material_ui/material_ui.dart';

/// Another BeamX device found on the network.
@immutable
class PeerDevice {
  const PeerDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.internetId,
    this.hidden = false,
  });

  final String id;
  final String name;
  final String platform; // windows, macos, linux, android, ios
  final String address;
  final int port;
  final DateTime lastSeen;

  /// Set when connecting through the internet server instead of directly.
  final String? internetId;
  bool get viaInternet => internetId != null;

  /// Found by its exact ID; not shown in the nearby list.
  final bool hidden;

  IconData get icon => switch (platform) {
        'android' => Icons.phone_android_rounded,
        'ios' => Icons.phone_iphone_rounded,
        'macos' => Icons.laptop_mac_rounded,
        'windows' => Icons.desktop_windows_rounded,
        'linux' => Icons.computer_rounded,
        _ => Icons.devices_other_rounded,
      };

  String get platformLabel => switch (platform) {
        'android' => 'Android',
        'ios' => 'iOS',
        'macos' => 'macOS',
        'windows' => 'Windows',
        'linux' => 'Linux',
        _ => 'Unknown',
      };

  /// Seconds since the last announcement, used for the signal indicator.
  int ageSeconds(DateTime now) => now.difference(lastSeen).inSeconds;
}
