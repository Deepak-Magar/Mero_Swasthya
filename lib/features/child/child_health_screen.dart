import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/epi_schedule.dart';
import '../auth/auth_controller.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';
import 'growth_chart.dart';

/// Tier 3 — the child's immunisation card and growth chart.
///
/// The immunisation half is a *schedule*, not a log: every dose exists as a row
/// from the day the child is registered, so the question "what is this child
/// missing" is answered by looking rather than by remembering. That is why an
/// ungiven dose is a first-class row and why overdue is its own colour.
class ChildHealthScreen extends ConsumerStatefulWidget {
  const ChildHealthScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<ChildHealthScreen> createState() => _ChildHealthScreenState();
}

class _ChildHealthScreenState extends ConsumerState<ChildHealthScreen> {
  bool _generating = false;

  /// Create the schedule the first time somebody opens this screen for a child
  /// who does not have one yet.
  ///
  /// Doing it here rather than only at registration means the existing seeded
  /// under-fives — and anybody added before this feature shipped — get a card
  /// without a migration.
  Future<void> _ensureSchedule(Patient patient) async {
    if (_generating) return;
    final dob = BsDate.parseAd(patient.dob);
    if (dob == null || !isUnderFive(dob)) return;

    final epi = ref.read(epiScheduleProvider).valueOrNull;
    if (epi == null) return;

    _generating = true;
    try {
      await ref.read(childHealthRepoProvider).ensureSchedule(
            patientId: patient.id,
            dob: dob,
            epi: epi,
          );
    } finally {
      _generating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final patient = ref.watch(patientProvider(widget.patientId)).valueOrNull;
    final schedule =
        ref.watch(immunisationScheduleProvider(widget.patientId)).valueOrNull ??
            const <Immunisation>[];

    // Watched, not read: the asset resolves a frame or two after the screen
    // opens, and the schedule has to be generated once it has.
    ref.watch(epiScheduleProvider);
    if (patient != null && schedule.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureSchedule(patient);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.childHealthTitle),
        actions: const [SyncChip()],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: patient == null
                ? Center(child: Text(l10n.commonLoading))
                : _Body(patient: patient, schedule: schedule),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.patient, required this.schedule});

  final Patient patient;
  final List<Immunisation> schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final dob = BsDate.parseAd(patient.dob);

    if (dob == null || !isUnderFive(dob)) {
      return EmptyState(
        icon: Icons.child_care_outlined,
        title: l10n.childNotAChild,
      );
    }

    final months = ageInMonths(dob, DateTime.now());
    final progress = immunisationProgress(schedule);
    final measurements =
        ref.watch(growthMeasurementsProvider(patient.id)).valueOrNull ??
            const <GrowthMeasurement>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        40,
      ),
      children: [
        SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  months < 24
                      ? l10n.childAgeMonths(months)
                      : l10n.childAgeYears(months ~/ 12),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                ),
                if (schedule.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress.total == 0
                        ? 0
                        : progress.given / progress.total,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.childProgress(progress.given, progress.total),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.xl),
        SectionHeader(l10n.childImmunisations),
        // The asset has not been checked against a current Ministry
        // publication, and a health worker reading this card deserves to know
        // that before they act on it.
        _Caveat(text: l10n.childScheduleUnverified),
        const SizedBox(height: 8),

        if (schedule.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final dose in schedule)
            _DoseTile(patient: patient, dose: dose),

        const SizedBox(height: 24),
        Text(
          l10n.childGrowth,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        GrowthChartCard(patient: patient, measurements: measurements),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => showAddMeasurementSheet(context, patient),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.childAddMeasurement),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ],
    );
  }
}

/// A one-line "do not trust this yet" note.
class _Caveat extends StatelessWidget {
  const _Caveat({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 15, color: TriageColors.amber),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: TriageColors.amber),
          ),
        ),
      ],
    );
  }
}

class _DoseTile extends ConsumerWidget {
  const _DoseTile({required this.patient, required this.dose});

