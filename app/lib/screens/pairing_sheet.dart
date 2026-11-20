import 'dart:convert';
import 'dart:io' show InternetAddress, InternetAddressType, NetworkInterface;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_scope.dart';
import '../models/peer_device.dart';
import '../services/connection_service.dart';
import '../services/discovery_service.dart';
import '../services/relay_client.dart';
import '../services/input/input_injector.dart';
import '../services/password_auth.dart';
import '../services/screen_capture.dart';
import '../services/signaling.dart';

Future<void> showPairingSheet(BuildContext context,
    {PeerDevice? peer, String? code}) {
  final Widget sheet = peer == null
      ? const _MyCodeSheet()
      : _ConnectSheet(peer: peer, initialCode: code);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => sheet,
  );
}

/// This device's local IPv4 addresses, for connecting by address.
Future<List<String>> _localAddresses() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in ifaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
  } catch (_) {
    return const [];
  }
}

/// Formats "123456" as "123 456".
String formatCode(String c) =>
    c.length == 6 ? '${c.substring(0, 3)} ${c.substring(3)}' : c;

/// Shows this device's pairing code and QR, plus connect by IP address.
class _MyCodeSheet extends StatefulWidget {
  const _MyCodeSheet();

  @override
  State<_MyCodeSheet> createState() => _MyCodeSheetState();
}

class _MyCodeSheetState extends State<_MyCodeSheet> {
  final _address = TextEditingController();
  final _internetId = TextEditingController();
  final Future<List<String>> _addresses = _localAddresses();

