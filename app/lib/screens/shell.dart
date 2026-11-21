import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../services/beam_session.dart';
import '../services/connection_service.dart';
import 'devices_screen.dart';
import 'incoming_request_dialog.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'stream_screen.dart';
import 'terms_gate.dart';
import 'transfers_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  _Destination('Devices', Icons.devices_outlined, Icons.devices_rounded),
  _Destination('Transfers', Icons.swap_vert_outlined, Icons.swap_vert_rounded),
  _Destination('Profiles', Icons.dashboard_customize_outlined,
      Icons.dashboard_customize_rounded),
  _Destination('Settings', Icons.settings_outlined, Icons.settings_rounded),
];

/// Main layout. Uses a bottom bar on phones, a side rail on tablets and
/// small windows, and an extended rail with labels on large screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  ConnectionService? _connection;
  BeamSession? _shownSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_connection != null) return;
    final c = AppScope.of(context).connection;
    _connection = c;
    c.pending.addListener(_onPending);
    c.session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureTermsAccepted(context);
    });
  }

  @override
  void dispose() {
    _connection?.pending.removeListener(_onPending);
    _connection?.session.removeListener(_onSession);
    super.dispose();
  }

  /// Another device asked to connect: ask the user.
  void _onPending() {
    final req = _connection?.pending.value;
    if (req == null || !mounted) return;
    showIncomingRequestDialog(context, req);
  }

  /// A session started: open the streaming screen.
  void _onSession() {
    final s = _connection?.session.value;
    if (s == null || s == _shownSession || !mounted) return;
    _shownSession = s;
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondary) => StreamScreen(session: s),
      transitionsBuilder: (context, a, secondary, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
  }

  Widget _page(int i) => switch (i) {
        0 => const DevicesScreen(),
        1 => const TransfersScreen(),
        2 => const ProfilesScreen(),
        _ => const SettingsScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 640;
    final extended = width >= 1100;

    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
              .animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_index), child: _page(_index)),
    );

    if (compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: _index,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _Logo(extended: extended),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mark = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.cast_rounded, color: scheme.onPrimary, size: 22),
    );
    if (!extended) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 12),
        Text('BeamX',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
