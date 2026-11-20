import 'dart:io' show Platform;

import 'input_android.dart';
import 'input_linux.dart';
import 'input_macos.dart';
import 'input_windows.dart';

/// Keys the viewer may press. Anything else is ignored by the sharer.
const remoteKeyNames = <String>{
  'enter', 'tab', 'backspace', 'delete', 'escape', 'space', //
  'left', 'right', 'up', 'down', 'home', 'end', 'pageup', 'pagedown',
  'shift', 'ctrl', 'alt', 'meta',
  'f1', 'f2', 'f3', 'f4', 'f5', 'f6', 'f7', 'f8', 'f9', 'f10', 'f11', 'f12',
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', //
  'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
  // Media remote
  'media_play', 'media_next', 'media_prev', 'vol_up', 'vol_down', 'vol_mute',
};

/// Media keys, sent as a press (down + up) by the media remote.
const mediaKeyNames = <String>{
  'media_play', 'media_next', 'media_prev', 'vol_up', 'vol_down', 'vol_mute',
};

/// A validated input event from the viewing device.
/// Coordinates are 0–1 across the shared screen.
sealed class RemoteInput {
  const RemoteInput();

  /// Parses untrusted input. Returns null if invalid.
  static RemoteInput? parse(Map<dynamic, dynamic> m) {
    double? c(Object? v) =>
        v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : null;
    final x = c(m['x']), y = c(m['y']);
    switch (m['e']) {
      case 'move' when x != null && y != null:
        return PointerMove(x, y);
      case 'down' || 'up' when x != null && y != null:
        final b = m['b'];
        if (b is! int || b < 0 || b > 2) return null;
        return PointerButton(x, y, b, m['e'] == 'down');
      case 'wheel':
        final dx = m['dx'], dy = m['dy'];
        if (dx is! num || dy is! num) return null;
        return Wheel(dx.toDouble().clamp(-2000, 2000), dy.toDouble().clamp(-2000, 2000));
      case 'key':
        final k = m['k'], d = m['d'];
        if (k is! String || !remoteKeyNames.contains(k) || d is! bool) return null;
        return KeyPress(k, d);
      case 'text':
        final s = m['s'];
        if (s is! String || s.isEmpty || s.length > 1000) return null;
        return TypeText(s);
      case 'nav':
        final a = m['a'];
        if (a is! String || !const {'back', 'home', 'recents'}.contains(a)) return null;
        return NavAction(a);
    }
    return null;
  }
}

class PointerMove extends RemoteInput {
  const PointerMove(this.x, this.y);
  final double x, y;
}

class PointerButton extends RemoteInput {
  const PointerButton(this.x, this.y, this.button, this.down);
  final double x, y;

  /// 0 = left/touch, 1 = right, 2 = middle.
  final int button;
  final bool down;
}

class Wheel extends RemoteInput {
  const Wheel(this.dx, this.dy);

  /// Scroll distance in logical pixels, as reported by the viewer.
  final double dx, dy;
}

class KeyPress extends RemoteInput {
  const KeyPress(this.key, this.down);
  final String key;
  final bool down;
}

class TypeText extends RemoteInput {
  const TypeText(this.text);
  final String text;
}

/// Android navigation buttons.
class NavAction extends RemoteInput {
  const NavAction(this.action);
  final String action;
}

/// Performs mouse, keyboard and touch input on this device.
abstract class InputInjector {
  /// The injector for this platform, or null where remote control of this
  /// device isn't possible (iOS).
  static InputInjector? create() {
    if (Platform.isWindows) return WindowsInput();
    if (Platform.isMacOS) return MacInput();
    if (Platform.isLinux) return LinuxInput();
    if (Platform.isAndroid) return AndroidInput();
    return null;
  }

  /// True if the OS currently lets BeamX control this device.
  Future<bool> isReady();

  /// What the user must do to allow control, shown when [isReady] is false.
  String get permissionHelp;

  /// Opens the system setting where the user can allow control.
  Future<void> openPermissionSettings();

  Future<void> handle(RemoteInput input);

  /// Releases held buttons and keys, e.g. when control is turned off.
  Future<void> reset();
}
