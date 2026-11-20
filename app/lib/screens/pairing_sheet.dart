import 'dart:convert';
import 'dart:io' show InternetAddress;
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_scope.dart';
import '../models/peer_device.dart';
import 'stream_screen.dart';

enum StreamDirection { view, share }

Future<void> showPairingSheet(BuildContext context, {PeerDevice? peer}) {
  final Widget sheet =
      peer == null ? const _MyCodeSheet() : _ConnectSheet(peer: peer);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => sheet,
  );
}

String _newCode() {
  final r = Random.secure();
  return List.generate(6, (_) => r.nextInt(10)).join();
}

/// Shows this device's one-time pairing code and QR, plus manual connect.
class _MyCodeSheet extends StatefulWidget {
  const _MyCodeSheet();

  @override
  State<_MyCodeSheet> createState() => _MyCodeSheetState();
}

class _MyCodeSheetState extends State<_MyCodeSheet> {
  String _code = _newCode();
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings.value;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final qrData = jsonEncode({
      'app': 'beamx',
      'id': scope.discovery.selfId,
      'name': s.deviceName,
      'port': s.port,
      'code': _code,
    });

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pair a device',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Scan this QR or enter the code on the other device',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(data: qrData, size: 200),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: SelectableText(
              '${_code.substring(0, 3)} ${_code.substring(3)}',
              key: ValueKey(_code),
              style: t.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: 6),
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _code = _newCode()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('New code'),
          ),
          const Divider(height: 32),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Or connect by address',
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'e.g. 192.168.1.20',
              prefixIcon: const Icon(Icons.lan_rounded),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final addr = _address.text.trim();
                if (InternetAddress.tryParse(addr) == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a valid IP address')));
                  return;
                }
                // The sheet's own context dies on pop, so reopen from the
                // navigator's context.
                final nav = Navigator.of(context);
                nav.pop();
                showPairingSheet(nav.context,
                    peer: PeerDevice(
                      id: 'manual-$addr',
                      name: addr,
                      platform: 'unknown',
                      address: addr,
                      port: s.port,
                      lastSeen: DateTime.now(),
                    ));
              },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Choose a direction and enter the other device's pairing code.
class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.peer});
  final PeerDevice peer;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  StreamDirection _direction = StreamDirection.view;
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _codeValid => RegExp(r'^\d{6}$').hasMatch(_code.text);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final peer = widget.peer;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(peer.icon, size: 32, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.name,
                        style: t.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${peer.platformLabel} · ${peer.address}',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SegmentedButton<StreamDirection>(
            style: const ButtonStyle(
                visualDensity: VisualDensity.comfortable),
            segments: const [
              ButtonSegment(
                value: StreamDirection.view,
                icon: Icon(Icons.visibility_rounded),
                label: Text('View their screen'),
              ),
              ButtonSegment(
                value: StreamDirection.share,
                icon: Icon(Icons.screen_share_rounded),
                label: Text('Share mine'),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (v) => setState(() => _direction = v.first),
          ),
          const SizedBox(height: 20),
          Text('Pairing code shown on ${peer.name}',
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            textAlign: TextAlign.center,
            style: t.headlineSmall?.copyWith(letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _codeValid
                  ? () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(PageRouteBuilder<void>(
                        transitionDuration: const Duration(milliseconds: 400),
                        pageBuilder: (context, animation, secondary) =>
                            StreamScreen(
                          peer: peer,
                          sharingMine: _direction == StreamDirection.share,
                        ),
                        transitionsBuilder: (context, a, secondary, child) =>
                            FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale: Tween(begin: 0.96, end: 1.0).animate(
                                CurvedAnimation(
                                    parent: a, curve: Curves.easeOutCubic)),
                            child: child,
                          ),
                        ),
                      ));
                    }
                  : null,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}
