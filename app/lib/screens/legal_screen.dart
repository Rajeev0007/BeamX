import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Shows TERMS.md, PRIVACY.md or NOTICE as bundled with the app.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  static void open(BuildContext context, String title, String file) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => LegalScreen(title: title, asset: 'assets/legal/$file')));

  /// Light Markdown cleanup for plain-text display.
  static String _plain(String md) => md
      .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^#+ ', multiLine: true), '')
      .replaceAll(RegExp(r'^_(.+)_$', multiLine: true), r'$1');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(asset),
        builder: (context, snap) => snap.hasData
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: SelectableText(_plain(snap.data!),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5)),
                  ),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
