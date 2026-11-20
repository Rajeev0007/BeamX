import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/settings.dart';
import '../widgets/page_header.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).settings;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(
          title: 'Transfers',
          subtitle: 'Files and clipboard between your devices',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant, width: 2),
              color: scheme.surfaceContainerLow,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_file_rounded,
                      size: 44, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text('Drop files here to send',
                      style:
                          t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('File transfer arrives with the connection engine',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Card(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                leading: const Icon(Icons.content_paste_rounded),
                title: const Text('Shared clipboard'),
                subtitle: Text(store.value.clipboardSync.label),
                trailing: Switch(
                  value: store.value.clipboardSync != ClipboardSync.off,
                  onChanged: (v) => store.update((x) => x.copyWith(
                      clipboardSync:
                          v ? ClipboardSync.both : ClipboardSync.off)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: Column(
            children: [
              Icon(Icons.history_rounded,
                  size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('No transfers yet',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
