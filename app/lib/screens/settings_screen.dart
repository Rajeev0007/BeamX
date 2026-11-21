import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../models/settings.dart';
import '../services/credits.dart';
import '../services/diag_log.dart';
import '../services/discovery_service.dart';
import '../services/password_auth.dart';
import '../services/settings_store.dart';
import '../services/trust_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_footer.dart';
import '../widgets/page_header.dart';
import 'legal_screen.dart';

/// One searchable row in the settings list.
class _Entry {
  const _Entry(this.section, this.title, this.keywords, this.build);
  final String section;
  final String title;
  final String keywords;
  final Widget Function(BuildContext, SettingsStore, BeamSettings) build;

  bool matches(String q) =>
      q.isEmpty ||
      '$section $title $keywords'.toLowerCase().contains(q.toLowerCase());
}

/// Streaming changes made by hand switch the active profile to "Custom".
void _setStream(SettingsStore store, BeamSettings Function(BeamSettings) f) =>
    store.update((s) => f(s).copyWith(activeProfile: 'Custom'));

/// Asks for a new access password twice, then stores only its derived key.
Future<void> _setPassword(BuildContext c, SettingsStore st) async {
  final scope = AppScope.of(c);
  final key = await showDialog<String>(
    context: c,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(hostId: scope.trust.deviceId),
  );
  if (key == null) return;
  await scope.trust.setPasswordKey(key);
  st.update((x) => x.copyWith(passwordAccess: true));
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(
        content: Text('Password set. Share it only with people you trust.')));
  }
}

const beamxVersion = Credits.version;

