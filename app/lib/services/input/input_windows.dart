import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'input_injector.dart';

// Win32 SendInput bindings (user32.dll), written directly with dart:ffi.

final class _MouseInput extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class _KeybdInput extends Struct {
  @Uint16()
  external int wVk;
  @Uint16()
  external int wScan;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int time;
  @IntPtr()
  external int dwExtraInfo;
}

final class _InputUnion extends Union {
  external _MouseInput mi;
  external _KeybdInput ki;
}

final class _Input extends Struct {
  @Uint32()
  external int type;
  external _InputUnion u;
}

typedef _SendInputC = Uint32 Function(Uint32, Pointer<_Input>, Int32);
typedef _SendInputDart = int Function(int, Pointer<_Input>, int);

const _inputMouse = 0;
const _inputKeyboard = 1;
const _move = 0x0001;
const _absolute = 0x8000;
const _wheel = 0x0800;
const _hwheel = 0x1000;
const _btnDown = [0x0002, 0x0008, 0x0020]; // left, right, middle
const _btnUp = [0x0004, 0x0010, 0x0040];
const _keyUp = 0x0002;
const _unicode = 0x0004;
const _extended = 0x0001;

const _vk = <String, int>{
  'backspace': 0x08, 'tab': 0x09, 'enter': 0x0D, 'shift': 0x10, //
  'ctrl': 0x11, 'alt': 0x12, 'escape': 0x1B, 'space': 0x20,
  'pageup': 0x21, 'pagedown': 0x22, 'end': 0x23, 'home': 0x24,
  'left': 0x25, 'up': 0x26, 'right': 0x27, 'down': 0x28,
  'delete': 0x2E, 'meta': 0x5B,
  'media_play': 0xB3, 'media_next': 0xB0, 'media_prev': 0xB1,
  'vol_mute': 0xAD, 'vol_down': 0xAE, 'vol_up': 0xAF,
};

const _extendedKeys = {
  'pageup', 'pagedown', 'end', 'home', 'left', 'up', 'right', 'down', //
  'delete', 'meta', 'media_play', 'media_next', 'media_prev', 'vol_mute',
  'vol_down', 'vol_up',
};

int? _vkFor(String key) {
  final v = _vk[key];
  if (v != null) return v;
  if (key.length == 1) {
    final c = key.codeUnitAt(0);
    if (c >= 0x61 && c <= 0x7A) return c - 0x20; // a-z → VK_A..VK_Z
    if (c >= 0x30 && c <= 0x39) return c; // 0-9
  }
  if (key.startsWith('f')) {
    final n = int.tryParse(key.substring(1));
    if (n != null && n >= 1 && n <= 12) return 0x70 + n - 1;
  }
  return null;
}

/// Mouse and keyboard control of the main Windows screen via SendInput.
///
/// Windows blocks input into apps running as administrator unless BeamX
/// also runs as administrator.
class WindowsInput implements InputInjector {
  late final _SendInputDart _send = DynamicLibrary.open('user32.dll')
      .lookupFunction<_SendInputC, _SendInputDart>('SendInput');
  final Set<int> _heldKeys = {};
  final Set<int> _heldButtons = {};

  @override
  Future<bool> isReady() async => true;

  @override
  String get permissionHelp => '';

  @override
  Future<void> openPermissionSettings() async {}

  void _mouse(int flags, {int dx = 0, int dy = 0, int data = 0}) {
    final p = calloc<_Input>();
    try {
      p.ref.type = _inputMouse;
      p.ref.u.mi
        ..dx = dx
        ..dy = dy
        ..mouseData = data
        ..dwFlags = flags;
      _send(1, p, sizeOf<_Input>());
    } finally {
      calloc.free(p);
    }
  }

  void _key({int vk = 0, int scan = 0, required int flags}) {
    final p = calloc<_Input>();
    try {
      p.ref.type = _inputKeyboard;
      p.ref.u.ki
        ..wVk = vk
        ..wScan = scan
        ..dwFlags = flags;
      _send(1, p, sizeOf<_Input>());
    } finally {
      calloc.free(p);
    }
  }

  void _moveTo(double x, double y) => _mouse(_move | _absolute,
      dx: (x * 65535).round(), dy: (y * 65535).round());

  @override
  Future<void> handle(RemoteInput input) async {
    switch (input) {
      case PointerMove(:final x, :final y):
        _moveTo(x, y);
      case PointerButton(:final x, :final y, :final button, :final down):
        _moveTo(x, y);
        _mouse(down ? _btnDown[button] : _btnUp[button]);
        down ? _heldButtons.add(button) : _heldButtons.remove(button);
      case Wheel(:final dx, :final dy):
        // Flutter reports pixels (positive = down/right); Windows wants
        // multiples of 120 (positive = up/right).
        if (dy != 0) _mouse(_wheel, data: (-dy * 1.2).round() & 0xFFFFFFFF);
        if (dx != 0) _mouse(_hwheel, data: (dx * 1.2).round() & 0xFFFFFFFF);
      case KeyPress(:final key, :final down):
        final vk = _vkFor(key);
        if (vk == null) return;
        final ext = _extendedKeys.contains(key) ? _extended : 0;
        _key(vk: vk, flags: ext | (down ? 0 : _keyUp));
        down ? _heldKeys.add(vk) : _heldKeys.remove(vk);
      case TypeText(:final text):
        for (final unit in text.codeUnits) {
          if (unit == 0x0A) {
            _key(vk: 0x0D, flags: 0);
            _key(vk: 0x0D, flags: _keyUp);
            continue;
          }
          _key(scan: unit, flags: _unicode);
          _key(scan: unit, flags: _unicode | _keyUp);
        }
      case NavAction():
        break;
    }
  }

  @override
  Future<void> reset() async {
    for (final b in _heldButtons) {
      _mouse(_btnUp[b]);
    }
    _heldButtons.clear();
    for (final vk in _heldKeys) {
      _key(vk: vk, flags: _keyUp);
    }
    _heldKeys.clear();
  }
}
