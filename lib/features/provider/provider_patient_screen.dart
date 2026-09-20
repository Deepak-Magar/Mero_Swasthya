import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/anc_schedule.dart';
import '../../domain/rules/edd.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../patient_home/share_sheet.dart' show sectionLabel;
import '../reminders/prescription_actions.dart';
import '../shared/widgets/app_widgets.dart';

/// S21 — Provider patient summary: "ten-second read of what matters".
///
/// Everything here comes from the cached bundle, so it reads identically with
/// the network off. Allergies are first and in red, always.
class ProviderPatientScreen extends ConsumerWidget {
  const ProviderPatientScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final patient = ref.watch(patientProvider(patientId));
    final value = patient.valueOrNull;

    // A.7: a printed card grants `read` only. The write actions are removed
    // rather than disabled — a greyed "Add visit" invites a provider to keep
    // tapping it, and the banner above explains why there is nothing to tap.
    final readOnly =
        ref.watch(readOnlyAccessProvider(patientId)).valueOrNull ?? false;

    // A.4: a redeemed grant is good for 24 hours. The row stays on disk until
    // the next sync tidies it, so the screen has to check the window itself —
    // without this it went on showing the whole record, action bar and all, a
    // day after the code was scanned.
    final expired = ref.watch(grantExpiredProvider(patientId)).valueOrNull ??
        false;

    if (expired) {
      return Scaffold(
        appBar: AppBar(
          title: Text(value?.name ?? l10n.commonLoading),
          actions: const [SyncChip(), SizedBox(width: AppSpacing.sm)],
        ),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: EmptyState(
            icon: Icons.lock_clock_outlined,
            title: l10n.errorGrantExpired,
            body: l10n.providerScanHint,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(value?.name ?? l10n.commonLoading),
        actions: const [SyncChip(), SizedBox(width: AppSpacing.sm)],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Outside the scroll view on purpose: a provider who has scrolled
          // down to the medicines must not be able to forget that this record
          // cannot be written to.
          if (readOnly)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                0,
              ),
              child: ReadOnlyBanner(),
            ),
          Expanded(
            child: asyncView(
              patient,
              data: (value) => value == null
                  ? EmptyState(
                      icon: Icons.person_off_outlined,
                      title: l10n.errorNotFound,
                    )
                  : _Body(patient: value, readOnly: readOnly),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          value == null || readOnly ? null : _ActionBar(patient: value),
    );
  }
}

/// The sticky action bar along the bottom of S21.
///
/// Fixed rather than scrolled to: "Add visit" is what the provider came here to
/// do, and on a long record it would otherwise be four swipes below the fold
/// exactly when the patient is standing in front of them.
///
/// Absent entirely in read-only mode — see [ReadOnlyBanner].
class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final sections =
        ref.watch(grantSectionsProvider(patient.id)).valueOrNull ?? const [];
    bool shares(GrantSection s) => sections.isEmpty || sections.contains(s);

    final pregnancy = ref.watch(activePregnancyProvider(patient.id)).valueOrNull;

    // Spec S11: offered only when she is female and has no pregnancy open —
    // A.6 case 12, enforced in the UI as well as in the API.
    final canRegister = shares(GrantSection.pregnancy) &&
        patient.sex == Sex.female &&
        pregnancy == null;

