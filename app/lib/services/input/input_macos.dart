import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'input_injector.dart';

// CoreGraphics event bindings, written directly with dart:ffi.

final class _CGPoint extends Struct {
  @Double()
  external double x;
  @Double()
  external double y;
}

final class _CGSize extends Struct {
  @Double()
  external double width;
  @Double()
  external double height;
}

final class _CGRect extends Struct {
  external _CGPoint origin;
  external _CGSize size;
}

typedef _MainDisplayC = Uint32 Function();
typedef _MainDisplayDart = int Function();
typedef _BoundsC = _CGRect Function(Uint32);
typedef _BoundsDart = _CGRect Function(int);
typedef _MouseEventC = Pointer<Void> Function(Pointer<Void>, Uint32, _CGPoint, Uint32);
typedef _MouseEventDart = Pointer<Void> Function(Pointer<Void>, int, _CGPoint, int);
typedef _KeyEventC = Pointer<Void> Function(Pointer<Void>, Uint16, Bool);
typedef _KeyEventDart = Pointer<Void> Function(Pointer<Void>, int, bool);
typedef _ScrollC = Pointer<Void> Function(Pointer<Void>, Uint32, Uint32, Int32, Int32, Int32);
typedef _ScrollDart = Pointer<Void> Function(Pointer<Void>, int, int, int, int, int);
typedef _PostC = Void Function(Uint32, Pointer<Void>);
typedef _PostDart = void Function(int, Pointer<Void>);
typedef _SetFlagsC = Void Function(Pointer<Void>, Uint64);
typedef _SetFlagsDart = void Function(Pointer<Void>, int);
typedef _SetIntFieldC = Void Function(Pointer<Void>, Uint32, Int64);
typedef _SetIntFieldDart = void Function(Pointer<Void>, int, int);
typedef _SetUnicodeC = Void Function(Pointer<Void>, UnsignedLong, Pointer<Uint16>);
typedef _SetUnicodeDart = void Function(Pointer<Void>, int, Pointer<Uint16>);
typedef _ReleaseC = Void Function(Pointer<Void>);
typedef _ReleaseDart = void Function(Pointer<Void>);
typedef _TrustedC = Bool Function();
typedef _TrustedDart = bool Function();

const _hidTap = 0;
const _scrollPixel = 0;
const _clickStateField = 1; // kCGMouseEventClickState

// Event types: [down, up, dragged] for left, right, other(middle).
const _types = [
  [1, 2, 6],
  [3, 4, 7],
  [25, 26, 27],
];
const _mouseMoved = 5;

const _flagFor = <String, int>{
  'shift': 0x20000,
  'ctrl': 0x40000,
  'alt': 0x80000,
  'meta': 0x100000,
};

const _keyCodes = <String, int>{
  'enter': 36, 'tab': 48, 'space': 49, 'backspace': 51, 'escape': 53, //
  'delete': 117, 'home': 115, 'end': 119, 'pageup': 116, 'pagedown': 121,
  'left': 123, 'right': 124, 'down': 125, 'up': 126,
  'f1': 122, 'f2': 120, 'f3': 99, 'f4': 118, 'f5': 96, 'f6': 97,
  'f7': 98, 'f8': 100, 'f9': 101, 'f10': 109, 'f11': 103, 'f12': 111,
  'a': 0, 's': 1, 'd': 2, 'f': 3, 'h': 4, 'g': 5, 'z': 6, 'x': 7,
  'c': 8, 'v': 9, 'b': 11, 'q': 12, 'w': 13, 'e': 14, 'r': 15, 'y': 16,
  't': 17, '1': 18, '2': 19, '3': 20, '4': 21, '6': 22, '5': 23, '9': 25,
  '7': 26, '8': 28, '0': 29, 'o': 31, 'u': 32, 'i': 34, 'p': 35, 'l': 37,
  'j': 38, 'k': 40, 'n': 45, 'm': 46,
};

