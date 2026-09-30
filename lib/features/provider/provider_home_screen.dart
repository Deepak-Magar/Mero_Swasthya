import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/brand_logo.dart';
import '../auth/auth_controller.dart';
import '../shared/widgets/app_widgets.dart';
import '../shell/provider_shell.dart';

/// S19 — the provider shell's Patients tab: everyone whose grant is still open.
///
/// The scan tile that used to sit at the top of this screen is gone: scanning
/// is the shell's centre button, on every tab. What is left is what this
/// screen was always for: coming back to somebody already scanned.
///
/// The unlabeled `⋮` that used to hold "My family" and "Settings" is gone too;
/// both are named rows in the More tab.
///
/// With [seenTodayOnly] — Home's "Patients seen" tile — the list is instead
/// everyone with a visit or an ANC contact recorded today, owned records
/// included, under a filter chip that clears back to the full list.
class ProviderHomeScreen extends ConsumerWidget {
  const ProviderHomeScreen({super.key, this.seenTodayOnly = false});

  final bool seenTodayOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final granted = seenTodayOnly
        ? ref
            .watch(providerHomeProvider)
            .whenData((home) => home.seenToday)
        : ref.watch(grantedPatientsProvider);

    Future<void> refresh() => ref.read(syncEngineProvider).run();

    return Scaffold(
      appBar: AppBar(
        title: BrandAppBarTitle(
          child: Text(
            auth.user?.facilityName ?? l10n.providerHomeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // The full pill sits under the bar on this tab; see PatientHomeTab.
        actions: const [SizedBox(width: AppSpacing.sm)],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // The full sync pill: a health worker who has been out of signal all
          // morning needs "3 changes waiting" in words, not an amber glyph.
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.sm,
            ),
            child: SyncPill(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              0,
            ),
            child: seenTodayOnly
                ? SectionHeader(
                    l10n.providerSeenTodayFilter,
                    // The filter, and the way out of it: a chip whose cross
                    // returns to the whole list.
                    trailing: InputChip(
                      label: Text(l10n.providerSeenTodayFilter),
                      avatar: const Icon(Icons.today_outlined, size: 18),
                      deleteButtonTooltipMessage: l10n.providerShowAllPatients,
                      onDeleted: () => context.go(ProviderTabs.patients),
                    ),
                  )
                : SectionHeader(l10n.providerRecentPatients),
          ),
          Expanded(
            child: asyncView(
              granted,
              onRetry: refresh,
              data: (patients) {
                if (patients.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.55,
                          child: seenTodayOnly
                              ? EmptyState(
                                  icon: Icons.today_outlined,
                                  title: l10n.providerSeenTodayEmpty,
                                  body: l10n.providerSeenTodayEmptyBody,
                                  action: OutlinedButton(
                                    onPressed: () =>
                                        context.go(ProviderTabs.patients),
                                    child: Text(l10n.providerShowAllPatients),
                                  ),
                                )
                              : EmptyState(
                                  icon: Icons.qr_code_scanner_rounded,
                                  title: l10n.providerNoRecentPatients,
                                  body: l10n.providerNoRecentPatientsBody,
                                  action: FilledButton.icon(
                                    // The scanner is a pushed route now, the
                                    // same one the centre button opens.
                                    onPressed: () =>
                                        context.push(ProviderTabs.scan),
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                    ),
                                    label: Text(l10n.providerScanQr),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      40,
                    ),
                    itemCount: patients.length,
                    itemBuilder: (context, index) =>
                        _GrantedTile(patient: patients[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GrantedTile extends ConsumerWidget {
  const _GrantedTile({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final pregnancy = ref.watch(activePregnancyProvider(patient.id)).valueOrNull;
    final dob = BsDate.parseAd(patient.dob);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: () => context.push('/provider/patient/${patient.id}'),
      semanticLabel: patient.name,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brandTintOf(context),
              shape: BoxShape.circle,
            ),
            child: Text(
              patient.name.characters.firstOrNull ?? '?',
              style: text.titleMedium?.copyWith(color: AppColors.brandOf(context)),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and age are one cluster; the allergy line is a separate
                // statement and gets its own air, because on this screen it is
                // the only thing that can change what the provider does next.
                Text(patient.name, style: text.titleSmall),
                if (dob != null) ...[
                  const SizedBox(height: AppSpacing.tight),
                  Text(
                    l10n.patientHomeAge(BsDate.ageInYears(dob)),
                    style: text.bodySmall,
                  ),
                ],
                if (patient.allergies.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.dangerInkOf(context),
                      ),
                      const SizedBox(width: AppSpacing.tight),
                      Expanded(
                        child: Text(
                          patient.allergies.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.dangerInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (pregnancy != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SoftPill(
                    icon: Icons.pregnant_woman_outlined,
                    label: l10n.providerActivePregnancy,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.md, left: AppSpacing.sm),
            child: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