    // Two buttons share this row, so each gets about half a phone minus the
    // icon. "Register pregnancy" does not fit on one line there and came out
    // as "Register pregn…" on the device; a second line costs nothing and is
    // the difference between a label and a guess.
    const secondaryStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, AppTheme.minTapTarget)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      ),
    );

    final secondary = <Widget>[
      if (shares(GrantSection.documents))
        OutlinedButton.icon(
          onPressed: () => context.push('/patient/${patient.id}/documents'),
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          style: secondaryStyle,
          label: Text(
            l10n.documentsCapture,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      if (canRegister)
        OutlinedButton.icon(
          onPressed: () => context.push('/patient/${patient.id}/pregnancy/new'),
          icon: const Icon(Icons.pregnant_woman_outlined, size: 18),
          style: secondaryStyle,
          label: Text(
            l10n.patientHomeRegisterPregnancy,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (secondary.isNotEmpty) ...[
                Row(
                  children: [
                    for (var i = 0; i < secondary.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(child: secondary[i]),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton.icon(
                onPressed: () =>
                    context.push('/provider/patient/${patient.id}/visit/new'),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.providerAddVisit),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.patient, required this.readOnly});

  final Patient patient;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);
    // Tier 3 fine-grained consent. Empty means the whole record — an owned
    // patient, or a grant issued before this existed. The server has already
    // withheld the content; this is what stops the screen showing an empty
    // section and letting the provider think the record is blank.
    final sections =
        ref.watch(grantSectionsProvider(patient.id)).valueOrNull ?? const [];
    bool shares(GrantSection s) => sections.isEmpty || sections.contains(s);
    final visits = ref.watch(visitsProvider(patient.id)).valueOrNull ?? const [];
    final pregnancy = ref.watch(activePregnancyProvider(patient.id)).valueOrNull;
    final dob = BsDate.parseAd(patient.dob);
    final latest = visits.isEmpty ? null : visits.first;

    final facts = [
      if (dob != null) l10n.patientHomeAge(BsDate.ageInYears(dob)),
      patient.sex.wire,
      if (patient.bloodGroup != null) patient.bloodGroup!,
    ].join('  ·  ');

    return CustomScrollView(
      slivers: [
        // Spec §16: "allergies in a red chip row at the top, always". Pinned,
        // so scrolling down to read the medicines cannot take the one fact off
        // the screen that decides whether those medicines are safe.
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedAllergies(
            allergies: patient.allergies,
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          sliver: SliverList.list(
            children: [
              if (sections.isNotEmpty) ...[
                _SharedSectionsLine(sections: sections),
                const SizedBox(height: AppSpacing.lg),
              ],

              // The identity cluster: three facts about one person, 4 px apart.
              Text(patient.name, style: text.headlineMedium),
              const SizedBox(height: AppSpacing.tight),
              Text(
                facts,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),

              if (shares(GrantSection.summary) &&
                  patient.chronicConditions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                _Section(
                  title: l10n.providerActiveProblems,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final code in patient.chronicConditions)
                        SoftPill(label: code),
                    ],
                  ),
                ),
              ],

              if (shares(GrantSection.visits) &&
                  (latest?.prescriptions.isNotEmpty ?? false)) ...[
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: l10n.providerCurrentMedicines,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final rx in latest!.prescriptions)
                        _MedicineRow(prescription: rx),
                      const SizedBox(height: AppSpacing.sm),
                      PrescriptionActions(
                        patientId: patient.id,
                        prescriptions: latest.prescriptions,
                      ),
                    ],
                  ),
                ),
              ],

              if (shares(GrantSection.summary) && latest?.vitals != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: l10n.providerLastVitals,
                  child: _VitalsGrid(
                    vitals: latest!.vitals!,
                    takenAt: latest.visitAt,
                  ),
                ),
              ],

              if (shares(GrantSection.pregnancy) && pregnancy != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _PregnancySection(pregnancy: pregnancy, readOnly: readOnly),
              ],

              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: () => context.push('/patient/${patient.id}/timeline'),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: Text(l10n.patientHomeTimeline),
              ),

              if (auth.user?.role == UserRole.fchv) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.visitFchvNoPrescribing,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The pinned allergy row.
///
/// It paints the page's own background rather than a white card, so that when
/// it sticks it reads as part of the chrome rather than as a card that has
/// stopped scrolling. The height is fixed because a sliver header has to
/// declare one; two lines of chips is the realistic worst case and the row
/// wraps inside that.
class _PinnedAllergies extends SliverPersistentHeaderDelegate {
  const _PinnedAllergies({required this.allergies, required this.background});

  final List<String> allergies;
  final Color background;

  static const double _height = 68;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _height,
      color: background,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: AllergyChipRow(allergies: allergies, singleLine: true),
    );
  }

  @override
  bool shouldRebuild(_PinnedAllergies old) =>
      old.allergies != allergies || old.background != background;
}

