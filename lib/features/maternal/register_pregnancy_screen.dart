import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/ids/ids.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/anc_schedule.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/rules.dart';
import '../../domain/rules/triage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';

/// S11 — Register a pregnancy.
///
/// The eight ANC contacts are generated here, locally, with the deterministic
/// ids from A.8.15, so the checklist exists the moment the form is saved. Only
/// the pregnancy is pushed; the server creates its own eight and they land on
/// the same rows.
class RegisterPregnancyScreen extends ConsumerStatefulWidget {
  const RegisterPregnancyScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<RegisterPregnancyScreen> createState() =>
      _RegisterPregnancyScreenState();
}

class _RegisterPregnancyScreenState
    extends ConsumerState<RegisterPregnancyScreen> {
  DateTime? _lmp;
  DateTime? _edd;
  int _gravida = 1;
  int _para = 0;
  final List<String> _riskFactors = [];
  bool _busy = false;
  String? _error;

  /// Spec S11: LMP *or* EDD. Entering either fills the other in live, because a
  /// woman who knows her last period should not have to compute a due date.
  DateTime? get _effectiveEdd =>
      _edd ?? (_lmp == null ? null : eddFromLmp(_lmp!));

  Future<void> _register() async {
    final l10n = L.of(context);
    final edd = _effectiveEdd;
    if (edd == null) {
      setState(() => _error = l10n.pregnancyNeedsDate);
      return;
    }

    final rules = ref.read(rulesProvider).valueOrNull;
    if (rules == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final pregnancy = Pregnancy(
      id: newId(),
      patientId: widget.patientId,
      lmp: _lmp == null ? null : BsDate.formatAd(_lmp!),
      edd: BsDate.formatAd(edd),
      gravida: _gravida,
      para: _para,
      riskFactors: _riskFactors,
      riskLevel: riskLevelFor(_riskFactors),
      registeredByUserId: '',
    );

    try {
      await ref.read(pregnancyRepoProvider).register(
            pregnancy,
            generateContacts(pregnancy, rules),
          );
      if (!mounted) return;
      showSaveResult(
        ScaffoldMessenger.of(context),
        L.of(context),
        ref.read(databaseProvider),
        rowId: pregnancy.id,
      );
      context.pushReplacement('/pregnancy/${pregnancy.id}');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final rules = ref.watch(rulesProvider);
    final nepali = Localizations.localeOf(context).languageCode == 'ne';
    final edd = _effectiveEdd;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pregnancyRegisterTitle)),
      body: asyncView(
        rules,
        data: (loaded) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            FormSection(
              title: l10n.pregnancyRegisterTitle,
              children: [
            BsDateField(
              label: l10n.pregnancyLmp,
              value: _lmp,
              lastDate: DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 300)),
              onChanged: (value) => setState(() {
                _lmp = value;
                _edd = null;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            BsDateField(
              label: l10n.pregnancyEdd,
              value: edd,
              firstDate: DateTime.now().subtract(const Duration(days: 30)),
              lastDate: DateTime.now().add(const Duration(days: 300)),
              errorText: _error,
              onChanged: (value) => setState(() {
                _edd = value;
                _error = null;
              }),
            ),
            if (edd != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 18,
                    color: AppColors.successInkOf(context),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.pregnancyEddComputed(
                        BsDate.formatBoth(edd, nepaliDigits: nepali),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.onTriageGreen,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            // Gravida and para side by side: they are one fact about her
            // obstetric history, always entered together, and two full-width
            // rows for two small integers is a waste of a screen.
            StepperGrid(
              children: [
                NumberStepper(
                  layout: NumberStepperLayout.stacked,
                  label: l10n.pregnancyGravida,
                  value: _gravida,
                  min: 1,
                  max: 15,
                  onChanged: (value) =>
                      setState(() => _gravida = (value ?? 1).toInt()),
                ),
                NumberStepper(
                  layout: NumberStepperLayout.stacked,
                  label: l10n.pregnancyPara,
                  value: _para,
                  max: 15,
                  onChanged: (value) =>
                      setState(() => _para = (value ?? 0).toInt()),
                ),
              ],
            ),
              ],
            ),

            FormSection(
              title: l10n.pregnancyRiskFactors,
              children: [
                for (final factor in loaded.riskFactors)
                  CheckboxListTile(
                    value: _riskFactors.contains(factor.code),
                    title: Text(
                      nepali ? factor.np : factor.en,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    subtitle: nepali
                        ? Text(
                            factor.en,
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _riskFactors.add(factor.code);
                      } else {
                        _riskFactors.remove(factor.code);
                      }
                    }),
                  ),
              ],
            ),

            _SchedulePreview(edd: edd, rules: loaded),
            FilledButton(
              onPressed: _busy ? null : _register,
              child: Text(l10n.pregnancyRegister),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the eight dates before anything is saved, so a health worker can sanity
/// check the LMP she just entered against what it implies.
class _SchedulePreview extends StatelessWidget {
  const _SchedulePreview({required this.edd, required this.rules});

  final DateTime? edd;
  final Rules rules;

  @override
  Widget build(BuildContext context) {
    if (edd == null) return const SizedBox.shrink();

    final preview = generateContacts(
      Pregnancy(id: 'preview', patientId: '', edd: BsDate.formatAd(edd!)),
      rules,
    );

    final l10n = L.of(context);

    return FormSection(
      title: l10n.pregnancyDashboardTitle,
      children: [
        for (final contact in preview)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.tight),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    l10n.pregnancyContactWeek(contact.weekTarget),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                  ),
                ),
                Expanded(
                  child: BsDateText(
                    contact.dueAt,
                    showAd: false,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