final _entries = <_Entry>[
  // Streaming
  _Entry('Streaming', 'Resolution', 'quality hd 4k 1080 720', (c, st, s) {
    return _ChoiceRow<int>(
      title: 'Resolution',
      icon: Icons.aspect_ratio_rounded,
      value: s.resolution,
      options: const {480: '480p', 720: '720p', 1080: '1080p', 1440: '1440p', 2160: '4K'},
      onChanged: (v) => _setStream(st, (x) => x.copyWith(resolution: v)),
    );
  }),
  _Entry('Streaming', 'Frame rate', 'fps smooth 60 120', (c, st, s) {
    return _ChoiceRow<int>(
      title: 'Frame rate',
      icon: Icons.speed_rounded,
      value: s.fps,
      options: const {30: '30', 60: '60', 90: '90', 120: '120'},
      onChanged: (v) => _setStream(st, (x) => x.copyWith(fps: v)),
    );
  }),
  _Entry('Streaming', 'Automatic bitrate', 'adaptive data quality', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.auto_graph_rounded),
      title: const Text('Automatic bitrate'),
      subtitle: const Text('Adjusts quality to your connection'),
      value: s.autoBitrate,
      onChanged: (v) => _setStream(st, (x) => x.copyWith(autoBitrate: v)),
    );
  }),
  _Entry('Streaming', 'Bitrate', 'mbps data quality', (c, st, s) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: s.autoBitrate
          ? const SizedBox(width: double.infinity)
          : ListTile(
              leading: const Icon(Icons.data_usage_rounded),
              title: Text('Bitrate: ${s.bitrateMbps.round()} Mbps'),
              subtitle: Slider(
                min: 1,
                max: 80,
                divisions: 79,
                value: s.bitrateMbps.clamp(1, 80).toDouble(),
                label: '${s.bitrateMbps.round()} Mbps',
                onChanged: (v) =>
                    _setStream(st, (x) => x.copyWith(bitrateMbps: v)),
              ),
            ),
    );
  }),
  _Entry('Streaming', 'Video codec', 'h264 h265 hevc av1', (c, st, s) {
    return _DropdownRow<VideoCodec>(
      title: 'Video codec',
      icon: Icons.movie_filter_rounded,
      value: s.codec,
      items: {for (final v in VideoCodec.values) v: v.label},
      onChanged: (v) => _setStream(st, (x) => x.copyWith(codec: v)),
    );
  }),

  // Audio
  _Entry('Audio', 'Stream audio', 'sound', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.volume_up_rounded),
      title: const Text('Stream audio'),
      subtitle: const Text('Hear the sound of Windows and Linux devices you view'),
      value: s.audioEnabled,
      onChanged: (v) => st.update((x) => x.copyWith(audioEnabled: v)),
    );
  }),
  _Entry('Audio', 'Play sound on', 'speaker output', (c, st, s) {
    return _DropdownRow<AudioOutput>(
      title: 'Play sound on',
      icon: Icons.speaker_rounded,
      value: s.audioOutput,
      items: {for (final v in AudioOutput.values) v: v.label},
      onChanged: (v) => st.update((x) => x.copyWith(audioOutput: v)),
    );
  }),
  _Entry('Audio', 'Share microphone', 'mic voice', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.mic_rounded),
      title: const Text('Share my microphone when viewing'),
      subtitle: const Text('The other device plays your voice. Mute it any '
          'time with the 🎤 button.'),
      value: s.micSharing,
      onChanged: (v) => st.update((x) => x.copyWith(micSharing: v)),
    );
  }),

  // Connection
  _Entry('Connection', 'Port', 'network advanced', (c, st, s) {
    return _TextRow(
      title: 'Port',
      icon: Icons.settings_ethernet_rounded,
      initial: '${s.port}',
      numeric: true,
      validate: (v) {
        final p = int.tryParse(v);
        return p != null && p >= 1024 && p <= 65535
            ? null
            : 'Use a number from 1024 to 65535';
      },
      onSaved: (v) => st.update((x) => x.copyWith(port: int.parse(v))),
    );
  }),
  _Entry('Access from anywhere', 'Connect from anywhere', 'internet remote anywhere online', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.public_rounded),
      title: const Text('Connect from anywhere'),
      subtitle: Text(s.signalingServer.isEmpty
          ? 'Reachable by ID over the internet while BeamX is open. Uses the '
              'free public server (no setup).'
          : 'Reachable by ID over the internet through your own server'),
      value: s.internetEnabled,
      onChanged: (v) => st.update((x) => x.copyWith(internetEnabled: v)),
    );
  }),
  _Entry('Access from anywhere', 'Password access', 'password unattended id', (c, st, s) {
    final has = AppScope.of(c).trust.hasPassword;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.key_rounded),
          title: const Text('Allow connecting with a password'),
          subtitle: const Text(
              'People who know this device\'s ID and your password can '
              'connect without the code, even when you\'re away'),
          value: s.passwordAccess && has,
          onChanged: (v) async {
            if (v) {
              await _setPassword(c, st);
            } else {
              await AppScope.of(c).trust.setPasswordKey(null);
              st.update((x) => x.copyWith(passwordAccess: false));
            }
          },
        ),
        if (s.passwordAccess && has) ...[
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _setPassword(c, st),
          ),
          SwitchListTile(
            secondary: const SizedBox(width: 24),
            title: const Text('Still ask me to Allow'),
            subtitle: const Text('Off: password connections start straight away'),
            value: s.passwordAsk,
            onChanged: (v) => st.update((x) => x.copyWith(passwordAsk: v)),
          ),
          SwitchListTile(
            secondary: const SizedBox(width: 24),
            title: const Text('Password connections can control this device'),
            value: s.passwordControl,
            onChanged: (v) => st.update((x) => x.copyWith(passwordControl: v)),
          ),
        ],
      ],
    );
  }),
  _Entry('Connection', 'Internet server', 'signaling relay remote anywhere', (c, st, s) {
    return _TextRow(
      title: 'Your own internet server (optional, more reliable)',
      icon: Icons.public_rounded,
      initial: s.signalingServer,
      hint: 'wss://1-2-3-4.sslip.io/beamx',
      validate: (v) {
        if (v.trim().isEmpty) return null;
        final u = Uri.tryParse(v.trim());
        return u != null && u.scheme == 'wss' && u.host.isNotEmpty
            ? null
            : 'Must be a wss:// address (encrypted), see server/README.md';
      },
      onSaved: (v) => st.update((x) => x.copyWith(signalingServer: v.trim())),
    );
  }),
  _Entry('Connection', 'Auto-connect trusted devices', 'reconnect', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.autorenew_rounded),
      title: const Text('Trusted devices skip the Allow prompt'),
      subtitle: const Text('Turn off to approve every connection, even from trusted devices'),
      value: s.autoConnectTrusted,
      onChanged: (v) => st.update((x) => x.copyWith(autoConnectTrusted: v)),
    );
  }),

  // Control & display
  _Entry('Control & display', 'Scroll speed', 'mouse wheel touch sensitivity pointer', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.swap_vert_rounded),
      title: Text('Scroll speed when controlling: ${s.pointerSpeed.toStringAsFixed(1)}×'),
      subtitle: Slider(
        min: 0.2,
        max: 3,
        divisions: 28,
        value: s.pointerSpeed.clamp(0.2, 3).toDouble(),
        onChanged: (v) => st.update((x) => x.copyWith(pointerSpeed: v)),
      ),
    );
  }),
  if (Platform.isAndroid || Platform.isIOS)
    _Entry('Control & display', 'Screen rotation', 'rotate orientation portrait landscape lock', (c, st, s) {
      return _ChoiceRow<String>(
        title: 'Screen rotation',
        icon: Icons.screen_rotation_rounded,
        value: s.orientation,
        options: const {'auto': 'Auto', 'portrait': 'Portrait', 'landscape': 'Landscape'},
        onChanged: (v) => st.update((x) => x.copyWith(orientation: v)),
      );
    }),
  _Entry('Control & display', 'Gamepad keys', 'game controller keys wasd arrows', (c, st, s) {
    return _ChoiceRow<String>(
      title: 'Gamepad keys',
      icon: Icons.sports_esports_rounded,
      value: s.gamepadPreset,
      options: const {'arrows': 'Arrows + Space', 'wasd': 'WASD + Space'},
      onChanged: (v) => st.update((x) => x.copyWith(gamepadPreset: v)),
    );
  }),
  _Entry('Control & display', 'View only', 'control disable', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.visibility_rounded),
      title: const Text('View only'),
      subtitle: const Text('Watch without controlling the other device'),
      value: s.viewOnly,
      onChanged: (v) => st.update((x) => x.copyWith(viewOnly: v)),
    );
  }),
  _Entry('Control & display', 'Stats overlay', 'fps ping bitrate', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.query_stats_rounded),
      title: const Text('Stats overlay'),
      value: s.showStatsOverlay,
      onChanged: (v) => st.update((x) => x.copyWith(showStatsOverlay: v)),
    );
  }),
  _Entry('Control & display', 'Always on top', 'window pc', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.picture_in_picture_rounded),
      title: const Text('Keep stream window on top'),
      subtitle: const Text('Computers only: the viewing window stays above other apps'),
      value: s.alwaysOnTop,
      onChanged: (v) => st.update((x) => x.copyWith(alwaysOnTop: v)),
    );
  }),

  // Appearance
  _Entry('Appearance', 'Device name', 'rename', (c, st, s) {
    return _TextRow(
      title: 'Device name',
      icon: Icons.badge_rounded,
      initial: s.deviceName,
      validate: (v) => v.trim().isEmpty || v.length > 40
          ? 'Use 1 to 40 characters'
          : null,
      onSaved: (v) => st.update((x) => x.copyWith(deviceName: v.trim())),
    );
  }),
  _Entry('Appearance', 'Theme', 'dark light mode', (c, st, s) {
    return _ChoiceRow<ThemeMode>(
      title: 'Theme',
      icon: Icons.dark_mode_rounded,
      value: s.themeMode,
      options: const {
        ThemeMode.system: 'System',
        ThemeMode.light: 'Light',
        ThemeMode.dark: 'Dark',
      },
      onChanged: (v) => st.update((x) => x.copyWith(themeMode: v)),
    );
  }),
  _Entry('Appearance', 'Accent colour', 'color theme', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.palette_rounded),
      title: const Text('Accent colour'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < AppTheme.accents.length; i++)
              _ColorDot(
                color: AppTheme.accents[i],
                selected: s.accentIndex == i,
                onTap: () => st.update((x) => x.copyWith(accentIndex: i)),
              ),
          ],
        ),
      ),
    );
  }),

  // Security & privacy
  _Entry('Security & privacy', 'Ask before every connection', 'approve permission', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.verified_user_rounded),
      title: const Text('Ask before every connection'),
      subtitle: const Text('Trusted devices can skip this if auto-connect is on'),
      value: s.requireApproval,
      onChanged: (v) => st.update((x) => x.copyWith(requireApproval: v)),
    );
  }),
  _Entry('Security & privacy', 'End-to-end encryption', 'secure encrypt', (c, st, s) {
    return const ListTile(
      leading: Icon(Icons.lock_rounded),
      title: Text('End-to-end encryption'),
      subtitle: Text('Always on. BeamX never sends unencrypted streams.'),
      trailing: Icon(Icons.check_circle_rounded, color: Colors.green),
    );
  }),
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
    _Entry('Security & privacy', 'Save folder', 'download folder location files', (c, st, s) {
      return ListTile(
        leading: const Icon(Icons.folder_rounded),
        title: const Text('Save received files to'),
        subtitle: Text(s.saveFolder.isEmpty ? 'Downloads/BeamX (default)' : s.saveFolder),
        trailing: Wrap(spacing: 4, children: [
          if (s.saveFolder.isNotEmpty)
            TextButton(
              onPressed: () => st.update((x) => x.copyWith(saveFolder: '')),
              child: const Text('Default'),
            ),
          FilledButton.tonal(
            onPressed: () async {
              final uri = await FilePicker.pickDirectory();
              if (uri != null && uri.scheme == 'file') {
                st.update((x) => x.copyWith(saveFolder: uri.toFilePath()));
              }
            },
            child: const Text('Change'),
          ),
        ]),
      );
    }),
  _Entry('Security & privacy', 'Clipboard sync', 'copy paste', (c, st, s) {
    return _DropdownRow<ClipboardSync>(
      title: 'Clipboard sync',
      icon: Icons.content_paste_rounded,
      value: s.clipboardSync,
      items: {for (final v in ClipboardSync.values) v: v.label},
      onChanged: (v) => st.update((x) => x.copyWith(clipboardSync: v)),
    );
  }),
  _Entry('Security & privacy', 'Trusted devices', 'trust remember forget remove', (c, st, s) {
    final trust = AppScope.of(c).trust;
    return ValueListenableBuilder<List<TrustedDevice>>(
      valueListenable: trust.trustedByMe,
      builder: (c, list, _) => ExpansionTile(
        leading: const Icon(Icons.verified_user_rounded),
        title: const Text('Trusted devices'),
        subtitle: Text(list.isEmpty
            ? 'None. Tick "Trust this device" when allowing a connection.'
            : '${list.length} can connect without a code'),
        children: [
          for (final d in list)
            ListTile(
              title: Text(d.name),
              subtitle: Text('${d.platform} · added '
                  '${d.added.toLocal().toString().substring(0, 10)}'),
              trailing: TextButton(
                onPressed: () => trust.untrust(d.id),
                child: const Text('Remove'),
              ),
            ),
        ],
      ),
    );
  }),
  _Entry('Security & privacy', 'Visible to nearby devices', 'discoverable hidden', (c, st, s) {
    return SwitchListTile(
      secondary: const Icon(Icons.wifi_tethering_rounded),
      title: const Text('Visible to nearby devices'),
      value: s.discoverable,
      onChanged: (v) => st.update((x) => x.copyWith(discoverable: v)),
    );
  }),

  // Reset
  _Entry('About', 'About BeamX', 'version licence license copyright rajeev development', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: const Text('About BeamX'),
      subtitle: const Text('Version $beamxVersion · © 2026 Rajeev Development'),
      onTap: () => showAboutDialog(
        context: c,
        applicationName: 'BeamX',
        applicationVersion: beamxVersion,
        applicationIcon: const Icon(Icons.cast_rounded, size: 40),
        applicationLegalese: '© 2026 Rajeev Development.\n'
            'Free and open source under the GNU GPL v3. "BeamX" is a name of '
            'Rajeev Development.',
        children: const [
          SizedBox(height: 16),
          SelectableText('Official downloads and source code:\n'
              'https://github.com/Rajeev0007/BeamX'),
        ],
      ),
    );
  }),
  _Entry('About', 'Terms of Service', 'tos terms legal agreement', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.gavel_rounded),
      title: const Text('Terms of Service'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => LegalScreen.open(c, 'Terms of Service', 'TERMS.md'),
    );
  }),
  _Entry('About', 'Privacy Policy', 'privacy data policy', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.privacy_tip_rounded),
      title: const Text('Privacy Policy'),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => LegalScreen.open(c, 'Privacy Policy', 'PRIVACY.md'),
    );
  }),
  _Entry('About', 'Copy diagnostics log', 'bug report log debug problem', (c, st, s) {
    return ListTile(
      leading: const Icon(Icons.bug_report_rounded),
      title: const Text('Copy diagnostics log'),
      subtitle: const Text('Connection events from this app session, without '
          'passwords or codes. Paste it into a bug report.'),
      onTap: () async {
        final text = DiagLog.isEmpty ? 'No events yet' : DiagLog.text;
        await Clipboard.setData(ClipboardData(
            text: 'BeamX ${DiscoveryService.platform}\n$text'));
        if (c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(
              const SnackBar(content: Text('Diagnostics log copied')));
        }
      },
    );
  }),
  _Entry('About', 'Reset all settings', 'default restore', (c, st, s) {
    return ListTile(
      leading: Icon(Icons.restart_alt_rounded,
          color: Theme.of(c).colorScheme.error),
      title: const Text('Reset all settings'),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: c,
          builder: (d) => AlertDialog(
            title: const Text('Reset all settings?'),
            content: const Text('Every option returns to its default value.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Reset')),
            ],
          ),
        );
        if (ok ?? false) st.reset();
      },
    );
  }),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).settings;
    final visible = _entries.where((e) => e.matches(_query)).toList();
    final sections = <String, List<_Entry>>{};
    for (final e in visible) {
      sections.putIfAbsent(e.section, () => []).add(e);
    }

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final s = store.value;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            PageHeader(
              title: 'Settings',
              subtitle: 'Profile: ${s.activeProfile}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: SearchBar(
                hintText: 'Search settings',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (sections.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: Text('No settings match your search')),
              ),
            for (final entry in sections.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 24, 8),
                child: Text(entry.key.toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final e in entry.value)
                        KeyedSubtree(
                          key: ValueKey(e.title),
                          child: e.build(context, store, s),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const AppFooter(),
          ],
        );
      },
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options.entries)
              ChoiceChip(
                label: Text(o.value),
                selected: o.key == value,
                onSelected: (_) => onChanged(o.key),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(items[value] ?? ''),
      trailing: PopupMenuButton<T>(
        initialValue: value,
        onSelected: onChanged,
        icon: const Icon(Icons.expand_more_rounded),
        itemBuilder: (_) => [
          for (final i in items.entries)
            PopupMenuItem(value: i.key, child: Text(i.value)),
        ],
      ),
    );
  }
}