  @override
  void dispose() {
    _address.dispose();
    _internetId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings.value;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: ValueListenableBuilder<String>(
        valueListenable: scope.pairing.code,
        builder: (context, code, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Pair a device',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('On the other device, tap this device and enter the code',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: SelectableText(
                formatCode(code),
                key: ValueKey(code),
                style: t.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6),
              ),
            ),
            TextButton.icon(
              onPressed: scope.pairing.regenerate,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('New code'),
            ),
            FutureBuilder<List<String>>(
              future: _addresses,
              builder: (context, snap) {
                final list = snap.data ?? const <String>[];
                if (list.isEmpty) return const SizedBox.shrink();
                return SelectableText(
                  'This device\'s address: ${list.join(', ')}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: FutureBuilder<List<String>>(
                future: _addresses,
                builder: (context, snap) => QrImageView(
                  data: jsonEncode({
                    'app': 'beamx',
                    'id': scope.discovery.selfId,
                    'name': s.deviceName,
                    'platform': DiscoveryService.platform,
                    'port': s.port,
                    'addrs': snap.data ?? const <String>[],
                    'code': code,
                  }),
                  size: 160,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('Scan with BeamX on a phone, tablet or Mac',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ValueListenableBuilder<RelayStatus>(
              valueListenable: scope.connection.relayStatus,
              builder: (context, r, _) => r.state != RelayState.online
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 32),
                        Text('Over the internet',
                            style: t.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        SelectableText(
                            'This device\'s Internet ID: '
                            '${RelayClient.format(r.internetId ?? '')}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _internetId,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(9),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Other device\'s 9-digit Internet ID',
                            prefixIcon: const Icon(Icons.public_rounded),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            onPressed: () {
                              final id = _internetId.text;
                              if (!RegExp(r'^\d{9}$').hasMatch(id)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Enter all 9 digits')));
                                return;
                              }
                              final nav = Navigator.of(context);
                              nav.pop();
                              showPairingSheet(nav.context,
                                  peer: PeerDevice(
                                    id: 'internet-$id',
                                    name: 'BeamX ${RelayClient.format(id)}',
                                    platform: 'unknown',
                                    address: 'internet',
                                    port: 0,
                                    lastSeen: DateTime.now(),
                                    internetId: id,
                                  ));
                            },
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(height: 32),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Device not listed? Connect by address',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.1.20',
                prefixIcon: const Icon(Icons.lan_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
      ),
    );
  }
}

/// Choose a direction, enter the other device's code and connect.
class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet({required this.peer, this.initialCode});
  final PeerDevice peer;
  final String? initialCode;

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  late StreamMode _mode =
      _canView ? StreamMode.view : StreamMode.share;
  late final _code = TextEditingController(text: widget.initialCode);
  bool _connecting = false;
  bool _allowControl = false;
  String? _error;

  /// The other device trusts this one, so no code is needed.
  late bool _trusted = widget.initialCode == null &&
      AppScope.of(context).connection.isTrustedBy(widget.peer);

  bool get _canView => widget.peer.platform != 'ios';
  bool get _canShare => ScreenCapture.supported;

  ConnectionService? _connection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connection ??= AppScope.of(context).connection;
  }

  @override
  void dispose() {
    // Closing the sheet while waiting gives up the attempt, so the app
    // doesn't stay busy or open a stream later.
    if (_connecting) _connection?.cancelConnect();
    _code.dispose();
    super.dispose();
  }

  bool _showSecret = false;

  bool get _isCode => RegExp(r'^\d{6}$').hasMatch(_code.text);

  /// A 6-digit pairing code, or the owner's password (8+ characters).
  bool get _codeValid =>
      _trusted || _isCode || _code.text.length >= PasswordAuth.minLength;

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    try {
      await AppScope.of(context).connection.connect(
            peer: widget.peer,
            code: _trusted || !_isCode ? null : _code.text,
            password: _trusted || _isCode ? null : _code.text,
            mode: _mode,
            allowControl: _allowControl,
          );
      _connecting = false;
      // The app has already opened the streaming screen on top, so remove
      // this sheet's own route rather than popping the top one.
      if (route != null && route.isActive) nav.removeRoute(route);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _connecting = false;
        _error = '$e';
        // Trust was removed on the other side: fall back to the code.
        if (e is SignalingException &&
            (e.code == 'untrusted' || e.code == 'need-code')) {
          _trusted = false;
        }
      });
    }
  }

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
                        style:
                            t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                        peer.viaInternet
                            ? 'Over the internet · ID ${RelayClient.format(peer.internetId!)}'
                            : '${peer.platformLabel} · ${peer.address}',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SegmentedButton<StreamMode>(
            segments: [
              ButtonSegment(
                value: StreamMode.view,
                enabled: _canView,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('View their screen'),
              ),
              ButtonSegment(
                value: StreamMode.share,
                enabled: _canShare,
                icon: const Icon(Icons.screen_share_rounded),
                label: const Text('Share mine'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _connecting
                ? null
                : (v) => setState(() => _mode = v.first),
          ),
          if (!_canView || !_canShare) ...[
            const SizedBox(height: 8),
            Text(
              !_canView
                  ? 'iPhones and iPads can\'t share their screen yet.'
                  : ScreenCapture.unsupportedReason,
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (_mode == StreamMode.share && InputInjector.create() != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowControl,
              onChanged: _connecting
                  ? null
                  : (v) => setState(() => _allowControl = v ?? false),
              title: const Text('Let them control my screen'),
              subtitle: const Text('You can turn it off any time.'),
            ),
          const SizedBox(height: 20),
          if (_trusted) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_rounded, color: scheme.primary),
              title: const Text('Trusted: no code needed'),
              subtitle: _error == null
                  ? null
                  : Text(_error!, style: TextStyle(color: scheme.error)),
              trailing: TextButton(
                onPressed: _connecting
                    ? null
                    : () => setState(() => _trusted = false),
                child: const Text('Use code'),
              ),
            ),
          ] else ...[
          Text('Password, or the pairing code shown on ${peer.name}',
              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            enabled: !_connecting,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            obscureText: !_showSecret && !_isCode,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 128,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _codeValid && !_connecting ? _connect() : null,
            textAlign: TextAlign.center,
            style: t.titleLarge?.copyWith(letterSpacing: 2),
            decoration: InputDecoration(
              counterText: '',
              hintText: '123456 or password',
              suffixIcon: IconButton(
                tooltip: _showSecret ? 'Hide' : 'Show',
                icon: Icon(_showSecret
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _showSecret = !_showSecret),
              ),
              errorText: _error,
              errorMaxLines: 4,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _codeValid && !_connecting ? _connect : null,
              icon: _connecting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.link_rounded),
              label: Text(_connecting
                  ? 'Waiting for ${peer.name} to accept…'
                  : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }
}
