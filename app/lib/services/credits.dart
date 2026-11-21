import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Credits shown in the footer and About screen. Under the additional terms
/// in NOTICE (GPL-3.0 section 7), copies of BeamX must keep this credit.
class Credits {
  Credits._();

  static const developer = 'Rajeev Development';
  static const copyright = '© 2026 Rajeev Development';
  static const repo = 'https://github.com/Rajeev0007/BeamX';
  static const version =
      String.fromEnvironment('BEAMX_VERSION', defaultValue: 'dev');

  /// SHA-1 of Rajeev Development's Android signing certificate (public).
  static const _officialAndroidCert = '31178dde1a8ccd30d683ad5d0ff28cb0ff417386';

  static OfficialStatus? _status;

  /// Whether this copy is an official release, signed by Rajeev
  /// Development. Copies built and signed by anyone else are "unofficial".
  static Future<OfficialStatus> status() async {
    if (_status != null) return _status!;
    var result = OfficialStatus.unknown;
    if (Platform.isAndroid) {
      try {
        final sha1 = await const MethodChannel('beamx/input')
            .invokeMethod<String>('signingSha1');
        result = sha1 == _officialAndroidCert
            ? OfficialStatus.official
            : OfficialStatus.unofficial;
      } catch (_) {}
    }
    return _status = result;
  }
}

enum OfficialStatus {
  official,
  unofficial,

  /// The platform can't check its own signature (Windows, macOS, Linux,
  /// iOS): verify the download's checksum instead.
  unknown,
}
