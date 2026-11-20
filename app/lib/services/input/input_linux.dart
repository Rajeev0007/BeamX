import 'dart:ffi';
import 'dart:io';

import 'input_injector.dart';

// X11 + XTest bindings, written directly with dart:ffi.

typedef _OpenC = Pointer<Void> Function(Pointer<Void>);
typedef _OpenDart = Pointer<Void> Function(Pointer<Void>);
typedef _ScreenC = Int32 Function(Pointer<Void>);
typedef _ScreenDart = int Function(Pointer<Void>);
typedef _SizeC = Int32 Function(Pointer<Void>, Int32);
typedef _SizeDart = int Function(Pointer<Void>, int);
typedef _MotionC = Int32 Function(Pointer<Void>, Int32, Int32, Int32, UnsignedLong);
typedef _MotionDart = int Function(Pointer<Void>, int, int, int, int);
typedef _FakeC = Int32 Function(Pointer<Void>, Uint32, Int32, UnsignedLong);
typedef _FakeDart = int Function(Pointer<Void>, int, int, int);
typedef _KeysymC = Uint8 Function(Pointer<Void>, UnsignedLong);
typedef _KeysymDart = int Function(Pointer<Void>, int);
typedef _FlushC = Int32 Function(Pointer<Void>);
typedef _FlushDart = int Function(Pointer<Void>);

const _keysyms = <String, int>{
  'enter': 0xff0d, 'tab': 0xff09, 'backspace': 0xff08, 'escape': 0xff1b, //
  'delete': 0xffff, 'home': 0xff50, 'left': 0xff51, 'up': 0xff52,
  'right': 0xff53, 'down': 0xff54, 'pageup': 0xff55, 'pagedown': 0xff56,
  'end': 0xff57, 'shift': 0xffe1, 'ctrl': 0xffe3, 'alt': 0xffe9,
  'meta': 0xffeb, 'space': 0x20,
};

// X buttons: 1 left, 2 middle, 3 right.
const _buttons = [1, 3, 2];
const _shiftedSymbols = '~!@#\$%^&*()_+{}|:"<>?';

/// Mouse and keyboard control of the X11 screen via the XTest extension.
/// Wayland sessions are not supported.
class LinuxInput implements InputInjector {
  DynamicLibrary? _x11;
  DynamicLibrary? _xtst;
  Pointer<Void> _dpy = nullptr;
  int _screen = 0;

  late _MotionDart _motion;
  late _FakeDart _button;
  late _FakeDart _key;
  late _KeysymDart _keysymToKeycode;
  late _FlushDart _flush;
  late _SizeDart _width;
  late _SizeDart _height;

  final Set<int> _heldButtons = {};
  final Set<int> _heldKeys = {};

