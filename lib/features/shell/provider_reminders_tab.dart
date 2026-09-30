import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/rules/provider_home.dart';
import '../../shared/widgets/soft_card.dart';
import '../provider/provider_widgets.dart';
import '../shared/widgets/app_widgets.dart';

/// The provider shell's Reminders tab: every ANC contact this phone knows is
/// owed, in the order a health worker works through them — today's, then the
/// ones already missed, then the coming week.
///
/// Read from the same [providerHomeProvider] as Home, so the "ANC due today"
/// tile and this list can never disagree about a number.
class ProviderRemindersTab extends ConsumerWidget {
  const ProviderRemindersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final home = ref.watch(providerHomeProvider);

    Future<void> refresh() async {
      ref.invalidate(providerHomeProvider);
      try {
        await ref.read(providerHomeProvider.future);
      } on Object {
        // Reported by the error state.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remindersTitle),
        actions: const [SyncPill.compact(), SizedBox(width: AppSpacing.sm)],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: asyncView(
                home,
                onRetry: refresh,
                data: (value) {
                  final sections = [
                    (l10n.providerRemindersDueToday, value.dueToday, false),
                    (l10n.dashboardOverdue, value.overdue, true),
                    (l10n.providerRemindersNextWeek, value.upcoming, false),
                  ].where((s) => s.$2.isNotEmpty).toList();

                  if (sections.isEmpty) {
                    return ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: l10n.providerRemindersEmpty,
                            body: l10n.providerRemindersEmptyBody,
                            action: FilledButton.icon(
                              onPressed: () => context.push('/provider/scan'),
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              label: Text(l10n.providerScanQr),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      56,
                    ),
                    children: [
                      for (final (title, rows, overdue) in sections) ...[
                        SectionHeader('$title · ${rows.length}'),
                        for (final DueContact row in rows)
                          DueContactTile(row: row, overdue: overdue),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
