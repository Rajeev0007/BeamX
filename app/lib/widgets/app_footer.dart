import 'package:material_ui/material_ui.dart';

import '../screens/legal_screen.dart';
import '../services/credits.dart';

/// "BeamX 1.0.2 · © 2026 Rajeev Development · Terms · Privacy" plus the
/// official-build badge.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Widget link(String text, String title, String file) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => LegalScreen.open(context, title, file),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(text,
                style: small?.copyWith(
                    color: scheme.primary, decoration: TextDecoration.underline)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          FutureBuilder<OfficialStatus>(
            future: Credits.status(),
            builder: (context, snap) => switch (snap.data) {
              OfficialStatus.official => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Text('Official build', style: small?.copyWith(color: Colors.green)),
                  ],
                ),
              OfficialStatus.unofficial => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: scheme.error),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('Unofficial build: not signed by ${Credits.developer}',
                          style: small?.copyWith(color: scheme.error)),
                    ),
                  ],
                ),
              _ => const SizedBox.shrink(),
            },
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text('BeamX ${Credits.version} · ${Credits.copyright} ·', style: small),
              link('Terms', 'Terms of Service', 'TERMS.md'),
              Text('·', style: small),
              link('Privacy', 'Privacy Policy', 'PRIVACY.md'),
              Text('·', style: small),
              link('Licence', 'Licence and credits', 'NOTICE'),
            ],
          ),
        ],
      ),
    );
  }
}
