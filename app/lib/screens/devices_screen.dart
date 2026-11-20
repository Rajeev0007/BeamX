import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../models/peer_device.dart';
import '../services/discovery_service.dart';
import '../services/relay_client.dart';
import '../services/trust_store.dart';
import '../widgets/page_header.dart';
import '../widgets/pressable.dart';
import '../widgets/radar.dart';
import 'pairing_sheet.dart';
import 'qr_scan_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  // Refreshes the "last seen" signal indicators.
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _scan(BuildContext context) async {
    final result = await Navigator.of(context).push<ScannedPairing>(
        MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (result == null || !context.mounted) return;
    await showPairingSheet(context, peer: result.peer, code: result.code);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Devices',
            subtitle: 'Connect to share or view a screen',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (qrScanSupported) ...[
                  IconButton.filledTonal(
                    tooltip: 'Scan pairing QR',
                    onPressed: () => _scan(context),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.tonalIcon(
                  onPressed: () => showPairingSheet(context),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Pair'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _ThisDeviceCard()),
        const SliverToBoxAdapter(child: _ConnectToId()),
        SliverToBoxAdapter(
          child: ValueListenableBuilder<String?>(
            valueListenable: scope.connection.versionMismatch,
            builder: (context, msg, _) => msg == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: _Banner(text: msg),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: ValueListenableBuilder<String?>(
            valueListenable: scope.connection.serverError,
            builder: (context, err, _) => err == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: _Banner(text: err),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: ValueListenableBuilder<String?>(
            valueListenable: scope.discovery.error,
            builder: (context, err, _) => err == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: _Banner(text: err),
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: _InternetTrusted()),
        ValueListenableBuilder<List<PeerDevice>>(
          valueListenable: scope.discovery.peers,
          builder: (context, peers, _) {
            if (peers.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisExtent: 168,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _AppearIn(
                    key: ValueKey(peers[i].id),
                    delay: i * 60,
                    child: _DeviceCard(peer: peers[i]),
                  ),
                  childCount: peers.length,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ThisDeviceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.settings;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final on = scheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.value;
          final id = RelayClient.format(scope.connection.myId);
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(color: on)),
                    ),
                    Switch(
                      value: s.discoverable,
                      onChanged: (v) =>
                          store.update((x) => x.copyWith(discoverable: v)),
                    ),
                  ],
                ),
                Text('Your ID', style: t.labelLarge?.copyWith(color: on)),
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SelectableText(id,
                            style: t.headlineMedium?.copyWith(
                                color: on,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy ID',
                      color: on,
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: scope.connection.myId));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ID copied')));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: scope.pairing.code,
                      builder: (context, code, _) => _Chip(
                          icon: Icons.pin_rounded,
                          text: 'Code ${formatCode(code)}'),
                    ),
                    if (s.passwordAccess && scope.trust.hasPassword)
                      const _Chip(icon: Icons.key_rounded, text: 'Password on'),
                    ValueListenableBuilder<RelayStatus>(
                      valueListenable: scope.connection.relayStatus,
                      builder: (context, r, _) => _Chip(
                        icon: r.state == RelayState.online
                            ? Icons.public_rounded
                            : Icons.public_off_rounded,
                        text: switch (r.state) {
                          RelayState.off => 'Local network only',
                          RelayState.connecting => 'Connecting to internet…',
                          RelayState.online => 'Reachable from anywhere',
                          RelayState.error => 'Internet: ${r.message ?? 'offline'}',
                        },
                      ),
                    ),
                    _Chip(
                      icon: s.discoverable
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      text: s.discoverable ? 'Visible nearby' : 'Hidden',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final on = Theme.of(context).colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: on),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: on, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// "Connect to ID" box: type another device's ID to reach it nearby or
/// over the internet.
class _ConnectToId extends StatefulWidget {
  const _ConnectToId();

  @override
  State<_ConnectToId> createState() => _ConnectToIdState();
}

class _ConnectToIdState extends State<_ConnectToId> {
  final _c = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final id = _c.text.replaceAll(' ', '');
    if (!RegExp(r'^\d{9}$').hasMatch(id)) {
      setState(() => _error = 'Enter the 9-digit ID');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final peer = await AppScope.of(context).connection.resolveId(id);
      if (!mounted) return;
      setState(() => _busy = false);
      await showPairingSheet(context, peer: peer);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                    LengthLimitingTextInputFormatter(11),
                  ],
                  onSubmitted: (_) => _go(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Connect to ID',
                    hintText: '123 456 789',
                    errorText: _error,
                    errorMaxLines: 3,
                    prefixIcon: const Icon(Icons.connected_tv_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  onPressed: _busy ? null : _go,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 52)),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Connect'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.peer});
  final PeerDevice peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trusted = AppScope.of(context).connection.isTrustedBy(peer);
    final age = peer.ageSeconds(DateTime.now());
    final signal = age <= 3
        ? Colors.green
        : age <= 6
            ? Colors.orange
            : Colors.red;

    return Pressable(
      onTap: () => showPairingSheet(context, peer: peer),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(peer.icon, color: scheme.onSecondaryContainer),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: signal, shape: BoxShape.circle),
                  ),
                ],
              ),
              const Spacer(),
              Text(peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${peer.platformLabel} · ${peer.address}',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(trusted ? Icons.verified_user_rounded : Icons.wifi_rounded,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(trusted ? 'Trusted · no code' : 'Same Wi-Fi',
                      style: TextStyle(
                          color: scheme.primary, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Radar(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primary,
                child: Icon(Icons.wifi_tethering_rounded,
                    color: scheme.onPrimary),
              ),
            ),
            const SizedBox(height: 24),
            Text('Looking for devices…',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              DiscoveryService.canBroadcast
                  ? 'Open BeamX on another device on the same Wi-Fi,\n'
                      'or tap Pair to connect with a code.'
                  : 'Tap Pair to connect with a code or QR.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: scheme.onErrorContainer))),
        ],
      ),
    );
  }
}

/// Fades and slides a child in when it first appears.
class _AppearIn extends StatefulWidget {
  const _AppearIn({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  State<_AppearIn> createState() => _AppearInState();
}

class _AppearInState extends State<_AppearIn> {
  bool _shown = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(milliseconds: widget.delay), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Devices that trust this one, reachable over the internet with one tap.
class _InternetTrusted extends StatelessWidget {
  const _InternetTrusted();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<RelayStatus>(
      valueListenable: scope.connection.relayStatus,
      builder: (context, relay, _) => ValueListenableBuilder<List<TrustedDevice>>(
        valueListenable: scope.trust.trustsMe,
        builder: (context, list, _) {
          if (relay.state != RelayState.online || list.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text('Your trusted devices · over the internet',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: scheme.primary)),
                  ),
                  for (final d in list)
                    ListTile(
                      leading: const Icon(Icons.public_rounded),
                      title: Text(d.name),
                      subtitle: Text('Internet ID '
                          '${RelayClient.format(RelayClient.internetIdFor(d.id))}'),
                      trailing: const Icon(Icons.arrow_forward_rounded),
                      onTap: () => showPairingSheet(context,
                          peer: PeerDevice(
                            id: d.id,
                            name: d.name,
                            platform: d.platform,
                            address: 'internet',
                            port: 0,
                            lastSeen: DateTime.now(),
                            internetId: RelayClient.internetIdFor(d.id),
                          )),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