  final Patient patient;
  final Immunisation dose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final status = statusOf(dose);
    final epi = ref.watch(epiScheduleProvider).valueOrNull;
    final vaccine = epi?.vaccine(dose.vaccineCode);
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    final label = vaccine == null
        ? dose.vaccineCode
        : (nepali ? vaccine.labelNp : vaccine.labelEn);

    final text = Theme.of(context).textTheme;

    final (colour, statusText) = switch (status) {
      DoseStatus.given => (AppColors.successInkOf(context), l10n.childDoseGiven),
      DoseStatus.due => (AppColors.triageAmber, l10n.childDoseDue),
      DoseStatus.overdue => (AppColors.dangerInkOf(context), l10n.childDoseOverdue),
      DoseStatus.upcoming => (AppColors.textSecondaryOf(context), l10n.childDoseUpcoming),
    };

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      // Spec §16's rule, applied here too: overdue gets a coloured edge as well
      // as a colour, so it is findable while scrolling and survives a
      // colour-vision deficiency.
      accent: status == DoseStatus.overdue ? AppColors.triageRed : null,
      padding: EdgeInsets.fromLTRB(
        status == DoseStatus.overdue ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      onTap: () => showRecordDoseSheet(context, patient, dose, label),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (status) {
              DoseStatus.given => Icons.check_circle_outline,
              DoseStatus.overdue => Icons.error_outline,
              DoseStatus.due => Icons.schedule_rounded,
              DoseStatus.upcoming => Icons.circle_outlined,
            },
            size: 20,
            color: colour,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${l10n.childDoseNumber(dose.doseNo)}',
                  style: text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.tight),
                Row(
                  children: [
                    Text(
                      statusText,
                      style: text.bodySmall?.copyWith(
                        color: colour,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(' · ', style: text.bodySmall),
                    Flexible(
                      child: BsDateText(
                        dose.givenAt ?? dose.dueAt,
                        showAd: false,
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PendingDot(rowId: dose.id),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }
}

/// "Record dose" — a date, a batch number, and nothing else.
Future<void> showRecordDoseSheet(
  BuildContext context,
  Patient patient,
  Immunisation dose,
  String vaccineLabel,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordDoseSheet(
      patient: patient,
      dose: dose,
      vaccineLabel: vaccineLabel,
    ),
  );
}

class _RecordDoseSheet extends ConsumerStatefulWidget {
  const _RecordDoseSheet({
    required this.patient,
    required this.dose,
    required this.vaccineLabel,
  });

  final Patient patient;
  final Immunisation dose;
  final String vaccineLabel;

  @override
  ConsumerState<_RecordDoseSheet> createState() => _RecordDoseSheetState();
}

class _RecordDoseSheetState extends ConsumerState<_RecordDoseSheet> {
  late DateTime _givenAt =
      DateTime.tryParse(widget.dose.givenAt ?? '') ?? DateTime.now();
  late final _batch = TextEditingController(text: widget.dose.batchNo ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _batch.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(childHealthRepoProvider).recordDose(
            widget.dose,
            givenAt: _givenAt,
            batchNo: _batch.text,
            givenByUserId: ref.read(authProvider).user?.id,
          );
      if (!mounted) return;
      showSavedSnackBar(context);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await ref.read(childHealthRepoProvider).clearDose(widget.dose);
      if (!mounted) return;
      showSavedSnackBar(context);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final alreadyGiven = widget.dose.givenAt != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.vaccineLabel} · ${l10n.childDoseNumber(widget.dose.doseNo)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            BsDateField(
              label: l10n.childGivenOn,
              value: _givenAt,
              // A dose cannot have been given tomorrow.
              lastDate: DateTime.now(),
              onChanged: (picked) =>
                  setState(() => _givenAt = picked ?? DateTime.now()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _batch,
              decoration: InputDecoration(labelText: l10n.childBatchNo),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(l10n.childRecordDose),
            ),
            if (alreadyGiven) ...[
              const SizedBox(height: 8),
              // A dose recorded against the wrong child is a thing that
              // happens, and the alternative is a row nobody can correct.
              TextButton(
                onPressed: _busy ? null : _clear,
                child: Text(l10n.childClearDose),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
