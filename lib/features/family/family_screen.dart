import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/rules/edd.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/brand_logo.dart';
import '../auth/auth_controller.dart';
import '../shared/widgets/app_widgets.dart';

/// S06 — Family list, the patient-mode home.
///
/// Reads the local database first so it paints instantly with no network, and
/// lets the sync engine bring anything new in behind it.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  @override
  void initState() {
    super.initState();
    // Spec S06: "GET /patients (on refresh), plus local DB read". The list
    // paints from the database first; this fills in anything the account owns
    // that this device has never seen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(patientRepoProvider).refreshFromServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final ownerId = auth.user?.id ?? '';
    final family = ref.watch(familyProvider(ownerId));

    final name = auth.user?.name;

    return Scaffold(
      appBar: AppBar(
        // Tighter than the gutter because the title now leads with the
        // mark; the gutter's worth of space came out of the greeting.
        titleSpacing: AppSpacing.md,
        // Greeting over label. The family list is a home screen, and a home
        // screen that opens with the user's own name reads as *their* phone
        // rather than as a database they have been given access to.
        title: BrandAppBarTitle(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (name != null && name.isNotEmpty)
              Text(
                l10n.familyGreeting(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              )
            else
              Text(
                l10n.familyTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            if (name != null && name.isNotEmpty)
              Text(l10n.familyTitle,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          const SyncChip(),
          // Everything that is not "open a record" lives behind one overflow.
          // A patient uses this screen every day and activates a provider
          // account roughly once, so that action does not get a permanent
          // seat in the bar.
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.commonMore,
            position: PopupMenuPosition.under,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            onSelected: (value) => switch (value) {
              'provider' => context.go('/provider'),
              'activate' => context.push('/provider/activate'),
              _ => context.push('/settings'),
            },
            itemBuilder: (context) => [
              if (auth.isHealthWorker)
                PopupMenuItem(
                  value: 'provider',
                  child: _MenuRow(
                    icon: Icons.medical_services_outlined,
                    label: l10n.providerHomeTitle,
                  ),
                )
              else
                PopupMenuItem(
                  value: 'activate',
                  child: _MenuRow(
                    icon: Icons.badge_outlined,
                    label: l10n.familyIAmHealthWorker,
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
          Expanded(
            child: asyncView(
              family,
              data: (patients) {
                if (patients.isEmpty) {
                  return EmptyState(
                    icon: Icons.people_outline,
                    title: l10n.familyEmptyTitle,
                    body: l10n.familyEmptyBody,
                    action: FilledButton.icon(
                      onPressed: () => context.push('/family/new'),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.familyAddMember),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    await ref.read(patientRepoProvider).refreshFromServer();
                    await ref.read(syncEngineProvider).run();
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      104,
                    ),
                    itemCount: patients.length,
                    itemBuilder: (context, index) =>
                        _FamilyCard(patient: patients[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/family/new'),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text(l10n.familyAddMember),
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

class _FamilyCard extends ConsumerWidget {
  const _FamilyCard({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final pregnancy = ref.watch(latestPregnancyProvider(patient.id)).valueOrNull;
    final visits = ref.watch(visitsProvider(patient.id)).valueOrNull;
    final dob = BsDate.parseAd(patient.dob);

    final icon = switch (patient.sex) {
      Sex.female => Icons.woman_outlined,
      Sex.male => Icons.man_outlined,
      Sex.other => Icons.person_outline,
    };

    final text = Theme.of(context).textTheme;

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: () => context.push('/patient/${patient.id}'),
      semanticLabel: patient.name,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brandTintOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.brandOf(context)),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            // Name, age and last visit are one cluster describing one person,
            // so they sit 4 px apart and read as a block. The badge is a
            // separate statement about *now*, so it gets 12 px of air.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        patient.name,
                        style: text.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    PendingDot(rowId: patient.id),
                  ],
                ),
                if (dob != null) ...[
                  const SizedBox(height: AppSpacing.tight),
                  Text(
                    l10n.patientHomeAge(BsDate.ageInYears(dob)),
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.tight),
                // Spec §13: Bikram Sambat first. This line used to print the
                // raw wire date — "Last visit 2026-08-25" — which is the one
                // calendar the family does not think in.
                if (visits == null || visits.isEmpty)
                  Text(l10n.familyNoVisitsYet, style: text.bodySmall)
                else
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          l10n.familyLastVisit(''),
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Flexible(
                        child: BsDateText(
                          visits.first.visitAt,
                          showAd: false,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                if (pregnancy != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  PregnantBadge(pregnancy: pregnancy),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.lg, left: AppSpacing.sm),
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

/// "Pregnant · week N" while it is open, "Delivered" once S14 has closed it.
///
/// A pregnancy that ended is still the most useful thing on the card for weeks
/// afterwards — it is what postnatal care hangs off — so the badge changes
/// rather than disappearing.
class PregnantBadge extends StatelessWidget {
  const PregnantBadge({super.key, required this.pregnancy});

  final Pregnancy pregnancy;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    if (pregnancy.status == PregnancyStatus.delivered) {
      return SoftPill(
        icon: Icons.child_care_outlined,
        label: l10n.familyDeliveredBadge,
        foreground: AppColors.onTriageGreen,
        background: AppColors.triageGreenTint,
      );
    }

    final edd = parseIsoDate(pregnancy.edd);
    final week = edd == null
        ? null
        : gestationalAgeWeeks(edd, DateTime.now().toUtc());

    return SoftPill(
      icon: Icons.pregnant_woman_outlined,
      label: week == null
          ? l10n.familyPregnantBadge(0)
          : l10n.familyPregnantBadge(week),
    );
  }
}
