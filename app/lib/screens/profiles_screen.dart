import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../models/profile.dart';
import '../services/settings_store.dart';
import '../widgets/page_header.dart';
import '../widgets/pressable.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([store, store.customProfiles]),
      builder: (context, _) {
        final active = store.value.activeProfile;
        final custom = store.customProfiles.value;
        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: PageHeader(
                title: 'Profiles',
                subtitle: 'Switch your whole setup with one tap',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisExtent: 150,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = StreamProfile.builtIn[i];
                    return _ProfileCard(
                      profile: p,
                      selected: p.name == active,
                      onTap: () {
                        store.update(p.apply);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: Text('${p.name} profile applied'),
                            behavior: SnackBarBehavior.floating,
                          ));
                      },
                    );
                  },
                  childCount: StreamProfile.builtIn.length,
                ),
              ),
            ),
            if (custom.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 24, 12),
                  child: Text('YOUR PROFILES',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final p = custom[i];
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: _ProfileCard(
                              profile: StreamProfile(
                                name: p.name,
                                description: p.summary,
                                icon: Icons.bookmark_rounded,
                                apply: (s) => s,
                              ),
                              selected: p.name == active,
                              onTap: () => store.applyProfile(p),
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 40,
                            child: IconButton(
                              tooltip: 'Delete profile',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => store.deleteProfile(p.name),
                            ),
                          ),
                        ],
                      );
                    },
                    childCount: custom.length,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.bookmark_add_rounded),
                      label: const Text('Save current settings as profile'),
                      onPressed: () => _saveProfile(context, store),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Export settings'),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: store.exportJson()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Settings copied to clipboard')));
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Import from clipboard'),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final ok = data?.text != null &&
                            store.importJson(data!.text!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? 'Settings imported'
                                  : 'Clipboard does not contain BeamX settings')));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _saveProfile(BuildContext context, SettingsStore store) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Save profile'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(hintText: 'e.g. Work laptop'),
        onSubmitted: (v) => Navigator.pop(d, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(d, c.text.trim()),
            child: const Text('Save')),
      ],
    ),
  );
  c.dispose();
  if (name == null || name.isEmpty) return;
  if (StreamProfile.builtIn.any((p) => p.name == name)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That name is used by a built-in profile')));
    }
    return;
  }
  store.saveProfile(name);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final StreamProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(profile.icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const Spacer(),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutBack,
                  child: Icon(Icons.check_circle_rounded, color: scheme.primary),
                ),
              ],
            ),
            const Spacer(),
            Text(profile.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(profile.description,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
