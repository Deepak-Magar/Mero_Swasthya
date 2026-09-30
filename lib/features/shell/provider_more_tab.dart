import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../shared/widgets/app_widgets.dart';
import 'more_row.dart';

/// The provider shell's More tab.
///
/// Four rows, all of them previously behind an unlabeled `⋮` or a button that
/// competed with the scan tile for the top of the screen. The health-post
/// dashboard belongs here rather than on Home: Home carries today's counts
/// and who needs attention, and the six-tile report is a once-a-day read.
class ProviderMoreTab extends ConsumerWidget {
  const ProviderMoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navMore),
        actions: const [
          SyncPill.compact(),
          SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          40,
        ),
        children: [
          SectionHeader(auth.user?.facilityName ?? l10n.providerHomeTitle),
          // Tier 2.
          MoreRow(
            icon: Icons.insights_outlined,
            label: l10n.dashboardAction,
            body: l10n.dashboardTitle,
            onTap: () => context.push('/provider/dashboard'),
          ),
          MoreRow(
            icon: Icons.sync_rounded,
            label: l10n.syncTitle,
            onTap: () => context.push('/sync'),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(l10n.moreSectionPhone),
          // A dual-role user switches sides several times a day; this was the
          // audit's twelfth finding, hidden behind the same `⋮`.
          MoreRow(
            icon: Icons.family_restroom_outlined,
            label: l10n.providerMyFamily,
            onTap: () => context.go('/family'),
          ),
          MoreRow(
            icon: Icons.settings_outlined,
            label: l10n.settingsTitle,
            body: l10n.settingsLanguage,
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}
