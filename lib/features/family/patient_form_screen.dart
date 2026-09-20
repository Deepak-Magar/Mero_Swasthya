import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/ids/ids.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../auth/auth_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';

/// S07 — Add / edit a family profile.
///
/// Entirely offline: the id is generated here, the row and its outbox op are
/// written together, and the screen pops immediately. Nothing waits on a
/// server, because in a village there may not be one for hours.
class PatientFormScreen extends ConsumerStatefulWidget {
  const PatientFormScreen({super.key, this.patientId});

  final String? patientId;

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ward = TextEditingController();
  final _municipality = TextEditingController();
  final _phone = TextEditingController();
  final _allergy = TextEditingController();

  Sex _sex = Sex.female;
  DateTime? _dob;
  String? _bloodGroup;
  List<String> _allergies = [];
  List<CodeListItem> _chronic = [];
  bool _loaded = false;
  bool _busy = false;
  String? _dobError;

  static const List<String> _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-',
  ];

  bool get _isEdit => widget.patientId != null;

  @override
  void dispose() {
    _name.dispose();
    _ward.dispose();
    _municipality.dispose();
    _phone.dispose();
    _allergy.dispose();
    super.dispose();
  }

  void _hydrate(Patient patient, List<CodeListItem> diagnoses) {
    if (_loaded) return;
    _loaded = true;

    _name.text = patient.name;
    _ward.text = patient.ward?.toString() ?? '';
    _municipality.text = patient.municipality ?? '';
    _phone.text = patient.emergencyContactPhone ?? '';
    _sex = patient.sex;
    _dob = BsDate.parseAd(patient.dob);
    _bloodGroup = patient.bloodGroup;
    _allergies = [...patient.allergies];
    _chronic = diagnoses
        .where((d) => patient.chronicConditions.contains(d.code))
        .toList();
  }

  Future<void> _save() async {
    final l10n = L.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_dob == null) {
      setState(() => _dobError = l10n.patientFormDobRequired);
      return;
    }
    if (_dob!.isAfter(DateTime.now())) {
      setState(() => _dobError = l10n.patientFormDobFuture);
      return;
    }

    setState(() {
      _busy = true;
      _dobError = null;
    });

    final repo = ref.read(patientRepoProvider);
    final existing =
        _isEdit ? await repo.findById(widget.patientId!) : null;

    final patient = Patient(
      id: existing?.id ?? newId(),
      ownerUserId: existing?.ownerUserId ?? ref.read(authProvider).user!.id,
      name: _name.text.trim(),
      sex: _sex,
      dob: BsDate.formatAd(_dob!),
      bloodGroup: _bloodGroup,
      ward: int.tryParse(_ward.text.trim()),
      municipality: _municipality.text.trim().isEmpty
          ? null
          : _municipality.text.trim(),
      allergies: _allergies,
      chronicConditions: _chronic.map((c) => c.code).toList(),
      emergencyContactPhone: _phone.text.trim().isEmpty
          ? null
          : AuthController.normalisePhone(_phone.text),
      version: existing?.version ?? 0,
    );

    try {
      if (existing == null) {
        await repo.create(patient);
      } else {
        await repo.update(patient);
      }
      if (!mounted) return;
      // Spec §16: pop first, then report; the row is already durable.
      showSaveResult(
        ScaffoldMessenger.of(context),
        L.of(context),
        ref.read(databaseProvider),
        rowId: patient.id,
      );
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
    final diagnoses =
        ref.watch(codelistProvider(CodeListKind.diagnosis)).valueOrNull ??
            const <CodeListItem>[];
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    if (_isEdit) {
      final patient = ref.watch(patientProvider(widget.patientId!)).valueOrNull;
      if (patient != null) _hydrate(patient, diagnoses);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? l10n.patientFormEditTitle : l10n.patientFormNewTitle,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            // No heading: the app bar has just said "Add family member", and a
            // "FULL NAME" header over a card holding a name, a sex, a date of
            // birth and a blood group labels one field and mis-labels four.
            FormSection(
              children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.patientFormName),
              validator: (value) => (value ?? '').trim().length < 2
                  ? l10n.authNameTooShort
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            // Three options, always the same three: a segmented control, not a
            // dropdown that hides two of them behind a tap.
            SegmentedControl<Sex>(
              values: Sex.values,
              selected: _sex,
              labelOf: (sex) => switch (sex) {
                Sex.female => l10n.patientFormSexFemale,
                Sex.male => l10n.patientFormSexMale,
                Sex.other => l10n.patientFormSexOther,
              },
              onChanged: (value) => setState(() => _sex = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            BsDateField(
              label: l10n.patientFormDob,
              value: _dob,
              lastDate: DateTime.now(),
              errorText: _dobError,
              onChanged: (value) => setState(() {
                _dob = value;
                _dobError = null;
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _bloodGroup,
              decoration:
                  InputDecoration(labelText: l10n.patientFormBloodGroup),
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.commonNotSet)),
                for (final group in _bloodGroups)
                  DropdownMenuItem(value: group, child: Text(group)),
              ],
              onChanged: (value) => setState(() => _bloodGroup = value),
            ),
              ],
            ),

            FormSection(
              title: l10n.patientFormMunicipality,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ward,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration:
                            InputDecoration(labelText: l10n.patientFormWard),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _municipality,
                        decoration: InputDecoration(
                          labelText: l10n.patientFormMunicipality,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n.patientFormEmergencyPhone,
                    prefixText: '+977 ',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    return AuthController.isValidPhone(value!)
                        ? null
                        : l10n.patientFormPhoneInvalid;
                  },
                ),
              ],
            ),

            // Allergies get their own section rather than a field in a list.
            // They are the one thing on this form that a provider will read
            // first on S21, and the form should say so.
            FormSection(
              title: l10n.patientFormAllergies,
              children: [
                _AllergyEditor(
                  allergies: _allergies,
                  controller: _allergy,
                  onChanged: (value) => setState(() => _allergies = value),
                ),
                const SizedBox(height: AppSpacing.xl),
                PicklistField<CodeListItem>(
                  label: l10n.patientFormChronic,
                  options: diagnoses,
                  selected: _chronic,
                  multi: true,
                  labelOf: (item) => nepali ? item.labelNp : item.labelEn,
                  onChanged: (value) => setState(() => _chronic = value),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: StickySaveBar(
        label: l10n.commonSave,
        busy: _busy,
        onPressed: _save,
      ),
    );
  }
}

