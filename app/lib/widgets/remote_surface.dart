import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../services/data_link.dart';

/// Keys sent by name. Printable characters are sent as text instead.
final _keyNames = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  LogicalKeyboardKey.shiftLeft: 'shift',
  LogicalKeyboardKey.shiftRight: 'shift',
  LogicalKeyboardKey.controlLeft: 'ctrl',
  LogicalKeyboardKey.controlRight: 'ctrl',
  LogicalKeyboardKey.altLeft: 'alt',
  LogicalKeyboardKey.altRight: 'alt',
  LogicalKeyboardKey.metaLeft: 'meta',
  LogicalKeyboardKey.metaRight: 'meta',
  LogicalKeyboardKey.f1: 'f1',
  LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3',
  LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7',
  LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9',
  LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11',
  LogicalKeyboardKey.f12: 'f12',
};

const _modifierNames = {'shift', 'ctrl', 'alt', 'meta'};

/// Letter or digit name for shortcuts like Ctrl+C, or null.
String? _shortcutName(LogicalKeyboardKey k) {
  final label = k.keyLabel.toLowerCase();
  if (label.length == 1 && RegExp(r'[a-z0-9]').hasMatch(label)) return label;
  return null;
}

/// Sends mouse, touch and keyboard input on the video to the sharing device.
class RemoteSurface extends StatefulWidget {
  const RemoteSurface({
    super.key,
    required this.renderer,
    required this.link,
    required this.child,
    this.scrollSpeed = 1.0,
  });

  /// Multiplies scroll distances (Settings → Scroll speed).
  final double scrollSpeed;

  final RTCVideoRenderer renderer;
  final DataLink link;
  final Widget child;

  @override
  State<RemoteSurface> createState() => _RemoteSurfaceState();
}

class _RemoteSurfaceState extends State<RemoteSurface> {
  final _focus = FocusNode(debugLabel: 'remote-control');
  final Map<int, int> _buttonForPointer = {};
  final Set<String> _keysDown = {};
  DateTime _lastMove = DateTime(2000);
  Size _size = Size.zero;

  @override
  void dispose() {
    // Release anything still held on the other device.
    for (final k in _keysDown) {
      widget.link.sendInput({'e': 'key', 'k': k, 'd': false});
    }
    _focus.dispose();
    super.dispose();
  }

  /// Maps a point in this widget to 0–1 across the video picture, which is
  /// letterboxed to fit (contain).
  Offset? _norm(Offset p, {bool strict = false}) {
    final vw = widget.renderer.videoWidth.toDouble();
    final vh = widget.renderer.videoHeight.toDouble();
    if (vw <= 0 || vh <= 0 || _size.isEmpty) return null;
    final scale = math.min(_size.width / vw, _size.height / vh);
    final w = vw * scale, h = vh * scale;
    final nx = (p.dx - (_size.width - w) / 2) / w;
    final ny = (p.dy - (_size.height - h) / 2) / h;
    if (strict && (nx < 0 || nx > 1 || ny < 0 || ny > 1)) return null;
    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  void _send(Map<String, Object> e) => widget.link.sendInput(e);

  void _onDown(PointerDownEvent e) {
    _focus.requestFocus();
    final p = _norm(e.localPosition, strict: true);
    if (p == null) return;
    final b = (e.buttons & kSecondaryMouseButton) != 0
        ? 1
        : (e.buttons & kMiddleMouseButton) != 0
            ? 2
            : 0;
    _buttonForPointer[e.pointer] = b;
    _send({'e': 'down', 'b': b, 'x': p.dx, 'y': p.dy});
  }

  void _onMove(PointerEvent e) {
    final now = DateTime.now();
    if (now.difference(_lastMove).inMilliseconds < 16) return; // ~60/s
    _lastMove = now;
    final p = _norm(e.localPosition);
    if (p != null) _send({'e': 'move', 'x': p.dx, 'y': p.dy});
  }

  void _onUp(PointerEvent e) {
    final b = _buttonForPointer.remove(e.pointer);
    if (b == null) return;
    final p = _norm(e.localPosition);
    if (p != null) _send({'e': 'up', 'b': b, 'x': p.dx, 'y': p.dy});
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final k = widget.scrollSpeed;
      _send({'e': 'wheel', 'dx': e.scrollDelta.dx * k, 'dy': e.scrollDelta.dy * k});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final named = _keyNames[e.logicalKey];
    final hw = HardwareKeyboard.instance;
    final shortcut =
        hw.isControlPressed || hw.isAltPressed || hw.isMetaPressed;

    if (e is KeyUpEvent) {
      final name = named ?? _shortcutName(e.logicalKey);
      if (name != null && _keysDown.remove(name)) {
        _send({'e': 'key', 'k': name, 'd': false});
      }
      return KeyEventResult.handled;
    }

    // Key down or repeat.
    final char = e.character;
    if (named == null && !shortcut && char != null && char.isNotEmpty &&
        char.codeUnitAt(0) >= 0x20) {
      _send({'e': 'text', 's': char});
      return KeyEventResult.handled;
    }
    final name = named ?? _shortcutName(e.logicalKey);
    if (name == null) return KeyEventResult.handled;
    if (e is KeyRepeatEvent && _modifierNames.contains(name)) {
      return KeyEventResult.handled;
    }
    _keysDown.add(name);
    _send({'e': 'key', 'k': name, 'd': true});
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onDown,
          onPointerMove: _onMove,
          onPointerHover: _onMove,
          onPointerUp: _onUp,
          onPointerCancel: _onUp,
          onPointerSignal: _onSignal,
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            child: widget.child,
          ),
        ),
      );
    });
  }
}

/// A small keyboard for phones and tablets, which have no physical keys.
Future<void> showRemoteKeyboard(BuildContext context, DataLink link) {
  final controller = TextEditingController();
  void key(String k) {
    link.sendInput({'e': 'key', 'k': k, 'd': true});
    link.sendInput({'e': 'key', 'k': k, 'd': false});
  }

  void sendText() {
    final t = controller.text;
    if (t.isNotEmpty) link.sendInput({'e': 'text', 's': t});
    controller.clear();
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) {
              sendText();
              key('enter');
            },
            decoration: InputDecoration(
              hintText: 'Type here, then tap Send',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: IconButton(
                tooltip: 'Send',
                icon: const Icon(Icons.send_rounded),
                onPressed: sendText,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, k) in const [
                ('⌫ Backspace', 'backspace'),
                ('↵ Enter', 'enter'),
                ('Tab', 'tab'),
                ('Esc', 'escape'),
                ('←', 'left'),
                ('→', 'right'),
                ('↑', 'up'),
                ('↓', 'down'),
              ])
                ActionChip(label: Text(label), onPressed: () => key(k)),
            ],
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}