/// One prescribed medicine.
///
/// The Nepali instruction goes underneath in [AppColors.textSecondaryOf(context)] rather
/// than inline after three separators: it is the line the *patient* is read
/// back, and it has to be findable without parsing a dot-separated string.
class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.prescription});

  final Prescription prescription;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rx = prescription;
    final name = rx.drugName.isEmpty ? rx.drugCode : rx.drugName;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${rx.dose} · ${rx.frequency.wire} · ${rx.durationDays}d',
                  style: text.bodySmall,
                ),
                if (rx.instructionsNp != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    rx.instructionsNp!,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Tier 2: a dose that is only written down is no use to somebody who
          // cannot read it.
          SpeakPrescriptionButton(prescription: rx),
        ],
      ),
    );
  }
}

/// Last vitals as a grid of number tiles rather than a dot-separated line.
///
/// A provider scanning for "is the BP high" reads a column of figures far
/// faster than a sentence, and a missing measurement is then visibly missing
/// rather than silently absent from a run-on string.
class _VitalsGrid extends StatelessWidget {
  const _VitalsGrid({required this.vitals, required this.takenAt});

  final Vitals vitals;
  final String takenAt;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final v = vitals;

    final tiles = <Widget>[
      if (v.bpSys != null && v.bpDia != null)
        StatTile(
          label: 'BP',
          value: '${v.bpSys}/${v.bpDia}',
          unit: 'mmHg',
          icon: Icons.monitor_heart_outlined,
        ),
      if (v.pulse != null)
        StatTile(
          label: l10n.visitPulse,
          value: '${v.pulse}',
          unit: 'bpm',
          icon: Icons.favorite_border_rounded,
        ),
      if (v.tempC != null)
        StatTile(
          label: l10n.visitTemperature,
          value: '${v.tempC}',
          icon: Icons.thermostat_outlined,
        ),
      if (v.weightKg != null)
        StatTile(
          label: l10n.ancWeight,
          value: '${v.weightKg}',
          icon: Icons.monitor_weight_outlined,
        ),
      if (v.spo2 != null)
        StatTile(
          label: l10n.visitSpo2,
          value: '${v.spo2}',
          unit: '%',
          icon: Icons.air_rounded,
        ),
    ];

    // Two columns, so a long Devanagari label has room to wrap rather than
    // ellipsing away the word that says what the number is.
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        const SizedBox(height: AppSpacing.md),
        BsDateText(takenAt, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PregnancySection extends ConsumerWidget {
  const _PregnancySection({required this.pregnancy, this.readOnly = false});

  final Pregnancy pregnancy;

  /// A printed-card redemption. The card says in as many words that nothing
  /// can be added through it, and the action bar is already withheld — but
  /// this section still offered "ANC contact 4", which opened the full form
  /// with a live Save button. Read-only has to mean the whole screen.
  final bool readOnly;

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

    return _Section(
      title: l10n.providerActivePregnancy,
      onTap: () => context.push('/pregnancy/${pregnancy.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  week == null ? '' : l10n.pregnancyWeekOf(week),
                  style: text.titleMedium,
                ),
              ),
              if (lastDone?.triageLevel != null)
                TriageDot(level: lastDone!.triageLevel),
            ],
          ),
          if (next != null) ...[
            FactRow(
              label: l10n.pregnancyContactNumber(next.contactNo),
              value: BsDateText(
                next.dueAt,
                showAd: false,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            if (!readOnly) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: () => context.push(
                  '/pregnancy/${pregnancy.id}/contact/${next.contactNo}',
                ),
                child: Text(l10n.ancContactTitle(next.contactNo)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One titled card on S21 and the Tier 2 screens that follow its shape.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onTap});

  final String title;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: SectionHeader(title, padding: EdgeInsets.zero)),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondaryOf(context),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// "Patient shared: summary, pregnancy".
///
/// Shown only when the grant is narrower than the whole record. It exists so a
/// provider looking at a short screen knows they are seeing a *choice* rather
/// than an empty record — the difference between "she has no pregnancy" and
/// "she did not share it" matters.
class _SharedSectionsLine extends StatelessWidget {
  const _SharedSectionsLine({required this.sections});

  final List<GrantSection> sections;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final names = sections.map((s) => sectionLabel(l10n, s)).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.privacy_tip_outlined,
          size: 16,
          color: AppColors.textSecondaryOf(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            l10n.providerSharedSections(names),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
