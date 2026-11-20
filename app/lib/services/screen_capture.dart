import 'dart:io' show Platform;

import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Captures this device's screen as a WebRTC media stream.
class ScreenCapture {
  ScreenCapture._();

  /// iOS needs a ReplayKit broadcast extension, which is not built yet.
  static bool get supported => !Platform.isIOS;

  static String get unsupportedReason =>
      'Sharing an iPhone or iPad screen is not available yet. '
      'You can still view other screens from this device.';

  /// Asks the user for permission (where the OS requires it) and starts
  /// capturing the main screen at up to [fps] frames per second.
  static Future<MediaStream> start({required int fps}) async {
    if (!supported) throw UnsupportedError(unsupportedReason);

    if (Platform.isAndroid) {
      // Android 14+ requires: user consent first, then a foreground
      // service of type mediaProjection, then the capture itself.
      final granted = await Helper.requestCapturePermission();
      if (!granted) throw CaptureDenied();
      final ok = await FlutterBackground.initialize(
        androidConfig: const FlutterBackgroundAndroidConfig(
          notificationTitle: 'BeamX is sharing your screen',
          notificationText: 'Open BeamX to stop sharing.',
          notificationImportance: AndroidNotificationImportance.normal,
          notificationIcon:
              AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        ),
      );
      if (ok) await FlutterBackground.enableBackgroundExecution();
      return navigator.mediaDevices
          .getDisplayMedia(<String, dynamic>{'video': true, 'audio': false});
    }

    // Desktop: capture the first (main) screen.
    if (Platform.isMacOS) {
      final granted = await Helper.requestCapturePermission();
      if (!granted) throw CaptureDenied();
    }
    final sources =
        await desktopCapturer.getSources(types: [SourceType.Screen]);
    if (sources.isEmpty) {
      throw StateError('No screen found to share');
    }
    return navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
      'video': {
        'deviceId': {'exact': sources.first.id},
        'mandatory': {'frameRate': fps.toDouble()},
      },
      'audio': false,
    });
  }

  /// Stops the Android foreground service after sharing ends.
  static Future<void> stopService() async {
    if (Platform.isAndroid && FlutterBackground.isBackgroundExecutionEnabled) {
      await FlutterBackground.disableBackgroundExecution();
    }
  }
}

class CaptureDenied implements Exception {
  @override
  String toString() => 'Screen sharing permission was not given';
}
