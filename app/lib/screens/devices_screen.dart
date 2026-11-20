import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../models/peer_device.dart';
import '../services/discovery_service.dart';
import '../widgets/page_header.dart';
import '../widgets/pressable.dart';
import '../widgets/radar.dart';
import 'pairing_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: 'Devices',
            subtitle: 'Connect to share or view a screen',
            trailing: FilledButton.tonalIcon(
              onPressed: () => showPairingSheet(context),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Pair'),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _ThisDeviceCard()),
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
    final store = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.value;
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
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary,
                  child: Icon(Icons.cast_connected_rounded,
                      color: scheme.onPrimary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onPrimaryContainer)),
                      const SizedBox(height: 2),
                      ValueListenableBuilder<String>(
                        valueListenable: AppScope.of(context).pairing.code,
                        builder: (context, code, _) => Text(
                          'Pairing code ${formatCode(code)}',
                          style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]),
                        ),
                      ),
                      Text(
                        s.discoverable
                            ? 'Visible to nearby devices'
                            : 'Hidden from nearby devices',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: s.discoverable,
                  onChanged: (v) =>
                      store.update((x) => x.copyWith(discoverable: v)),
                ),
              ],
            ),
          );
        },
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
                  Icon(Icons.wifi_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('Same Wi-Fi',
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
