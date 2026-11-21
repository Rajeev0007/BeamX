import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../services/beam_session.dart';
import '../services/data_link.dart';
import '../services/diag_log.dart';
import '../services/discovery_service.dart';
import '../services/prompts.dart';
import '../services/input/input_injector.dart';
import '../services/screen_capture.dart';
import '../services/settings_store.dart';
import '../services/window_control.dart';
import '../widgets/remote_extras.dart';
import '../widgets/remote_surface.dart';

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

  /// Viewer: whether our input goes to the other device (when it allows).
  bool _controlOn = true;
  bool _fullScreen = false;
  bool _gamepad = false;
  bool _dropHover = false;

  static bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  void _toggleFullScreen() {
    setState(() => _fullScreen = !_fullScreen);
    WindowControl.setFullScreen(_fullScreen);
  }

  BeamSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
    _scheduleHide();
    // A sleeping screen pauses the app, and phones then cut its network,
    // which ended sessions with "connection lost". Stay awake meanwhile.
    WakelockPlus.enable().catchError((Object _) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The viewer's quality settings drive the stream.
    if (_settings != null) return;
    _settings = AppScope.of(context).settings..addListener(_onSettings);
    _controlOn = !_settings!.value.viewOnly;
    if (!s.isSharer && _settings!.value.alwaysOnTop) WindowControl.setOnTop(true);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    s.removeListener(_onSession);
    _settings?.removeListener(_onSettings);
    WindowControl.setOnTop(false);
    WakelockPlus.disable().catchError((Object _) {});
    if (_fullScreen) WindowControl.setFullScreen(false);
    // Leaving the screen ends the session.
    s.close('You ended the session');
    super.dispose();
  }

  void _onSettings() {
    final store = _settings;
    if (!mounted || s.isSharer || store == null) return;
    s.requestQuality(StreamQuality.fromSettings(store.value));
    WindowControl.setOnTop(store.value.alwaysOnTop);
    setState(() {}); // e.g. new scroll speed
  }

  void _onSession() {
    if (!mounted) return;
    if (s.phase == SessionPhase.ended && !_popped) {
      _popped = true;
      final reason = s.endReason;
      final messenger = ScaffoldMessenger.of(context);
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        final nav = Navigator.of(context);
        // Close sheets and dialogs opened from the stream (quality, keyboard,
        // media remote, incoming file) along with it.
        if (!route.isCurrent) nav.popUntil((r) => r == route);
        nav.removeRoute(route);
      }
      final failed = reason != null &&
          (reason == BeamSession.couldNotConnect ||
              reason.startsWith('Connection lost') ||
              reason.startsWith('Could not'));
      if (failed) {
        // Real failures get an explanation and the log, not a toast.
        WidgetsBinding.instance.addPostFrameCallback((_) => _showFailure(reason));
      } else if (reason != null && reason != 'You ended the session') {
        messenger.showSnackBar(SnackBar(
          content: Text(reason),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() {});
  }

  static void _showFailure(String reason) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.wifi_off_rounded, size: 36),
        title: const Text('The connection didn\'t work'),
        content: SingleChildScrollView(
          child: Text('$reason\n\n'
              'Things to check:\n'
              '• Both devices run the same BeamX version.\n'
              '• Windows: reinstall with the latest BeamX-windows-setup.exe, or '
              'allow BeamX in Windows Defender Firewall for Private and Public '
              'networks.\n'
              '• Turn off VPN apps on both devices.\n'
              '• Guest or office Wi-Fi often blocks devices from talking to '
              'each other: try a phone hotspot.\n\n'
              'If it still fails, tap Copy log and send it to the developer.'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'BeamX ${DiscoveryService.platform}\n${DiagLog.text}'));
              ScaffoldMessenger.of(d).showSnackBar(
                  const SnackBar(content: Text('Diagnostics log copied')));
            },
            child: const Text('Copy log'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    final page = _page(context);
    if (!_desktop) return page;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dropHover = true),
      onDragExited: (_) => setState(() => _dropHover = false),
      onDragDone: (d) {
        setState(() => _dropHover = false);
        final paths = [
          for (final f in d.files)
            if (f is DropItemFile && f.path.isNotEmpty) f.path,
        ];
        if (paths.isNotEmpty && s.link.ready.value) s.link.sendPaths(paths);
      },
      child: page,
    );
  }

  Widget _page(BuildContext context) {
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
                  if (s.reconnecting)
                    const Positioned.fill(
                        child: _Connecting(text: 'Connection interrupted. Reconnecting…')),
                  if (s.isSharer)
                    const Positioned(
                        top: 16, left: 0, right: 0, child: _SharingPill()),
                  if (s.isSharer)
                    Positioned(
                      top: 64,
                      left: 16,
                      right: 16,
                      child: _ControlProblem(session: s),
                    ),
                  if (showStats)
                    Positioned(
                      top: s.isSharer ? 64 : 16,
                      right: 16,
                      child: _Stats(session: s),
                    ),
                  if (_gamepad && !s.isSharer)
                    Positioned.fill(
                      child: GamepadOverlay(
                        link: s.link,
                        layout: store.value.gamepadPreset,
                        onClose: () => setState(() => _gamepad = false),
                      ),
                    ),
                  if (_dropHover)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black54,
                          child: Center(
                            child: Text('Drop to send to ${s.peerName}',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
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
    final video = RTCVideoView(
      s.renderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      filterQuality: FilterQuality.medium,
    );
    return ValueListenableBuilder<RemoteControlStatus>(
      valueListenable: s.link.remote,
      builder: (context, remote, _) => remote.allowed && _controlOn
          ? RemoteSurface(
              renderer: s.renderer,
              link: s.link,
              scrollSpeed: _settings?.value.pointerSpeed ?? 1.0,
              platform: remote.platform,
              child: video,
            )
          : InteractiveViewer(maxScale: 5, child: video),
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
            const SizedBox(height: 8),
            Text(
              s.sendingAudio
                  ? '🔊 Your device\'s sound is shared too'
                  : ScreenCapture.audioSupported
                      ? '🔇 Sound is not shared (turned off on the viewing device)'
                      : '🔇 Sharing sound from this device isn\'t supported yet',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  /// Every toolbar action for the current state, most important first.
  List<_Action> _actions(BuildContext context, bool showStats) {
    final store = AppScope.of(context).settings;
    final ready = s.link.ready.value;
    final remote = s.link.remote.value;
    final controlling = !s.isSharer && remote.allowed && _controlOn;
    return [
      _Action(
        s.isSharer ? Icons.stop_screen_share_rounded : Icons.call_end_rounded,
        s.isSharer ? 'Stop sharing' : 'Disconnect',
        () => Navigator.of(context).maybePop(),
        color: Colors.redAccent,
        pinned: true,
      ),
      if (s.isSharer)
        _Action(
          s.link.controlAllowed.value ? Icons.mouse_rounded : Icons.mouse_outlined,
          s.link.controlAllowed.value
              ? 'Remote control on (tap to turn off)'
              : 'Let ${s.peerName} control this device',
          InputInjector.create() == null
              ? null
              : () => s.link.setControlAllowed(!s.link.controlAllowed.value),
          active: s.link.controlAllowed.value,
          pinned: true,
        ),
      if (!s.isSharer && remote.allowed)
        _Action(
          _controlOn ? Icons.mouse_rounded : Icons.mouse_outlined,
          _controlOn ? 'Controlling (tap to only watch)' : 'Watching (tap to control)',
          () => setState(() => _controlOn = !_controlOn),
          active: _controlOn,
          pinned: true,
        ),
      if (controlling)
        _Action(Icons.keyboard_rounded, 'Keyboard',
            () => showRemoteKeyboard(context, s.link), pinned: true),
      if (controlling && remote.platform == 'android') ...[
        _Action(Icons.arrow_back_rounded, 'Back',
            () => s.link.sendInput({'e': 'nav', 'a': 'back'}), pinned: true),
        _Action(Icons.circle_outlined, 'Home',
            () => s.link.sendInput({'e': 'nav', 'a': 'home'})),
        _Action(Icons.crop_square_rounded, 'Recent apps',
            () => s.link.sendInput({'e': 'nav', 'a': 'recents'})),
      ],
      if (!s.isSharer)
        _Action(
          _fullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          _fullScreen ? 'Exit full screen' : 'Full screen',
          _toggleFullScreen,
          pinned: true,
        ),
      if (s.receivingAudio)
        _Action(s.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            s.muted ? 'Unmute sound' : 'Mute sound', () => s.setMuted(!s.muted)),
      if (s.micAttached)
        _Action(s.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
            s.micOn ? 'Mute my microphone' : 'Unmute my microphone',
            () => s.setMicOn(!s.micOn),
            active: s.micOn),
      if (controlling)
        _Action(Icons.music_note_rounded, 'Media remote',
            () => showMediaRemote(context, s.link)),
      if (controlling && remote.platform != 'android')
        _Action(Icons.sports_esports_rounded, 'Gamepad',
            () => setState(() => _gamepad = !_gamepad),
            active: _gamepad),
      _Action(Icons.attach_file_rounded, 'Send files',
          ready ? s.link.pickAndSend : null),
      if (s.canCapture)
        _Action(Icons.photo_camera_rounded, 'Screenshot',
            () => _run(context, () async => 'Screenshot saved: ${await s.screenshot()}')),
      if (s.canCapture && BeamSession.recordingSupported)
        _Action(
          s.recording ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
          s.recording ? 'Stop recording' : 'Record',
          () => _run(context, () async {
            if (!s.recording) {
              await s.startRecording();
              return 'Recording… tap ⏹ to stop';
            }
            final path = await s.stopRecording();
            return 'Recording saved: ${path ?? ''}';
          }),
          color: s.recording ? Colors.redAccent : null,
        ),
      if (!s.isSharer)
        _Action(Icons.high_quality_rounded, 'Quality', () => _qualitySheet(context)),
      _Action(
        Icons.query_stats_rounded,
        showStats ? 'Hide stats' : 'Show stats',
        () => store.update((x) => x.copyWith(showStatsOverlay: !x.showStatsOverlay)),
        active: showStats,
      ),
    ];
  }

  Widget _toolbar(BuildContext context, bool showStats) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [s.link.ready, s.link.remote, s.link.controlAllowed]),
      builder: (context, _) => LayoutBuilder(builder: (context, c) {
        final all = _actions(context, showStats);
        // Each button is 48 px; keep them full size and put the rest in
        // a labelled "More" menu instead of shrinking everything.
        final fit = ((c.maxWidth - 32) / 48).floor();
        List<_Action> shown;
        List<_Action> more;
        if (all.length <= fit) {
          shown = all;
          more = const [];
        } else {
          final room = (fit - 1).clamp(1, all.length);
          final pinned = all.where((a) => a.pinned).take(room).toList();
          final extra = all.where((a) => !a.pinned).take(room - pinned.length);
          shown = [...pinned, ...extra];
          more = all.where((a) => !shown.contains(a)).toList();
        }
        return Material(
          color: Colors.black.withValues(alpha: 0.7),
          shape: const StadiumBorder(),
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final a in shown)
                  _ToolButton(
                    icon: a.icon,
                    tooltip: a.label,
                    onTap: a.onTap,
                    color: a.color,
                    active: a.active,
                  ),
                if (more.isNotEmpty)
                  _ToolButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More',
                    onTap: () => _moreSheet(context, more),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _moreSheet(BuildContext context, List<_Action> actions) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in actions)
                ListTile(
                  enabled: a.onTap != null,
                  leading: Icon(a.icon, color: a.color),
                  title: Text(a.label),
                  trailing: a.active ? const Icon(Icons.check_rounded) : null,
                  onTap: a.onTap == null
                      ? null
                      : () {
                          Navigator.pop(sheet);
                          a.onTap!();
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Runs [action] and shows its message, or the error, as a snackbar.
  Future<void> _run(BuildContext context, Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    String msg;
    try {
      msg = await action();
    } catch (e) {
      msg = 'Failed: $e';
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ));
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
                  '${s.link.remote.value.platform == 'android' ? 'Android phones share at up to 30 FPS. ' : ''}'
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
  const _Connecting({this.text = 'Connecting…'});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
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

/// Sharer: explains what to allow in the OS before remote control works.
class _ControlProblem extends StatelessWidget {
  const _ControlProblem({required this.session});
  final BeamSession session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: session.link.controlProblem,
      builder: (context, problem, _) {
        if (problem == null) return const SizedBox.shrink();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.amber.shade800,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Remote control needs permission. $problem',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: session.link.openControlSettings,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('Open settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Action {
  const _Action(this.icon, this.label, this.onTap,
      {this.color, this.active = false, this.pinned = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  /// Kept on the bar when space is short.
  final bool pinned;
}
