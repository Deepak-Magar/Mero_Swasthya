import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ids/ids.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/delivery_complications.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';

/// S14 — Record delivery, which also closes the pregnancy.
///
/// Both rows go out in one transaction (see `PregnancyRepo.recordDelivery`):
/// the server must not be told a pregnancy ended before it hears about the
/// delivery that ended it.
class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key, required this.pregnancyId});

  final String pregnancyId;

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

/// The bilingual label for a complication code.
///
/// Unknown codes — from a newer build, or from a backend that grew its own
/// list — are shown as they arrived rather than hidden, because a value this
/// version does not recognise is still something a clinician wrote down.
String complicationLabel(L l10n, String code) => switch (code) {
      'PROLONGED_LABOUR' => l10n.deliveryComplicationProlongedLabour,
      'OBSTRUCTED_LABOUR' => l10n.deliveryComplicationObstructedLabour,
      'PPH' => l10n.deliveryComplicationPph,
      'RETAINED_PLACENTA' => l10n.deliveryComplicationRetainedPlacenta,
      'PERINEAL_TEAR' => l10n.deliveryComplicationPerinealTear,
      'ECLAMPSIA' => l10n.deliveryComplicationEclampsia,
      'SEPSIS' => l10n.deliveryComplicationSepsis,
      'CORD_PROLAPSE' => l10n.deliveryComplicationCordProlapse,
      _ => code,
    };

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  DateTime _deliveredAt = DateTime.now();
  DeliveryPlace _place = DeliveryPlace.birthingCentre;
  DeliveryMode _mode = DeliveryMode.normal;
  DeliveryOutcome _outcome = DeliveryOutcome.liveBirth;
  double? _babyWeight;
  Sex? _babySex;
  late TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now());
  final List<String> _complications = [];
  bool _busy = false;

  /// Spec S14 asks for "date/time". The BS picker gives the date in the
  /// calendar the mother's card is written in; the clock stays the ordinary
  /// system one, because that is what the wall clock in the room shows.
  DateTime get _deliveredAtWithTime => DateTime(
        _deliveredAt.year,
        _deliveredAt.month,
        _deliveredAt.day,
        _time.hour,
        _time.minute,
      );

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save(Pregnancy pregnancy) async {
    setState(() => _busy = true);

    try {
      await ref.read(pregnancyRepoProvider).recordDelivery(
            Delivery(
              id: newId(),
              pregnancyId: pregnancy.id,
              deliveredAt: _deliveredAtWithTime.toUtc().toIso8601String(),
              place: _place,
              mode: _mode,
              outcome: _outcome,
              // The stepper adds 0.1 at a time and binary floating point turns
              // that into 3.4000000000000004. Round it here so the row that is
              // stored and pushed is the number somebody actually read off the
              // scale.
              babyWeightKg: _babyWeight == null
                  ? null
                  : double.parse(_babyWeight!.toStringAsFixed(1)),
              babySex: _babySex,
              complications: List.of(_complications),
            ),
            pregnancy.copyWith(status: PregnancyStatus.delivered),
          );
      if (!mounted) return;
      showSavedSnackBar(context);
      context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final bundle = ref.watch(pregnancyBundleProvider(widget.pregnancyId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.deliveryTitle)),
      body: asyncView(
        bundle,
        data: (value) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            FormSection(
              title: l10n.deliveryAt,
              children: [
            BsDateField(
              label: l10n.deliveryAt,
              value: _deliveredAt,
              lastDate: DateTime.now(),
              onChanged: (picked) =>
                  setState(() => _deliveredAt = picked ?? DateTime.now()),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(
                '${l10n.deliveryTime}: '
                '${_time.hour.toString().padLeft(2, '0')}:'
                '${_time.minute.toString().padLeft(2, '0')}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                alignment: Alignment.centerLeft,
              ),
            ),
              ],
            ),
            FormSection(
              title: l10n.deliveryTitle,
              children: [
            _Choices<DeliveryPlace>(
              label: l10n.deliveryPlace,
              values: DeliveryPlace.values,
              selected: _place,
              labelOf: (value) => switch (value) {
                DeliveryPlace.home => l10n.deliveryPlaceHome,
                DeliveryPlace.birthingCentre =>
                  l10n.deliveryPlaceBirthingCentre,
                DeliveryPlace.hospital => l10n.deliveryPlaceHospital,
                DeliveryPlace.onTheWay => l10n.deliveryPlaceOnTheWay,
              },
              onChanged: (value) => setState(() => _place = value),
            ),
            _Choices<DeliveryMode>(
              label: l10n.deliveryMode,
              values: DeliveryMode.values,
              selected: _mode,
              labelOf: (value) => switch (value) {
                DeliveryMode.normal => l10n.deliveryModeNormal,
                DeliveryMode.assisted => l10n.deliveryModeAssisted,
                DeliveryMode.cs => l10n.deliveryModeCs,
              },
              onChanged: (value) => setState(() => _mode = value),
            ),
            _Choices<DeliveryOutcome>(
              label: l10n.deliveryOutcome,
              values: DeliveryOutcome.values,
              selected: _outcome,
              labelOf: (value) => switch (value) {
                DeliveryOutcome.liveBirth => l10n.deliveryOutcomeLive,
                DeliveryOutcome.stillbirth => l10n.deliveryOutcomeStill,
              },
              onChanged: (value) => setState(() => _outcome = value),
            ),
              ],
            ),
            FormSection(
              title: l10n.deliveryBabyLabel,
              children: [
            NumberStepper(
              label: l10n.deliveryBabyWeight,
              value: _babyWeight,
              min: 0.5,
              max: 6,
              step: 0.1,
              decimals: 1,
              onChanged: (value) =>
                  setState(() => _babyWeight = value?.toDouble()),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Choices<Sex>(
              label: l10n.deliveryBabySex,
              values: const [Sex.female, Sex.male],
              selected: _babySex,
              labelOf: (value) => value == Sex.female
                  ? l10n.patientFormSexFemale
                  : l10n.patientFormSexMale,
              onChanged: (value) => setState(() => _babySex = value),
            ),
              ],
            ),
            // Complications stay a wrap of filter chips rather than a
            // segmented control: several can be true at once, and nine of them
            // will not fit on one row in either language.
            FormSection(
              title: l10n.deliveryComplications,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final code in deliveryComplicationCodes)
                      FilterChip(
                        label: Text(complicationLabel(l10n, code)),
                        selected: _complications.contains(code),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _complications.add(code);
                          } else {
                            _complications.remove(code);
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: StickySaveBar(
        label: l10n.commonSave,
        busy: _busy,
        onPressed: () {
          final loaded = bundle.valueOrNull;
          if (loaded != null) _save(loaded.pregnancy);
        },
      ),
    );
  }
}

class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          // These are all mutually exclusive answers to one question with at
          // most four options, which is exactly what a segmented control says.
          SegmentedControl<T>(
            values: values,
            selected: selected,
            labelOf: labelOf,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