/// Free text rather than a picklist: allergies are whatever the family says
/// they are, and a codelist would silently drop the ones that matter most.
class _AllergyEditor extends StatelessWidget {
  const _AllergyEditor({
    required this.allergies,
    required this.controller,
    required this.onChanged,
  });

  final List<String> allergies;
  final TextEditingController controller;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    void add() {
      final value = controller.text.trim();
      if (value.isEmpty || allergies.contains(value)) return;
      onChanged([...allergies, value]);
      controller.clear();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: l10n.patientFormAllergies,
                  hintText: l10n.patientFormAllergiesHint,
                ),
                onSubmitted: (_) => add(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              onPressed: add,
              icon: const Icon(Icons.add_rounded),
              tooltip: l10n.commonAdd,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.brandTintOf(context),
                foregroundColor: AppColors.brandOf(context),
                minimumSize: const Size.square(AppTheme.minTapTarget),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
              ),
            ),
          ],
        ),
        if (allergies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          // The chips are in the allergy red they will be shown in on S08 and
          // S21, so what is being entered looks like what will be read.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final allergy in allergies)
                InputChip(
                  label: Text(allergy),
                  backgroundColor: AppColors.allergyTint,
                  labelStyle: const TextStyle(
                    color: AppColors.allergyRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  deleteIconColor: AppColors.allergyRed,
                  side: BorderSide.none,
                  onDeleted: () => onChanged(
                    allergies.where((a) => a != allergy).toList(),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
