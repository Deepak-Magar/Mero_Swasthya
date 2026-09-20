import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/anc_schedule.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/epi_schedule.dart';
import '../../shared/widgets/soft_card.dart';
import '../export/export_pdf_button.dart';
import '../shared/widgets/app_widgets.dart';
import 'share_sheet.dart';

/// S08 — Patient home: the card, and the QR that shares it.
class PatientHomeScreen extends ConsumerWidget {
  const PatientHomeScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final patient = ref.watch(patientProvider(patientId));

    return Scaffold(
      appBar: AppBar(
        title: Text(patient.valueOrNull?.name ?? l10n.commonLoading),
        actions: [
          const SyncChip(),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.commonEdit,
            onPressed: () => context.push('/family/$patientId/edit'),
          ),
        ],
      ),
      body: asyncView(
        patient,
        data: (value) {
          if (value == null) {
            return EmptyState(
              icon: Icons.person_off_outlined,
              title: l10n.errorNotFound,
            );
          }
          return _Body(patient: value);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    // The latest, not only the active one: S14 closes a pregnancy, and a
    // closed pregnancy that vanishes from S08 takes the delivery record with
    // it — the dashboard would be reachable from nowhere.
    final pregnancy = ref.watch(latestPregnancyProvider(patient.id)).valueOrNull;
    final isActive = pregnancy?.status == PregnancyStatus.active;
    // Tier 3. Under five is where the EPI schedule and growth monitoring both
    // stop, so that is where the card stops being offered.
    final dob = BsDate.parseAd(patient.dob);
    final isChild = dob != null && isUnderFive(dob);

    // Tier 3's overdue-dose count, lifted onto the quick-action tile as a
    // badge. "Two overdue" is a reason to open child health; the words "Child
    // health" on their own are not.
    final schedule =
        ref.watch(immunisationScheduleProvider(patient.id)).valueOrNull ??
            const <Immunisation>[];
    final overdue = isChild ? overdueDoses(schedule).length : 0;

    // The third tile is whichever of the maternal / child journeys this person
    // is actually on. Everyone has a timeline, documents and reminders; only
    // one of these four ever applies at a time, so they share a slot instead of
    // each claiming a permanent row nobody needs.
    final (thirdIcon, thirdLabel, thirdRoute) = switch (patient) {
      _ when isActive => (
          Icons.pregnant_woman_outlined,
          l10n.pregnancyDashboardTitle,
          '/pregnancy/${pregnancy!.id}',
        ),
      _ when isChild => (
          Icons.vaccines_outlined,
          l10n.childHealthAction,
          '/patient/${patient.id}/child',
        ),
      _ when patient.sex == Sex.female => (
          Icons.pregnant_woman_outlined,
          l10n.patientHomeRegisterPregnancy,
          '/patient/${patient.id}/pregnancy/new',
        ),
      // An adult man on no maternal or child pathway. Rather than leave a hole
      // in the row, the slot falls back to the audit list, which is the one
      // remaining thing every patient has.
      _ => (
          Icons.visibility_outlined,
          l10n.patientHomeWhoViewed,
          '/patient/${patient.id}/audit',
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        40,
      ),
      children: [
        _HeaderCluster(patient: patient),
        const SizedBox(height: AppSpacing.xl),

        // Exactly one primary button on the screen. Everything else is a tile,
        // a card or a line in the More sheet — so "show this to the health
        // worker" is never one of five equally loud choices.
        FilledButton.icon(
          onPressed: () => showShareSheet(context, patient.id),
          icon: const Icon(Icons.qr_code_2_rounded, size: 26),
          label: Text(l10n.patientHomeShareRecord),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandOf(context),
            foregroundColor: AppColors.onBrandOf(context),
            minimumSize: const Size.fromHeight(60),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: SoftTile(
                icon: Icons.history_rounded,
                label: l10n.patientHomeTimeline,
                onTap: () => context.push('/patient/${patient.id}/timeline'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SoftTile(
                icon: Icons.folder_outlined,
                label: l10n.patientHomeDocuments,
                onTap: () => context.push('/patient/${patient.id}/documents'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SoftTile(
                icon: thirdIcon,
                label: thirdLabel,
                onTap: () => context.push(thirdRoute),
                badge: overdue > 0 ? _CountBadge(count: overdue) : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SoftTile(
                icon: Icons.notifications_outlined,
                label: l10n.patientHomeReminders,
                onTap: () => context.push('/patient/${patient.id}/reminders'),
              ),
            ),
          ],
        ),

        if (pregnancy != null && isActive) ...[
          const SizedBox(height: AppSpacing.xl),
          _PregnancyCard(pregnancy: pregnancy),
        ],
        if (pregnancy != null && !isActive) ...[
          const SizedBox(height: AppSpacing.xl),
          _DeliveredCard(pregnancy: pregnancy),
        ],

        const SizedBox(height: AppSpacing.xl),
        // Printable card, audit and PDF export all live one tap down. Each is
        // used once in a while — when somebody loses a phone, when a referral
        // hospital wants paper — and none of them earns a permanent row on the
        // screen a family opens every week.
        Center(
          child: TextButton.icon(
            onPressed: () => _showMoreSheet(context, patient),
            icon: const Icon(Icons.more_horiz_rounded, size: 20),
            label: Text(l10n.commonMore),
          ),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, Patient patient) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final l10n = L.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(l10n.commonMore),
                _SheetRow(
                  icon: Icons.visibility_outlined,
                  label: l10n.patientHomeWhoViewed,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/patient/${patient.id}/audit');
                  },
                ),
                // Spec A.7. The ten-minute QR needs a charged phone with a
                // signal at the moment somebody asks; this one needs neither.
                _SheetRow(
                  icon: Icons.badge_outlined,
                  label: l10n.printedCardAction,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.push('/patient/${patient.id}/card');
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                // Tier 3. The record belongs to the patient, so it has to be
                // able to leave the app: a printed sheet works in a referral
                // hospital with no network, no account and no copy of this
                // software.
                ExportPdfButton(patient: patient),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A row in the S08 More sheet: outlined glyph, label, chevron.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondaryOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// The red count on the child-health tile.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: AppColors.triageRed,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.onBrand,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ),
    );
  }
}

/// The identity cluster at the top of S08.
///
/// Not a card: it is the page's own headline, and putting it on a white
/// rectangle would make the person's name look like one more item in a list of
/// items. Name, age and blood group sit 4 px apart as one block; the allergy
/// row is a separate statement and gets 16 px of air.
class _HeaderCluster extends StatelessWidget {
  const _HeaderCluster({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final dob = BsDate.parseAd(patient.dob);

    final facts = <String>[
      if (dob != null) l10n.patientHomeAge(BsDate.ageInYears(dob)),
      if (patient.bloodGroup != null)
        '${l10n.patientHomeBloodGroup} ${patient.bloodGroup}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(patient.name, style: text.headlineMedium),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.tight),
          Text(
            facts.join('  ·  '),
            style: text.bodyMedium?.copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // Spec §16: allergies are always shown, even when empty, so their
        // absence is a statement rather than an oversight.
        AllergyChipRow(allergies: patient.allergies),
      ],
    );
  }
}

class _PregnancyCard extends ConsumerWidget {
  const _PregnancyCard({required this.pregnancy});

  final Pregnancy pregnancy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final bundle = ref.watch(pregnancyBundleProvider(pregnancy.id)).valueOrNull;
    final edd = parseIsoDate(pregnancy.edd);
    final week =
        edd == null ? null : gestationalAgeWeeks(edd, DateTime.now().toUtc());

    final next = bundle == null ? null : nextContact(bundle.ancContacts);
    final lastDone = bundle?.ancContacts
        .where((c) => c.doneAt != null)
        .fold<AncContact?>(null, (a, b) => b);

    final text = Theme.of(context).textTheme;
    final subtle = text.bodyMedium?.copyWith(color: AppColors.textSecondaryOf(context));

    return SoftCard(
      onTap: () => context.push('/pregnancy/${pregnancy.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pregnant_woman_outlined,
                size: 20,
                color: AppColors.brandOf(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  week == null
                      ? l10n.pregnancyDashboardTitle
                      : l10n.pregnancyWeekOf(week),
                  style: text.titleMedium,
                ),
              ),
              if (lastDone?.triageLevel != null) ...[
                TriageDot(level: lastDone!.triageLevel),
                const SizedBox(width: AppSpacing.sm),
              ],
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryOf(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // EDD and next contact are the two dates this card exists to carry,
          // so they sit together as one cluster under the week count.
          FactRow(
            label: l10n.pregnancyEdd,
            value: BsDateText(pregnancy.edd, showAd: false, style: subtle),
          ),
          if (next != null)
            FactRow(
              label: l10n.pregnancyContactNumber(next.contactNo),
              value: BsDateText(next.dueAt, showAd: false, style: subtle),
            ),
        ],
      ),
    );
  }
}

/// The way back to a pregnancy S14 has closed.
///
/// Small on purpose: the postnatal record still matters, but it is no longer
/// the thing this woman's week is organised around, and the screen's headline
/// should be whatever comes next.
class _DeliveredCard extends StatelessWidget {
  const _DeliveredCard({required this.pregnancy});

  final Pregnancy pregnancy;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    final text = Theme.of(context).textTheme;

    return SoftCard(
      onTap: () => context.push('/pregnancy/${pregnancy.id}'),
      child: Row(
        children: [
          Icon(
            Icons.child_care_outlined,
            size: 22,
            color: AppColors.successInkOf(context),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.pregnancyDelivered, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                BsDateText(
                  pregnancy.edd,
                  showAd: false,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }
}
