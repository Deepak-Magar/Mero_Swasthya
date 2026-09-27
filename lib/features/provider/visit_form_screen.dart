import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/ids/ids.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../shared/voice/voice_note_button.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';

/// S22 — Add visit, the 60-second form.
///
/// Everything is a picklist or a stepper: spec §16 says never require typing
/// for vitals, and a provider with sixty patients a day will not type a
/// diagnosis. The save is local-then-outbox, so it returns instantly.
class VisitFormScreen extends ConsumerStatefulWidget {
  const VisitFormScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  CodeListItem? _complaint;
  List<CodeListItem> _diagnoses = [];
  Vitals _vitals = const Vitals();
  final List<Prescription> _prescriptions = [];
  final _notes = TextEditingController();
  final _advice = TextEditingController();
  DateTime? _followUp;
  bool _referring = false;
  Facility? _referralFacility;
  final _referralReason = TextEditingController();
  ReferralUrgency _urgency = ReferralUrgency.routine;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    _advice.dispose();
    _referralReason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = L.of(context);
    if (_complaint == null) {
      setState(() => _error = l10n.visitNeedsComplaint);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final visit = Visit(
      id: newId(),
      patientId: widget.patientId,
      visitAt: DateTime.now().toUtc().toIso8601String(),
      chiefComplaintCode: _complaint!.code,
      vitals: _vitals,
      diagnosisCodes: _diagnoses.map((d) => d.code).toList(),
      notes: _text(_notes),
      advice: _text(_advice),
      followUpAt: _followUp == null ? null : BsDate.formatAd(_followUp!),
      referral: _referring && _referralFacility != null
          ? Referral(
              facilityId: _referralFacility!.id,
              facilityName: _referralFacility!.name,
              reason: _text(_referralReason) ?? _complaint!.labelEn,
              urgency: _urgency,
            )
          : null,
      prescriptions: List.of(_prescriptions),
    );

    try {
      await ref.read(visitRepoProvider).add(visit);
      if (!mounted) return;
      // Spec §16: pop first, then report; the row is already durable.
      showSaveResult(
        ScaffoldMessenger.of(context),
        L.of(context),
        ref.read(databaseProvider),
        rowId: visit.id,
      );
      context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  String? _text(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final nepali = Localizations.localeOf(context).languageCode == 'ne';
    final auth = ref.watch(authProvider);
    // Spec S22: an FCHV records the visit but cannot prescribe.
    final canPrescribe = auth.user?.role == UserRole.provider;

    String labelOf(CodeListItem item) => nepali ? item.labelNp : item.labelEn;

    final complaints =
        ref.watch(codelistProvider(CodeListKind.complaint)).valueOrNull ??
            const <CodeListItem>[];
    final diagnoses =
        ref.watch(codelistProvider(CodeListKind.diagnosis)).valueOrNull ??
            const <CodeListItem>[];
    final facilities = ref.watch(facilitiesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visitTitle),
        actions: const [SyncPill.compact(), SizedBox(width: AppSpacing.sm)],
      ),
      // Sticky, because this form is seven sections long and a provider with a
      // patient in front of them should never have to scroll to finish.
      bottomNavigationBar: StickySaveBar(
        label: l10n.commonSave,
        busy: _busy,
        onPressed: _save,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.lg,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          // --- Complaint -----------------------------------------------
          FormSection(
            title: l10n.visitChiefComplaint,
            helper: l10n.visitChiefComplaintHelper,
            children: [
              PicklistField<CodeListItem>(
                label: l10n.visitChiefComplaint,
                options: complaints,
                selected: _complaint == null ? const [] : [_complaint!],
                labelOf: labelOf,
                onChanged: (value) => setState(() {
                  _complaint = value.isEmpty ? null : value.first;
                  _error = null;
                }),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.dangerInkOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),

          // --- Vitals ---------------------------------------------------
          //
          // Two columns of large steppers. Spec §16: never require typing for
          // vitals, and a grid puts twice as many of them above the fold as a
          // column of full-width rows does.
          FormSection(
            title: l10n.visitVitals,
            helper: l10n.visitVitalsHelper,
            children: [
              StepperGrid(
                children: [
                  NumberStepper(
                    layout: NumberStepperLayout.stacked,
                    label: l10n.ancBpSys,
                    value: _vitals.bpSys,
                    min: 60,
                    max: 250,
                    step: 2,
                    onChanged: (value) => setState(
                      () => _vitals = _vitals.copyWith(bpSys: value?.toInt()),
                    ),
                  ),
                  NumberStepper(
                    layout: NumberStepperLayout.stacked,
                    label: l10n.ancBpDia,
                    value: _vitals.bpDia,
                    min: 30,
                    max: 160,
                    step: 2,
                    onChanged: (value) => setState(
                      () => _vitals = _vitals.copyWith(bpDia: value?.toInt()),
                    ),
                  ),
                  NumberStepper(
                    layout: NumberStepperLayout.stacked,
                    label: l10n.visitPulse,
                    value: _vitals.pulse,
                    min: 30,
                    max: 220,
                    onChanged: (value) => setState(
                      () => _vitals = _vitals.copyWith(pulse: value?.toInt()),
                    ),
                  ),
                  NumberStepper(
                    layout: NumberStepperLayout.stacked,
                    label: l10n.visitTemperature,
                    value: _vitals.tempC,
                    min: 34,
                    max: 43,
                    step: 0.1,
                    decimals: 1,
                    onChanged: (value) => setState(
                      () => _vitals = _vitals.copyWith(tempC: value?.toDouble()),
                    ),
                  ),
                  NumberStepper(
                    layout: NumberStepperLayout.stacked,
                    label: l10n.ancWeight,
                    value: _vitals.weightKg,
                    min: 2,
                    max: 200,
                    step: 0.5,
                    decimals: 1,
                    onChanged: (value) => setState(
                      () =>
                          _vitals = _vitals.copyWith(weightKg: value?.toDouble()),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // --- Diagnoses ------------------------------------------------
          FormSection(
            title: l10n.visitDiagnoses,
            helper: l10n.visitDiagnosesHelper,
            children: [
              PicklistField<CodeListItem>(
                label: l10n.visitDiagnoses,
                options: diagnoses,
                selected: _diagnoses,
                multi: true,
                labelOf: labelOf,
                onChanged: (value) => setState(() => _diagnoses = value),
              ),
            ],
          ),

          // --- Medicines -------------------------------------------------
          if (canPrescribe)
            _PrescriptionSection(
              prescriptions: _prescriptions,
              labelOf: labelOf,
              onChanged: (value) => setState(() {
                _prescriptions
                  ..clear()
                  ..addAll(value);
              }),
            ),

          // --- Advice ----------------------------------------------------
          FormSection(
            title: l10n.visitAdvice,
            helper: l10n.visitAdviceHelper,
            children: [
              TextField(
                controller: _advice,
                maxLines: 2,
                decoration: InputDecoration(labelText: l10n.visitAdvice),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(
                  // Not `visitAdvice`: this writes `notes`, and labelling it
                  // "Advice" put two identical labels one above the other in
                  // the same card, with no way to tell which was which.
                  labelText: l10n.ancNotes,
                  // Tier 3: dictate in Nepali. The transcript lands in this
                  // field and stays editable — nothing is saved unread.
                  suffixIcon: VoiceNoteButton(controller: _notes),
                ),
              ),
            ],
          ),

          // --- Follow-up --------------------------------------------------
          FormSection(
            title: l10n.visitFollowUp,
            children: [
              BsDateField(
                label: l10n.visitFollowUp,
                value: _followUp,
                firstDate: DateTime.now(),
                onChanged: (value) => setState(() => _followUp = value),
              ),
            ],
          ),

          // --- Referral ----------------------------------------------------
          FormSection(
            title: l10n.visitReferral,
            children: [
              SwitchListTile(
                value: _referring,
                title: Text(
                  l10n.visitReferral,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: (value) => setState(() => _referring = value),
              ),
              if (_referring) ...[
                const SizedBox(height: AppSpacing.md),
                PicklistField<Facility>(
                  label: l10n.visitReferralFacility,
                  options: facilities,
                  selected: _referralFacility == null
                      ? const []
                      : [_referralFacility!],
                  labelOf: (f) => f.name,
                  onChanged: (value) => setState(
                    () => _referralFacility = value.isEmpty ? null : value.first,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _referralReason,
                  decoration:
                      InputDecoration(labelText: l10n.ancReferralReason),
                ),
                const SizedBox(height: AppSpacing.lg),
                SegmentedControl<ReferralUrgency>(
                  values: ReferralUrgency.values,
                  selected: _urgency,
                  labelOf: (urgency) => switch (urgency) {
                    ReferralUrgency.routine => l10n.visitUrgencyRoutine,
                    ReferralUrgency.urgent => l10n.visitUrgencyUrgent,
                  },
                  onChanged: (value) => setState(() => _urgency = value),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PrescriptionSection extends ConsumerWidget {
  const _PrescriptionSection({
    required this.prescriptions,
    required this.labelOf,
    required this.onChanged,
  });

  final List<Prescription> prescriptions;
  final String Function(CodeListItem) labelOf;
  final ValueChanged<List<Prescription>> onChanged;

  /// Spec S22: the three Nepali instruction chips a provider actually uses.
  static const List<String> instructionChips = [
    'खाना पछि',
    'खाना अघि',
    'सुत्ने बेला',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final drugs = ref.watch(codelistProvider(CodeListKind.drug)).valueOrNull ??
        const <CodeListItem>[];

    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            l10n.visitMedicines,
            helper: l10n.visitMedicinesHelper,
          ),
          // Each medicine is its own card rather than a row in a shared one:
          // they are added and removed one at a time, and a card that can be
          // deleted should look like a discrete object.
          for (final rx in prescriptions)
            SoftCard(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rx.drugName.isEmpty ? rx.drugCode : rx.drugName,
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${rx.dose} · ${rx.frequency.wire} · '
                          '${rx.durationDays}d',
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
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.commonRemove,
                    onPressed: () => onChanged(
                      prescriptions.where((p) => p.id != rx.id).toList(),
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              final added = await showModalBottomSheet<Prescription>(
                context: context,
                isScrollControlled: true,
                builder: (context) =>
                    _PrescriptionSheet(drugs: drugs, labelOf: labelOf),
              );
              if (added != null) onChanged([...prescriptions, added]);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l10n.visitAddMedicine),
          ),
        ],
      ),
    );
  }
}

class _PrescriptionSheet extends StatefulWidget {
  const _PrescriptionSheet({required this.drugs, required this.labelOf});

  final List<CodeListItem> drugs;
  final String Function(CodeListItem) labelOf;

  @override
  State<_PrescriptionSheet> createState() => _PrescriptionSheetState();
}

class _PrescriptionSheetState extends State<_PrescriptionSheet> {
  CodeListItem? _drug;
  final _dose = TextEditingController(text: '1 tab');
  PrescriptionFrequency _frequency = PrescriptionFrequency.bd;
  int _days = 5;
  String? _instruction;

  @override
  void dispose() {
    _dose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        top: AppSpacing.sm,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(l10n.visitAddMedicine),
            PicklistField<CodeListItem>(
              label: l10n.visitDrug,
              options: widget.drugs,
              selected: _drug == null ? const [] : [_drug!],
              labelOf: widget.labelOf,
              onChanged: (value) =>
                  setState(() => _drug = value.isEmpty ? null : value.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _dose,
              decoration: InputDecoration(labelText: l10n.visitDose),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Six frequencies as one segmented control: they are mutually
            // exclusive and always the same six, which is exactly what a
            // segmented control says and a row of loose chips does not.
            SectionHeader(
              l10n.visitFrequency,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            SegmentedControl<PrescriptionFrequency>(
              values: PrescriptionFrequency.values,
              selected: _frequency,
              labelOf: (frequency) => frequency.wire,
              onChanged: (value) => setState(() => _frequency = value),
            ),
            const SizedBox(height: AppSpacing.xl),
            NumberStepper(
              label: l10n.visitDurationDays,
              value: _days,
              min: 1,
              max: 90,
              onChanged: (value) =>
                  setState(() => _days = (value ?? 1).toInt()),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              l10n.visitInstructions,
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final chip in _PrescriptionSection.instructionChips)
                  ChoiceChip(
                    label: Text(chip),
                    selected: _instruction == chip,
                    onSelected: (selected) =>
                        setState(() => _instruction = selected ? chip : null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _drug == null
                  ? null
                  : () => Navigator.of(context).pop(
                        Prescription(
                          id: newId(),
                          drugCode: _drug!.code,
                          drugName: widget.labelOf(_drug!),
                          dose: _dose.text.trim(),
                          frequency: _frequency,
                          durationDays: _days,
                          instructionsNp: _instruction,
                        ),
                      ),
              child: Text(l10n.commonAdd),
            ),
          ],
        ),
      ),
    );
  }
}
