import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/data_link.dart';

void _press(DataLink link, String key) {
  HapticFeedback.selectionClick();
  link.sendInput({'e': 'key', 'k': key, 'd': true});
  link.sendInput({'e': 'key', 'k': key, 'd': false});
}

/// Play/pause, tracks, volume and slide buttons for the controlled device.
Future<void> showMediaRemote(BuildContext context, DataLink link) {
  Widget btn(IconData icon, String label, String key, {bool big = false}) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            iconSize: big ? 40 : 28,
            padding: EdgeInsets.all(big ? 18 : 12),
            onPressed: () => _press(link, key),
            icon: Icon(icon),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Media remote', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              btn(Icons.skip_previous_rounded, 'Previous', 'media_prev'),
              btn(Icons.play_arrow_rounded, 'Play / pause', 'media_play', big: true),
              btn(Icons.skip_next_rounded, 'Next', 'media_next'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              btn(Icons.volume_down_rounded, 'Volume −', 'vol_down'),
              btn(Icons.volume_off_rounded, 'Mute', 'vol_mute'),
              btn(Icons.volume_up_rounded, 'Volume +', 'vol_up'),
            ],
          ),
          const Divider(height: 32),
          Text('Slides', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              btn(Icons.chevron_left_rounded, 'Back', 'left', big: true),
              btn(Icons.slideshow_rounded, 'Start (F5)', 'f5'),
              btn(Icons.close_fullscreen_rounded, 'End (Esc)', 'escape'),
              btn(Icons.chevron_right_rounded, 'Next', 'right', big: true),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Key layouts for the on-screen gamepad.
const gamepadLayouts = <String, Map<String, String>>{
  'arrows': {
    'up': 'up', 'down': 'down', 'left': 'left', 'right': 'right', //
    'A': 'space', 'B': 'enter', 'X': 'ctrl', 'Y': 'shift',
    'Start': 'escape', 'Select': 'tab',
  },
  'wasd': {
    'up': 'w', 'down': 's', 'left': 'a', 'right': 'd', //
    'A': 'space', 'B': 'e', 'X': 'q', 'Y': 'r',
    'Start': 'escape', 'Select': 'tab',
  },
};

/// A full-screen controller whose buttons hold keys down on the other
/// device, for games that use the keyboard.
class GamepadOverlay extends StatelessWidget {
  const GamepadOverlay({
    super.key,
    required this.link,
    required this.layout,
    required this.onClose,
  });

  final DataLink link;
  final String layout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final map = gamepadLayouts[layout] ?? gamepadLayouts['arrows']!;
    Widget key(String name, {IconData? icon, double size = 72, Color? color}) =>
        _HoldButton(
          link: link,
          keyName: map[name]!,
          size: size,
          color: color,
          child: icon != null
              ? Icon(icon, color: Colors.white, size: size * 0.5)
              : Text(name,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w800)),
        );

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.25),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 24,
              bottom: 24,
              child: SizedBox(
                width: 216,
                height: 216,
                child: Stack(
                  children: [
                    Align(alignment: Alignment.topCenter, child: key('up', icon: Icons.arrow_drop_up_rounded)),
                    Align(alignment: Alignment.bottomCenter, child: key('down', icon: Icons.arrow_drop_down_rounded)),
                    Align(alignment: Alignment.centerLeft, child: key('left', icon: Icons.arrow_left_rounded)),
                    Align(alignment: Alignment.centerRight, child: key('right', icon: Icons.arrow_right_rounded)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: 24,
              child: SizedBox(
                width: 216,
                height: 216,
                child: Stack(
                  children: [
                    Align(alignment: Alignment.topCenter, child: key('Y', color: Colors.amber)),
                    Align(alignment: Alignment.bottomCenter, child: key('A', color: Colors.green)),
                    Align(alignment: Alignment.centerLeft, child: key('X', color: Colors.blue)),
                    Align(alignment: Alignment.centerRight, child: key('B', color: Colors.red)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  key('Select', size: 56),
                  const SizedBox(width: 16),
                  key('Start', size: 56),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    tooltip: 'Close gamepad',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Text(
                'A ${map['A']} · B ${map['B']} · X ${map['X']} · Y ${map['Y']}'
                ' · pad ${map['up']}/${map['left']}/${map['down']}/${map['right']}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds [keyName] down while touched; several can be held at once.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.link,
    required this.keyName,
    required this.child,
    this.size = 72,
    this.color,
  });

  final DataLink link;
  final String keyName;
  final Widget child;
  final double size;
  final Color? color;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  final Set<int> _pointers = {};

  void _set(int pointer, bool down) {
    final was = _pointers.isNotEmpty;
    down ? _pointers.add(pointer) : _pointers.remove(pointer);
    final now = _pointers.isNotEmpty;
    if (was == now) return;
    if (now) HapticFeedback.lightImpact();
    widget.link.sendInput({'e': 'key', 'k': widget.keyName, 'd': now});
    setState(() {});
  }

  @override
  void dispose() {
    if (_pointers.isNotEmpty) {
      widget.link.sendInput({'e': 'key', 'k': widget.keyName, 'd': false});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pointers.isNotEmpty;
    return Listener(
      onPointerDown: (e) => _set(e.pointer, true),
      onPointerUp: (e) => _set(e.pointer, false),
      onPointerCancel: (e) => _set(e.pointer, false),
      child: AnimatedScale(
        scale: pressed ? 0.9 : 1,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (widget.color ?? Colors.white24)
                .withValues(alpha: pressed ? 0.9 : 0.55),
            border: Border.all(color: Colors.white54, width: 2),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
