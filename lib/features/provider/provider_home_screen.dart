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

/// S19 — Provider home: scan, and the patients whose grants are still open.
class ProviderHomeScreen extends ConsumerWidget {
  const ProviderHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final granted = ref.watch(grantedPatientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: BrandAppBarTitle(
          child: Text(
            auth.user?.facilityName ?? l10n.providerHomeTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          const SyncChip(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.commonMore,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            onSelected: (value) => switch (value) {
              'family' => context.go('/family'),
              _ => context.push('/settings'),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'family',
                child: _MenuRow(
                  icon: Icons.family_restroom_outlined,
                  label: l10n.providerMyFamily,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: _MenuRow(
                  icon: Icons.settings_outlined,
                  label: l10n.settingsTitle,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              0,
            ),
            child: Column(
              children: [
                // The whole reason the phone is out of the pocket. It is a
                // tile rather than a button: at 96 dp of brand blue it is the
                // first thing the eye lands on and can be hit without looking.
                _ScanTile(onTap: () => context.push('/provider/scan')),
                const SizedBox(height: AppSpacing.md),
                // Tier 2. Below the scan tile because it is a once-a-day read,
                // not the thing being done with a patient at the door.
                OutlinedButton.icon(
                  onPressed: () => context.push('/provider/dashboard'),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: Text(l10n.dashboardAction),
                ),
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(l10n.providerRecentPatients),
              ],
            ),
          ),
          Expanded(
            child: asyncView(
              granted,
              data: (patients) {
                if (patients.isEmpty) {
                  return EmptyState(
                    icon: Icons.qr_code_scanner_rounded,
                    title: l10n.providerNoRecentPatients,
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    40,
                  ),
                  itemCount: patients.length,
                  itemBuilder: (context, index) =>
                      _GrantedTile(patient: patients[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// S19's primary action.
class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Semantics(
      button: true,
      label: l10n.providerScanQr,
      child: Material(
        color: AppColors.brandOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 36,
                  color: AppColors.onBrandOf(context),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    l10n.providerScanQr,
                    style: TextStyle(
                      color: AppColors.onBrandOf(context),
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row inside the app-bar overflow menu.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
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
