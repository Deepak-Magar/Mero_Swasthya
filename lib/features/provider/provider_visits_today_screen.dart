import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/rules/provider_home.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import 'provider_widgets.dart';

/// The list behind Home's "Visits recorded" tile: every visit saved on this
/// phone today, newest first, with whether it has reached the server yet.
class ProviderVisitsTodayScreen extends ConsumerWidget {
  const ProviderVisitsTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final home = ref.watch(providerHomeProvider);
    final complaints =
        ref.watch(codelistProvider(CodeListKind.complaint)).valueOrNull ??
            const [];
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    String complaintLabel(String code) {
      for (final item in complaints) {
        if (item.code == code) return nepali ? item.labelNp : item.labelEn;
      }
      return code;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.providerVisitsTodayTitle),
        actions: const [SyncPill.compact(), SizedBox(width: AppSpacing.sm)],
      ),
      body: asyncView(
        home,
        data: (value) {
          if (value.visitsToday.isEmpty) {
            return EmptyState(
              icon: Icons.note_add_outlined,
              title: l10n.providerVisitsTodayEmpty,
              body: l10n.providerVisitsTodayEmptyBody,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              40,
            ),
            itemCount: value.visitsToday.length,
            itemBuilder: (context, index) => _VisitTile(
              row: value.visitsToday[index],
              complaint: complaintLabel(value.visitsToday[index].visit.chiefComplaintCode),
            ),
          );
        },
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.row, required this.complaint});

  final VisitToday row;
  final String complaint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final at = DateTime.tryParse(row.visit.visitAt)?.toLocal();
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}';

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      onTap: () => context.push('/provider/patient/${row.patient.id}'),
      semanticLabel: row.patient.name,
      child: Row(
        children: [
          PatientAvatar(name: row.patient.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.patient.name, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  [time, complaint].where((s) => s.isNotEmpty).join(' · '),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PendingDot(rowId: row.visit.id),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }
}
