import 'package:flutter/services.dart';

import 'input_injector.dart';

/// Touch, text and media control of an Android phone through BeamX's
/// accessibility service (native code in app/native/android).
///
/// On Android 8 and newer the finger follows the remote pointer live
/// (continued strokes), so drags and swipes respond immediately.
class AndroidInput implements InputInjector {
  static const _ch = MethodChannel('beamx/input');

  bool _down = false;
  DateTime _lastMove = DateTime(2000);
  bool? _controlEdition;

  @override
  Future<bool> isReady() async {
    try {
      _controlEdition ??=
          await _ch.invokeMethod<bool>('isControlEdition') ?? false;
      if (_controlEdition == false) return false;
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  String get permissionHelp => _controlEdition == false
      ? 'This BeamX edition can\'t be controlled remotely (it installs '
          'without Play Protect blocks). For remote control of this phone, '
          'install "BeamX Control" from the Releases page.'
      : 'Turn on BeamX in Settings → Accessibility → Installed apps (or '
          'Downloaded apps). If Android says it\'s a restricted setting, open '
          'Settings → Apps → BeamX → ⋮ → Allow restricted settings first.';

  @override
  Future<void> openPermissionSettings() async {
    if (_controlEdition == false) {
      try {
        await _ch.invokeMethod<void>('openReleases');
      } catch (_) {}
      return;
    }
    try {
      await _ch.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  Future<void> _touch(String method, double x, double y) =>
      _ch.invokeMethod<bool>(method, {'x': x, 'y': y});

  @override
  Future<void> handle(RemoteInput input) async {
    try {
      switch (input) {
        case PointerButton(:final x, :final y, :final down) when down:
          _down = true;
          await _touch('touchDown', x, y);
        case PointerMove(:final x, :final y) when _down:
          final now = DateTime.now();
          if (now.difference(_lastMove).inMilliseconds < 12) break;
          _lastMove = now;
          await _touch('touchMove', x, y);
        case PointerButton(:final x, :final y) when _down:
          _down = false;
          await _touch('touchUp', x, y);
        case TypeText(:final text):
          await _ch.invokeMethod<bool>('text', {'text': text});
        case KeyPress(:final key, :final down) when down && mediaKeyNames.contains(key):
          await _ch.invokeMethod<bool>('media', {'key': key});
        case KeyPress(:final key, :final down) when down:
          if (key == 'backspace' || key == 'enter') {
            await _ch.invokeMethod<bool>('key', {'key': key});
          }
        case NavAction(:final action):
          await _ch.invokeMethod<bool>('global', {'action': action});
        default:
          break;
      }
    } on PlatformException catch (_) {
      // The service was turned off; the sharer UI shows how to re-enable it.
    }
  }

  /// Lifts a held finger where it is (no swipe to the centre).
  @override
  Future<void> reset() async {
    if (!_down) return;
    _down = false;
    try {
      await _ch.invokeMethod<bool>('touchCancel');
    } catch (_) {}
  }
}