class _TextRow extends StatefulWidget {
  const _TextRow({
    required this.title,
    required this.icon,
    required this.initial,
    required this.validate,
    required this.onSaved,
    this.hint,
    this.numeric = false,
  });

  final String title;
  final IconData icon;
  final String initial;
  final String? hint;
  final bool numeric;
  final String? Function(String) validate;
  final ValueChanged<String> onSaved;

  @override
  State<_TextRow> createState() => _TextRowState();
}

class _TextRowState extends State<_TextRow> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void didUpdateWidget(_TextRow old) {
    super.didUpdateWidget(old);
    // Reflect outside changes (e.g. reset or profile import).
    if (widget.initial != old.initial && widget.initial != _c.text) {
      _c.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final err = widget.validate(_c.text);
    setState(() => _error = err);
    if (err == null && _c.text != widget.initial) widget.onSaved(_c.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Focus(
        onFocusChange: (has) {
          if (!has) _submit();
        },
        child: TextField(
          controller: _c,
          keyboardType: widget.numeric ? TextInputType.number : null,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.title,
            hintText: widget.hint,
            errorText: _error,
            prefixIcon: Icon(widget.icon),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.hostId});
  final String hostId;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _show = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weak = PasswordAuth.weakness(_a.text);
    if (weak != null) {
      setState(() => _error = weak);
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = 'Passwords don\'t match');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final key = await PasswordAuth.deriveKey(_a.text, widget.hostId);
    if (mounted) Navigator.pop(context, key);
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _show = !_show),
          ),
        );
    return AlertDialog(
      icon: const Icon(Icons.key_rounded, size: 36),
      title: const Text('Set access password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Anyone with this device\'s ID and this password can '
                'connect. Use a long password you don\'t use anywhere else.'),
            const SizedBox(height: 16),
            TextField(
              controller: _a,
              obscureText: !_show,
              enabled: !_working,
              autofocus: true,
              decoration: deco('Password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _b,
              obscureText: !_show,
              enabled: !_working,
              onSubmitted: (_) => _save(),
              decoration: deco('Repeat password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working ? null : _save,
          child: _working
              ? const SizedBox.square(
                  dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Save'),
        ),
      ],
    );
  }
}
