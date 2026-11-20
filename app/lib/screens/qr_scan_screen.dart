import 'dart:convert';
import 'dart:io' show InternetAddress, Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/peer_device.dart';

/// What a BeamX pairing QR code contains.
class ScannedPairing {
  const ScannedPairing(this.peer, this.code);
  final PeerDevice peer;
  final String code;

  /// Parses an untrusted QR payload. Returns null if it isn't a valid
  /// BeamX code.
  static ScannedPairing? parse(String? raw) {
    if (raw == null || raw.length > 2000) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map || j['app'] != 'beamx') return null;
      final id = j['id'], name = j['name'], port = j['port'];
      final code = j['code'], addrs = j['addrs'];
      if (id is! String || id.length > 64 || name is! String ||
          port is! int || port < 1 || port > 65535 ||
          code is! String || !RegExp(r'^\d{6}$').hasMatch(code) ||
          addrs is! List) {
        return null;
      }
      final address = addrs
          .whereType<String>()
          .where((a) => InternetAddress.tryParse(a) != null)
          .firstOrNull;
      if (address == null) return null;
      final platform = j['platform'];
      return ScannedPairing(
        PeerDevice(
          id: id,
          name: name.length > 40 ? name.substring(0, 40) : name,
          platform: platform is String && platform.length <= 16
              ? platform
              : 'unknown',
          address: address,
          port: port,
          lastSeen: DateTime.now(),
        ),
        code,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Camera scanning is available on phones, tablets and Macs.
bool get qrScanSupported =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;
  String? _hint;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final result = ScannedPairing.parse(b.rawValue);
      if (result != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.pop(context, result);
        return;
      }
    }
    if (_hint == null) {
      setState(() => _hint = 'That is not a BeamX pairing code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan pairing QR'),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: MobileScanner(onDetect: _onDetect)),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 4),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _hint ??
                  'On the other device, open Devices → Pair and point the '
                      'camera at its QR code.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
