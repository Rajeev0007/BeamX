import 'package:flutter/services.dart';

import 'input_injector.dart';

/// Touch and text control of an Android phone through BeamX's accessibility
/// service (native code in app/native/android).
///
/// A pointer down → moves → up sequence becomes one gesture, so taps,
/// long presses and swipes all work. The gesture plays when the finger or
/// mouse button is released.
class AndroidInput implements InputInjector {
  static const _ch = MethodChannel('beamx/input');

  final List<double> _points = [];
  DateTime? _downAt;

  @override
  Future<bool> isReady() async {
    try {
      return await _ch.invokeMethod<bool>('isEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  String get permissionHelp =>
      'Turn on BeamX in Settings → Accessibility → Installed apps (or '
      'Downloaded apps). If Android says it\'s a restricted setting, open '
      'Settings → Apps → BeamX → ⋮ → Allow restricted settings first.';

  @override
  Future<void> openPermissionSettings() async {
    try {
      await _ch.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  @override
  Future<void> handle(RemoteInput input) async {
    try {
      switch (input) {
        case PointerButton(:final x, :final y, :final down) when down:
          _points
            ..clear()
            ..addAll([x, y]);
          _downAt = DateTime.now();
        case PointerMove(:final x, :final y) when _downAt != null:
          final n = _points.length;
          final moved = n < 2 ||
              (x - _points[n - 2]).abs() > 0.002 ||
              (y - _points[n - 1]).abs() > 0.002;
          if (moved && _points.length < 2000) _points.addAll([x, y]);
        case PointerButton(:final x, :final y) :
          final start = _downAt;
          if (start == null) break;
          _downAt = null;
          if (_points.length >= 2) _points.addAll([x, y]);
          final ms = DateTime.now().difference(start).inMilliseconds.clamp(1, 59000);
          await _ch.invokeMethod<bool>(
              'gesture', {'points': List<double>.of(_points), 'duration': ms});
          _points.clear();
        case TypeText(:final text):
          await _ch.invokeMethod<bool>('text', {'text': text});
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

  @override
  Future<void> reset() async {
    _points.clear();
    _downAt = null;
  }
}
