import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../services/beam_session.dart';
import '../services/settings_store.dart';

/// Full-screen view of a live session with an auto-hiding toolbar.
///
/// Viewer: shows the other device's screen.
/// Sharer: shows that sharing is active, with a small local preview.
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key, required this.session});

  final BeamSession session;

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _toolbarVisible = true;
  Timer? _hideTimer;
  bool _popped = false;
  SettingsStore? _settings;

  BeamSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _scheduleHide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The viewer's quality settings drive the stream.
    if (_settings != null) return;
    _settings = AppScope.of(context).settings..addListener(_onSettings);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    s.removeListener(_onSession);
    _settings?.removeListener(_onSettings);
    // Leaving the screen ends the session.
    s.close('You ended the session');
    super.dispose();
  }

  void _onSettings() {
    final store = _settings;
    if (!mounted || s.isSharer || store == null) return;
    s.requestQuality(StreamQuality.fromSettings(store.value));
  }

  void _onSession() {
    if (!mounted) return;
    if (s.phase == SessionPhase.ended && !_popped) {
      _popped = true;
      final reason = s.endReason;
      final messenger = ScaffoldMessenger.of(context);
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
      if (reason != null && reason != 'You ended the session') {
        messenger.showSnackBar(SnackBar(
          content: Text(reason),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() {});
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
              final showStats = store.value.showStatsOverlay;
              return Stack(
                children: [
                  Positioned.fill(
                    child: s.isSharer ? _sharerView(context) : _viewerView(),
                  ),
                  if (s.phase == SessionPhase.connecting)
                    const Positioned.fill(child: _Connecting()),
                  if (s.isSharer)
                    const Positioned(
                        top: 16, left: 0, right: 0, child: _SharingPill()),
                  if (showStats)
                    Positioned(
                      top: s.isSharer ? 64 : 16,
                      right: 16,
                      child: _Stats(session: s),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    bottom: _toolbarVisible || s.isSharer ? 24 : -100,
                    child: Center(child: _toolbar(context, showStats)),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _viewerView() {
    return InteractiveViewer(
      maxScale: 5,
      child: RTCVideoView(
        s.renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  Widget _sharerView(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 300),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Colors.white10,
                      child: RTCVideoView(s.renderer),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Sharing your screen with ${s.peerName}',
                textAlign: TextAlign.center,
                style: t.headlineSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'You can switch to other apps. Come back here or use the '
              'notification to stop.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool showStats) {
    final store = AppScope.of(context).settings;
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      shape: const StadiumBorder(),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(
              icon: s.isSharer ? Icons.stop_screen_share_rounded : Icons.call_end_rounded,
              tooltip: s.isSharer ? 'Stop sharing' : 'Disconnect',
              color: Colors.redAccent,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: s.link.ready,
              builder: (context, ready, _) => _ToolButton(
                icon: Icons.attach_file_rounded,
                tooltip: 'Send files',
                onTap: ready ? s.link.pickAndSend : null,
              ),
            ),
            _ToolButton(
              icon: Icons.query_stats_rounded,
              tooltip: 'Stats overlay',
              active: showStats,
              onTap: () => store.update(
                  (x) => x.copyWith(showStatsOverlay: !x.showStatsOverlay)),
            ),
            if (!s.isSharer)
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
          final v = store.value;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Resolution'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final r in const [720, 1080, 1440, 2160])
                    ChoiceChip(
                      label: Text(r == 2160 ? '4K' : '${r}p'),
                      selected: v.resolution == r,
                      onSelected: (_) => store.update((x) =>
                          x.copyWith(resolution: r, activeProfile: 'Custom')),
                    ),
                ]),
                const SizedBox(height: 16),
                const Text('Frame rate'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in const [30, 60, 90, 120])
                    ChoiceChip(
                      label: Text('$f FPS'),
                      selected: v.fps == f,
                      onSelected: (_) => store.update(
                          (x) => x.copyWith(fps: f, activeProfile: 'Custom')),
                    ),
                ]),
                const SizedBox(height: 12),
                Text(
                  'The other device lowers these automatically if its screen '
                  'or network can\'t keep up.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting…', style: TextStyle(color: Colors.white70)),
          ],
        ),
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
  final VoidCallback? onTap;
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
        disabledForegroundColor: Colors.white38,
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
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.session});
  final BeamSession session;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        color: Colors.white,
        fontSize: 13,
        fontFeatures: [FontFeature.tabularFigures()]);
    return ValueListenableBuilder<StreamStats>(
      valueListenable: session.stats,
      builder: (context, st, _) {
        String n(num? v, [String unit = '']) =>
            v == null ? '—' : '${v.round()}$unit';
        final mbps = st.kbps == null ? '—' : (st.kbps! / 1000).toStringAsFixed(1);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Video  ${st.width ?? '—'}×${st.height ?? '—'}'
                  '${st.codec == null ? '' : ' · ${st.codec}'}',
                  style: style),
              Text('FPS    ${n(st.fps)}', style: style),
              Text('Rate   $mbps Mbps', style: style),
              Text('Ping   ${n(st.rttMs, ' ms')}', style: style),
            ],
          ),
        );
      },
    );
  }
}
