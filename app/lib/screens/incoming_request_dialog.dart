import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../services/connection_service.dart';

/// Asks whether to allow another device to connect. Declines automatically
/// if the dialog is dismissed.
Future<void> showIncomingRequestDialog(
    BuildContext context, IncomingRequest req) async {
  HapticFeedback.mediumImpact();
  final viewing = req.mode == StreamMode.view;
  var open = true;
  // Close the dialog if the request expires or the other device gives up.
  req.decided.then((_) {
    if (open && context.mounted) Navigator.of(context).pop();
  });
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (d) {
      final scheme = Theme.of(d).colorScheme;
      return AlertDialog(
        icon: Icon(
          viewing ? Icons.visibility_rounded : Icons.cast_rounded,
          color: scheme.primary,
          size: 36,
        ),
        title: Text(viewing
            ? '${req.name} wants to view your screen'
            : '${req.name} wants to show their screen'),
        content: Text(
          viewing
              ? 'They will see everything on your screen, including '
                  'notifications, until you stop sharing.\n\n'
                  'Address: ${req.address}'
              : 'Their screen will appear on this device.\n\n'
                  'Address: ${req.address}',
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
      );
    },
  );
  open = false;
  if (ok ?? false) {
    req.accept();
  } else {
    req.decline();
  }
}
