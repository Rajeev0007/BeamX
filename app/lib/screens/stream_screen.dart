import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../models/peer_device.dart';
import '../models/settings.dart';

/// Full-screen streaming view with an auto-hiding floating toolbar.
///
/// v0.1 shows the layout and controls only. The video engine is added in
/// the next milestone, so no stream data is displayed yet.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key, required this.peer, required this.sharingMine});

  final PeerDevice peer;
  final bool sharingMine;

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen>
    with SingleTickerProviderStateMixin {
  bool _toolbarVisible = true;
  Timer? _hideTimer;
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _glow.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toolbarVisible = false);
    });
  }

  void _wake() {
    if (!_toolbarVisible) setState(() => _toolbarVisible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).settings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) => _wake(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _wake,
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final s = store.value;
              return Stack(
                children: [
                  Positioned.fill(child: _placeholder(context)),
                  if (widget.sharingMine)
                    const Positioned(
                        top: 16, left: 0, right: 0, child: _SharingPill()),
                  if (s.showStatsOverlay)
                    Positioned(top: 16, right: 16, child: _Stats(s: s)),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: _toolbarVisible ? 24 : -100,
                    child: Center(child: _toolbar(context, s)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.4 + _glow.value * 0.8, -0.2),
            radius: 1.2,
            colors: [scheme.primary.withValues(alpha: 0.35), Colors.black],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    widget.sharingMine
                        ? Icons.screen_share_rounded
                        : Icons.connected_tv_rounded,
                    size: 64,
                    color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  widget.sharingMine
                      ? 'Sharing to ${widget.peer.name}'
                      : 'Viewing ${widget.peer.name}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preview: the streaming engine arrives in the next update.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, BeamSettings s) {
    final store = AppScope.of(context).settings;
    return Material(
      color: Colors.black.withValues(alpha: 0.65),
      shape: const StadiumBorder(),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(
              icon: Icons.call_end_rounded,
              tooltip: 'Disconnect',
              color: Colors.redAccent,
              onTap: () => Navigator.pop(context),
            ),
            _ToolButton(
              icon: s.audioEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              tooltip: s.audioEnabled ? 'Mute audio' : 'Unmute audio',
              onTap: () =>
                  store.update((x) => x.copyWith(audioEnabled: !x.audioEnabled)),
            ),
            if (!widget.sharingMine)
              _ToolButton(
                icon: s.viewOnly
                    ? Icons.visibility_rounded
                    : Icons.touch_app_rounded,
                tooltip: s.viewOnly ? 'View only (tap to control)' : 'Control on',
                onTap: () =>
                    store.update((x) => x.copyWith(viewOnly: !x.viewOnly)),
              ),
            _ToolButton(
              icon: Icons.query_stats_rounded,
              tooltip: 'Stats overlay',
              active: s.showStatsOverlay,
              onTap: () => store.update(
                  (x) => x.copyWith(showStatsOverlay: !x.showStatsOverlay)),
            ),
            _ToolButton(
              icon: Icons.high_quality_rounded,
              tooltip: 'Quality',
              onTap: () => _qualitySheet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _qualitySheet(BuildContext context) {
    final store = AppScope.of(context).settings;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.value;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resolution'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final r in const [720, 1080, 1440, 2160])
                    ChoiceChip(
                      label: Text(r == 2160 ? '4K' : '${r}p'),
                      selected: s.resolution == r,
                      onSelected: (_) =>
                          store.update((x) => x.copyWith(resolution: r)),
                    ),
                ]),
                const SizedBox(height: 16),
                const Text('Frame rate'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final f in const [30, 60, 90, 120])
                    ChoiceChip(
                      label: Text('$f FPS'),
                      selected: s.fps == f,
                      onSelected: (_) =>
                          store.update((x) => x.copyWith(fps: f)),
                    ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      isSelected: active,
      style: IconButton.styleFrom(
        foregroundColor: color ?? Colors.white,
        backgroundColor: active ? Colors.white24 : null,
      ),
      icon: Icon(icon),
    );
  }
}

/// Always visible while this device's screen is shared, so sharing can
/// never happen silently.
class _SharingPill extends StatelessWidget {
  const _SharingPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record, size: 12, color: Colors.white),
            SizedBox(width: 6),
            Text('Your screen is being shared',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.s});
  final BeamSettings s;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target ${s.resolution}p · ${s.fps} FPS', style: style),
          Text(
              'Bitrate ${s.autoBitrate ? 'auto' : '${s.bitrateMbps.round()} Mbps'}',
              style: style),
          const Text('Ping —  ·  Measured FPS —', style: style),
        ],
      ),
    );
  }
}
