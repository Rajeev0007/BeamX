import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../models/settings.dart';
import '../services/beam_session.dart';
import '../services/prompts.dart';
import '../services/transfer_service.dart';
import '../widgets/page_header.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.settings;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageHeader(
          title: 'Transfers',
          subtitle: 'Files and clipboard between connected devices',
          trailing: ListenableBuilder(
            listenable: scope.transfers,
            builder: (context, _) => scope.transfers.items.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: scope.transfers.clearFinished,
                    child: const Text('Clear'),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ValueListenableBuilder<BeamSession?>(
            valueListenable: scope.connection.session,
            builder: (context, session, _) =>
                _SendCard(session: session, scheme: scheme, t: t),
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
                subtitle: Text(
                    '${store.value.clipboardSync.label} · text copied on one '
                    'device can be pasted on the other while connected'),
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
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: scope.transfers,
          builder: (context, _) {
            final items = scope.transfers.items;
            if (items.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  children: [
                    Icon(Icons.history_rounded,
                        size: 40, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text('No transfers yet',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [for (final i in items) _TransferTile(item: i)],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SendCard extends StatelessWidget {
  const _SendCard({required this.session, required this.scheme, required this.t});
  final BeamSession? session;
  final ColorScheme scheme;
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant, width: 2),
        color: scheme.surfaceContainerLow,
      ),
      child: Column(
        children: [
          Icon(Icons.upload_file_rounded, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(s == null ? 'Not connected' : 'Send files to ${s.peerName}',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            s == null
                ? 'Start a session from Devices to send files'
                : 'They\'ll be asked to accept each file',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (s != null) ...[
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: s.link.ready,
              builder: (context, ready, _) => FilledButton.icon(
                onPressed: ready ? s.link.pickAndSend : null,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(ready ? 'Choose files' : 'Connecting…'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.item});
  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final out = item.direction == TransferDirection.outgoing;
    final status = switch (item.status) {
      TransferStatus.waiting => out ? 'Waiting for ${item.peer} to accept' : 'Waiting',
      TransferStatus.active =>
        '${formatBytes(item.transferred)} of ${formatBytes(item.size)}',
      TransferStatus.done => out
          ? 'Sent to ${item.peer} · ${formatBytes(item.size)}'
          : 'Saved to ${item.path ?? 'Downloads'}',
      TransferStatus.declined => '${item.peer} declined',
      TransferStatus.failed => 'Failed: ${item.error ?? 'unknown error'}',
    };
    final icon = switch (item.status) {
      TransferStatus.done => Icons.check_circle_rounded,
      TransferStatus.failed || TransferStatus.declined => Icons.error_rounded,
      _ => out ? Icons.north_east_rounded : Icons.south_west_rounded,
    };
    final color = switch (item.status) {
      TransferStatus.done => Colors.green,
      TransferStatus.failed || TransferStatus.declined => scheme.error,
      _ => scheme.primary,
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(status, maxLines: 2),
          if (item.status == TransferStatus.active)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(value: item.progress),
            ),
        ],
      ),
    );
  }
}
