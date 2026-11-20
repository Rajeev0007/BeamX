import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Wraps a card so it lifts on hover and shrinks slightly when pressed,
/// with a light haptic tap on phones.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scale = _down ? 0.97 : (_hover ? 1.015 : 1.0);
    final shadow = Theme.of(context).colorScheme.shadow;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                if (_hover)
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
