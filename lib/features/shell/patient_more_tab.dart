import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/epi_schedule.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../export/export_pdf_button.dart';
import '../shared/widgets/app_widgets.dart';
import 'more_row.dart';

/// The patient shell's More tab.
///
/// Every feature the audit found behind an unlabeled `⋮` or three taps down a
/// "More" text button lives here, as a named row with a line saying what it is
/// for. Nothing in this app is now more than two taps from a home screen, and
/// nothing is reached through a glyph alone.
///
/// Two sections, because the two halves answer different questions:
///
///  * **This record** — things about the member the strip has selected.
///  * **This phone** — things about the account and the device, which are the
///    same whichever member is selected.
class PatientMoreTab extends ConsumerWidget {
  const PatientMoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final ownerId = auth.user?.id ?? '';
    final family = ref.watch(familyProvider(ownerId)).valueOrNull ?? const [];
    final selectedId = ref.watch(selectedMemberProvider);

    final Patient? patient = family.isEmpty
        ? null
        : family.firstWhere(
            (p) => p.id == selectedId,
            orElse: () => family.first,
          );

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
          if (patient != null) ...[
            // Whose record these rows act on. Without it, "Who viewed my
            // record" on a four-person phone is an unanswerable question.
            SectionHeader('${l10n.moreSectionRecord} · ${patient.name}'),
            ..._recordRows(context, ref, l10n, patient),
            const SizedBox(height: AppSpacing.lg),
          ],
          SectionHeader(l10n.moreSectionPhone),
          if (auth.isHealthWorker)
            MoreRow(
              icon: Icons.medical_services_outlined,
              label: l10n.moreHealthWorkerMode,
              body: l10n.providerHomeTitle,
              onTap: () => context.go('/provider'),
            )
          else
            // The single route from a patient account to a provider one. The
            // audit ranked hiding this third-worst of everything it found.
            MoreRow(
              icon: Icons.badge_outlined,
              label: l10n.familyIAmHealthWorker,
              onTap: () => context.push('/provider/activate'),
            ),
          MoreRow(
            icon: Icons.sync_rounded,
            label: l10n.syncTitle,
            onTap: () => context.push('/sync'),
          ),
          MoreRow(
            icon: Icons.settings_outlined,
            label: l10n.settingsTitle,
            // Naming the language switch here is the point: it was the most
            // buried control in the app and the one most often asked for.
            body: l10n.settingsLanguage,
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  List<Widget> _recordRows(
    BuildContext context,
    WidgetRef ref,
    L l10n,
    Patient patient,
  ) {
    final pregnancy =
        ref.watch(latestPregnancyProvider(patient.id)).valueOrNull;
    final dob = BsDate.parseAd(patient.dob);
    final isChild = dob != null && isUnderFive(dob);

    // Deliberately *not* conditional on the Home grid's fourth slot. A feature
    // that applies is listed here whether or not it also won the tile, which is
    // what fixes the audit's fourth finding: a delivered pregnancy no longer
    // takes "Register pregnancy" off the phone with it.
    final canRegister = patient.sex == Sex.female &&
        pregnancy?.status != PregnancyStatus.active;

    return [
      MoreRow(
        icon: Icons.notifications_outlined,
        label: l10n.patientHomeReminders,
        onTap: () => context.push('/patient/${patient.id}/reminders'),
      ),
      MoreRow(
        icon: Icons.visibility_outlined,
        label: l10n.patientHomeWhoViewed,
        onTap: () => context.push('/patient/${patient.id}/audit'),
      ),
      // Spec A.7. The ten-minute QR needs a charged phone with a signal at the
      // moment somebody asks; this one needs neither.
      MoreRow(
        icon: Icons.badge_outlined,
        label: l10n.printedCardAction,
        onTap: () => context.push('/patient/${patient.id}/card'),
      ),
      if (isChild)
        MoreRow(
          icon: Icons.vaccines_outlined,
          label: l10n.childHealthAction,
          onTap: () => context.push('/patient/${patient.id}/child'),
        ),
      if (canRegister)
        MoreRow(
          icon: Icons.pregnant_woman_outlined,
          label: l10n.patientHomeRegisterPregnancy,
          onTap: () => context.push('/patient/${patient.id}/pregnancy/new'),
        ),
      MoreRow(
        icon: Icons.edit_outlined,
        label: l10n.moreEditDetails,
        onTap: () => context.push('/family/${patient.id}/edit'),
      ),
      // Tier 3. The record belongs to the patient, so it has to be able to
      // leave the app: a printed sheet works in a referral hospital with no
      // network, no account and no copy of this software.
      //
      // A button rather than a row because it does the work itself — it builds
      // the PDF and hands it to the platform share sheet — and has a busy state
      // a chevron row could not show.
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: ExportPdfButton(patient: patient),
      ),
    ];
  }
}
