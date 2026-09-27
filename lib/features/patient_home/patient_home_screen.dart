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
import '../shared/widgets/app_widgets.dart';
import '../shell/shell_scaffold.dart';
import 'share_sheet.dart';

/// S08 — one family member's record: the card, and the QR that shares it.
///
/// Two ways in, one body. The Home tab of the patient shell shows it for
/// whichever member the avatar strip has selected; `/patient/:id` shows it for
/// one named member with a back arrow, which is what a deep link and the
/// provider-side links need. Both render [PatientRecordBody], so the record
/// cannot look like two different screens depending on how it was reached.
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
          const SyncPill.compact(),
          // Labelled through its tooltip *and* duplicated as "Edit details" in
          // the More tab. The audit's finding was that a lone pencil is the
          // only way to correct a name; it is now the shortcut, not the path.
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.moreEditDetails,
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
          return PatientRecordBody(patient: value);
        },
      ),
    );
  }
}

/// The record itself: identity, the one primary action, the tile grid, and the
/// pregnancy card when there is one.
///
/// Scrollable and unpadded at the top so it can sit under the family strip on
/// the Home tab or directly under an app bar on `/patient/:id`.
class PatientRecordBody extends ConsumerWidget {
  const PatientRecordBody({super.key, required this.patient});

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

    // The fourth tile is whichever of the maternal / child journeys this person
    // is actually on. It is the same rule as before the UX pass, with the one
    // thing the audit found wrong about it fixed: whatever loses the slot is
    // now a labelled row in the More tab rather than unreachable. In
    // particular a woman whose pregnancy has been delivered can register the
    // next one from More, which she could not before.
    final (fourthIcon, fourthLabel, fourthRoute) = switch (patient) {
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
      // in the grid, the slot falls back to the audit list, which is the one
      // remaining thing every patient has.
      _ => (
          Icons.visibility_outlined,
          l10n.patientHomeWhoViewed,
          '/patient/${patient.id}/audit',
        ),
    };

    // A tile for a screen that is also a tab switches to it instead of pushing
    // a second copy. Outside the shell — `/patient/:id`, a widget test — there
    // is no tab to switch to, so it pushes the route as it always did.
    final shell = ShellScope.maybeOf(context);
    void openTab(int index, String route) {
      if (shell == null) {
        context.push(route);
      } else {
        shell.select(index);
      }
    }

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

        // Exactly one primary button on the screen, and it is on Home rather
        // than one level down: "show this to the health worker" is the whole
        // product, and it is now the first thing a patient can reach.
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
        // 2 x 2, not 1 x 4.
        //
        // Four tiles across a 360 dp phone left about 78 dp each, and the
        // audit's sixth finding was the result: Devanagari labels shrank to a
        // fragment and the row read as four unlabelled icons. Half as many per
        // row is twice the width for the word, which is what makes the tile a
        // labelled control rather than a glyph.
        Row(
          children: [
            Expanded(
              child: SoftTile(
                icon: Icons.history_rounded,
                label: l10n.patientHomeTimeline,
                onTap: () =>
                    openTab(1, '/patient/${patient.id}/timeline'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SoftTile(
                icon: Icons.folder_outlined,
                label: l10n.patientHomeDocuments,
                onTap: () =>
                    openTab(2, '/patient/${patient.id}/documents'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SoftTile(
                icon: fourthIcon,
                label: fourthLabel,
                onTap: () => context.push(fourthRoute),
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
      ],
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