  bool _open() {
    if (_dpy != nullptr) return true;
    try {
      final x11 = _x11 ??= DynamicLibrary.open('libX11.so.6');
      final xtst = _xtst ??= DynamicLibrary.open('libXtst.so.6');
      final dpy = x11.lookupFunction<_OpenC, _OpenDart>('XOpenDisplay')(nullptr);
      if (dpy == nullptr) return false;
      _screen = x11.lookupFunction<_ScreenC, _ScreenDart>('XDefaultScreen')(dpy);
      _width = x11.lookupFunction<_SizeC, _SizeDart>('XDisplayWidth');
      _height = x11.lookupFunction<_SizeC, _SizeDart>('XDisplayHeight');
      _keysymToKeycode =
          x11.lookupFunction<_KeysymC, _KeysymDart>('XKeysymToKeycode');
      _flush = x11.lookupFunction<_FlushC, _FlushDart>('XFlush');
      _motion = xtst.lookupFunction<_MotionC, _MotionDart>('XTestFakeMotionEvent');
      _button = xtst.lookupFunction<_FakeC, _FakeDart>('XTestFakeButtonEvent');
      _key = xtst.lookupFunction<_FakeC, _FakeDart>('XTestFakeKeyEvent');
      _dpy = dpy;
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool get _isWayland =>
      (Platform.environment['XDG_SESSION_TYPE'] ?? '').toLowerCase() == 'wayland';

  @override
  Future<bool> isReady() async => !_isWayland && _open();

  @override
  String get permissionHelp => _isWayland
      ? 'Remote control needs an X11 session. Log out and choose '
          '"Ubuntu on Xorg" (or your desktop\'s X11 option) at the login screen.'
      : 'Install the XTest library: sudo apt install libxtst6';

  @override
  Future<void> openPermissionSettings() async {}

  void _moveTo(double x, double y) {
    final w = _width(_dpy, _screen), h = _height(_dpy, _screen);
    _motion(_dpy, _screen, (x * (w - 1)).round(), (y * (h - 1)).round(), 0);
  }

  void _tapKeysym(int keysym, {bool shift = false}) {
    final code = _keysymToKeycode(_dpy, keysym);
    if (code == 0) return;
    final shiftCode = _keysymToKeycode(_dpy, 0xffe1);
    if (shift) _key(_dpy, shiftCode, 1, 0);
    _key(_dpy, code, 1, 0);
    _key(_dpy, code, 0, 0);
    if (shift) _key(_dpy, shiftCode, 0, 0);
  }

  int? _keysymFor(String key) {
    final k = _keysyms[key];
    if (k != null) return k;
    if (key.length == 1) return key.codeUnitAt(0); // a-z, 0-9 = ASCII
    if (key.startsWith('f')) {
      final n = int.tryParse(key.substring(1));
      if (n != null && n >= 1 && n <= 12) return 0xffbe + n - 1;
    }
    return null;
  }

  @override
  Future<void> handle(RemoteInput input) async {
    if (!_open()) return;
    switch (input) {
      case PointerMove(:final x, :final y):
        _moveTo(x, y);
      case PointerButton(:final x, :final y, :final button, :final down):
        _moveTo(x, y);
        _button(_dpy, _buttons[button], down ? 1 : 0, 0);
        down ? _heldButtons.add(_buttons[button]) : _heldButtons.remove(_buttons[button]);
      case Wheel(:final dx, :final dy):
        // One wheel "click" per ~50 px; buttons 4/5 = up/down, 6/7 = left/right.
        void clicks(double d, int neg, int pos) {
          final n = (d.abs() / 50).ceil().clamp(0, 20);
          for (var i = 0; i < n; i++) {
            _button(_dpy, d < 0 ? neg : pos, 1, 0);
            _button(_dpy, d < 0 ? neg : pos, 0, 0);
          }
        }
        if (dy != 0) clicks(dy, 4, 5);
        if (dx != 0) clicks(dx, 6, 7);
      case KeyPress(:final key, :final down):
        final sym = _keysymFor(key);
        if (sym == null) break;
        final code = _keysymToKeycode(_dpy, sym);
        if (code == 0) break;
        _key(_dpy, code, down ? 1 : 0, 0);
        down ? _heldKeys.add(code) : _heldKeys.remove(code);
      case TypeText(:final text):
        for (final r in text.runes) {
          if (r == 0x0A) {
            _tapKeysym(0xff0d);
            continue;
          }
          final ch = String.fromCharCode(r);
          final upper = ch != ch.toLowerCase();
          final shift = upper || _shiftedSymbols.contains(ch);
          // Latin-1 keysyms equal the code point; others use 0x01000000 + code.
          final sym = r < 0x100 ? (upper ? ch.toLowerCase().codeUnitAt(0) : r) : 0x01000000 + r;
          _tapKeysym(sym, shift: shift);
        }
      case NavAction():
        break;
    }
    _flush(_dpy);
  }

  @override
  Future<void> reset() async {
    if (_dpy == nullptr) return;
    for (final b in _heldButtons) {
      _button(_dpy, b, 0, 0);
    }
    for (final k in _heldKeys) {
      _key(_dpy, k, 0, 0);
    }
    _heldButtons.clear();
    _heldKeys.clear();
    _flush(_dpy);
  }
}