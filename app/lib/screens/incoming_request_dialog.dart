import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/connection_service.dart';

/// Asks whether to allow another device to connect. Declines automatically
/// if the request expires or the other device gives up.
Future<void> showIncomingRequestDialog(
    BuildContext context, IncomingRequest req) async {
  HapticFeedback.mediumImpact();
  final viewing = req.mode == StreamMode.view;
  var open = true;
  var trust = false;
  // Close the dialog if the request expires or the other device gives up.
  req.decided.then((_) {
    if (open && context.mounted) Navigator.of(context).pop();
  });
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (d) {
      final scheme = Theme.of(d).colorScheme;
      return StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          icon: Icon(
            viewing ? Icons.visibility_rounded : Icons.cast_rounded,
            color: scheme.primary,
            size: 36,
          ),
          title: Text(viewing
              ? '${req.name} wants to view your screen'
              : '${req.name} wants to show their screen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(viewing
                  ? 'They will see everything on your screen, including '
                      'notifications, until you stop sharing.'
                  : 'Their screen will appear on this device.'),
              const SizedBox(height: 8),
              Text('Address: ${req.address}'
                  '${req.alreadyTrusted ? ' · Trusted device' : ''}'),
              if (!req.alreadyTrusted) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: trust,
                  onChanged: (v) => setState(() => trust = v ?? false),
                  title: const Text('Trust this device'),
                  subtitle: const Text(
                      'Next time it can connect without a code. '
                      'You can remove it in Settings.'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(viewing ? 'Allow and share' : 'Allow'),
            ),
          ],
        ),
      );
    },
  );
  open = false;
  if (ok ?? false) {
    req.accept(trust: trust);
  } else {
    req.decline();
  }
}