/// Mouse and keyboard control of the main Mac display via CoreGraphics.
/// Requires the Accessibility permission.
class MacInput implements InputInjector {
  static final _cg = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
  static final _cf = DynamicLibrary.open(
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
  static final _as = DynamicLibrary.open(
      '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices');

  late final _mainDisplay =
      _cg.lookupFunction<_MainDisplayC, _MainDisplayDart>('CGMainDisplayID');
  late final _bounds =
      _cg.lookupFunction<_BoundsC, _BoundsDart>('CGDisplayBounds');
  late final _mouseEvent =
      _cg.lookupFunction<_MouseEventC, _MouseEventDart>('CGEventCreateMouseEvent');
  late final _keyEvent =
      _cg.lookupFunction<_KeyEventC, _KeyEventDart>('CGEventCreateKeyboardEvent');
  late final _scroll = _cg
      .lookupFunction<_ScrollC, _ScrollDart>('CGEventCreateScrollWheelEvent2');
  late final _post = _cg.lookupFunction<_PostC, _PostDart>('CGEventPost');
  late final _setFlags =
      _cg.lookupFunction<_SetFlagsC, _SetFlagsDart>('CGEventSetFlags');
  late final _setInt = _cg.lookupFunction<_SetIntFieldC, _SetIntFieldDart>(
      'CGEventSetIntegerValueField');
  late final _setUnicode = _cg.lookupFunction<_SetUnicodeC, _SetUnicodeDart>(
      'CGEventKeyboardSetUnicodeString');
  late final _release = _cf.lookupFunction<_ReleaseC, _ReleaseDart>('CFRelease');
  late final _trusted =
      _as.lookupFunction<_TrustedC, _TrustedDart>('AXIsProcessTrusted');

  int _flags = 0;
  final Set<int> _held = {};
  double _x = 0, _y = 0;
  DateTime _lastClick = DateTime(2000);
  int _clicks = 0;

  @override
  Future<bool> isReady() async => _trusted();

  @override
  String get permissionHelp =>
      'Allow BeamX in System Settings → Privacy & Security → Accessibility, '
      'then turn remote control off and on again.';

  @override
  Future<void> openPermissionSettings() async {
    await Process.run('open', [
      'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    ]);
  }

  /// Converts 0–1 coordinates to global display points.
  void _toScreen(double x, double y) {
    final b = _bounds(_mainDisplay());
    _x = b.origin.x + x * b.size.width;
    _y = b.origin.y + y * b.size.height;
  }

  void _postMouse(int type, int button, {int clicks = 0}) {
    final p = calloc<_CGPoint>();
    try {
      p.ref
        ..x = _x
        ..y = _y;
      final e = _mouseEvent(nullptr, type, p.ref, button);
      if (e == nullptr) return;
      if (clicks > 0) _setInt(e, _clickStateField, clicks);
      _setFlags(e, _flags);
      _post(_hidTap, e);
      _release(e);
    } finally {
      calloc.free(p);
    }
  }

  void _postKey(int code, bool down) {
    final e = _keyEvent(nullptr, code, down);
    if (e == nullptr) return;
    _setFlags(e, _flags);
    _post(_hidTap, e);
    _release(e);
  }

  void _postText(String s) {
    final units = s.codeUnits;
    final buf = calloc<Uint16>(units.length);
    try {
      for (var i = 0; i < units.length; i++) {
        buf[i] = units[i];
      }
      for (final down in [true, false]) {
        final e = _keyEvent(nullptr, 0, down);
        if (e == nullptr) continue;
        _setUnicode(e, units.length, buf);
        _post(_hidTap, e);
        _release(e);
      }
    } finally {
      calloc.free(buf);
    }
  }

  @override
  Future<void> handle(RemoteInput input) async {
    switch (input) {
      case PointerMove(:final x, :final y):
        _toScreen(x, y);
        final b = _held.isEmpty ? null : _held.first;
        _postMouse(b == null ? _mouseMoved : _types[b][2], b ?? 0);
      case PointerButton(:final x, :final y, :final button, :final down):
        _toScreen(x, y);
        if (down) {
          final now = DateTime.now();
          _clicks = now.difference(_lastClick).inMilliseconds < 400 ? _clicks + 1 : 1;
          _lastClick = now;
          _held.add(button);
        } else {
          _held.remove(button);
        }
        _postMouse(_types[button][down ? 0 : 1], button, clicks: _clicks);
      case Wheel(:final dx, :final dy):
        final e = _scroll(nullptr, _scrollPixel, 2, -dy.round(), -dx.round(), 0);
        if (e != nullptr) {
          _post(_hidTap, e);
          _release(e);
        }
      case KeyPress(:final key, :final down) when mediaKeyNames.contains(key):
        if (down) await _media(key);
      case KeyPress(:final key, :final down):
        final flag = _flagFor[key];
        if (flag != null) {
          _flags = down ? _flags | flag : _flags & ~flag;
          return;
        }
        final code = _keyCodes[key];
        if (code != null) _postKey(code, down);
      case TypeText(:final text):
        final parts = text.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) _postText(parts[i]);
          if (i < parts.length - 1) {
            _postKey(36, true);
            _postKey(36, false);
          }
        }
      case NavAction():
        break;
    }
  }

  /// Volume through AppleScript. Play/pause/next/previous go to Music,
  /// Spotify or whichever of them is running.
  Future<void> _media(String key) async {
    const players = ['Spotify', 'Music'];
    String player(String cmd) => [
          for (final p in players)
            'if application "$p" is running then tell application "$p" to $cmd'
        ].join('\n');
    final script = switch (key) {
      'vol_up' => 'set volume output volume ((output volume of (get volume settings)) + 6)',
      'vol_down' => 'set volume output volume ((output volume of (get volume settings)) - 6)',
      'vol_mute' => 'set volume output muted (not (output muted of (get volume settings)))',
      'media_play' => player('playpause'),
      'media_next' => player('next track'),
      'media_prev' => player('previous track'),
      _ => null,
    };
    if (script != null) await Process.run('osascript', ['-e', script]);
  }

  @override
  Future<void> reset() async {
    for (final b in _held.toList()) {
      _postMouse(_types[b][1], b);
    }
    _held.clear();
    _flags = 0;
  }
}
