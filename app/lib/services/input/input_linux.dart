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
class Lin