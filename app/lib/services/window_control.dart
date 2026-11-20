import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Fullscreen and always-on-top for the streaming window.
class WindowControl {
  WindowControl._();

  static bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> init() async {
    if (_desktop) await windowManager.ensureInitialized();
  }

  /// Keeps the BeamX window above other windows (computers only).
  static Future<void> setOnTop(bool onTop) async {
    if (!_desktop) return;
    try {
      await windowManager.setAlwaysOnTop(onTop);
    } catch (_) {}
  }

  static Future<void> setFullScreen(bool full) async {
    try {
      if (_desktop) {
        await windowManager.setFullScreen(full);
      } else {
        // Phones and tablets: hide the status and navigation bars.
        await SystemChrome.setEnabledSystemUIMode(
            full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }
}
