import 'package:flutter/material.dart';

/// Animated "searching" pulse shown while looking for nearby devices.
class Radar extends StatefulWidget {
  const Radar({super.key, this.size = 180, required this.child});

  final double size;
  final Widget child;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++) _ring(color, (_c.value + i / 3) % 1),
            child!,
          ],
        ),
        child: widget.child,
      ),
    );
  }

  Widget _ring(Color color, double t) {
    final eased = Curves.easeOut.transform(t);
    return Container(
      width: widget.size * (0.3 + 0.7 * eased),
      height: widget.size * (0.3 + 0.7 * eased),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: (1 - t) * 0.6),
          width: 2,
        ),
      ),
    );
  }
}
