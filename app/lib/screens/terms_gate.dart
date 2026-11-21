import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/credits.dart';
import 'legal_screen.dart';

const _acceptedKey = 'beamx.termsAccepted.v1';

/// On first launch, asks the user to accept the Terms and Privacy Policy.
Future<void> ensureTermsAccepted(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_acceptedKey) ?? false) return;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (d) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.cast_rounded, size: 40),
        title: const Text('Welcome to BeamX'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Before you start, please read and accept the Terms '
                  'of Service and Privacy Policy.\n\n'
                  'Only connect to devices you own or are allowed to use. '
                  'Never give your ID and password to strangers.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: () => LegalScreen.open(d, 'Terms of Service', 'TERMS.md'),
                  child: const Text('Terms of Service'),
                ),
                OutlinedButton(
                  onPressed: () => LegalScreen.open(d, 'Privacy Policy', 'PRIVACY.md'),
                  child: const Text('Privacy Policy'),
                ),
              ]),
              const SizedBox(height: 12),
              Text('${Credits.copyright}',
                  style: Theme.of(d).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Exit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('I agree'),
          ),
        ],
      ),
    ),
  );
  if (ok ?? false) {
    await prefs.setBool(_acceptedKey, true);
  } else if (Platform.isAndroid || Platform.isIOS) {
    await SystemNavigator.pop();
  } else {
    exit(0);
  }
}
