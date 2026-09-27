import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/rules.dart';
import '../../domain/rules/geo.dart';
import '../../domain/rules/triage.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/voice/voice_note_button.dart';
import '../shared/widgets/app_widgets.dart';

/// S13 — the 60-second ANC protocol form.
///
/// Triage is recomputed on every change, from the same rule table the backend
/// uses, so the banner moves as the health worker types rather than after a
/// round trip. The server recomputes it on save and, per spec A.4, its answer
/// wins if the two ever differ.
class AncContactScreen extends ConsumerStatefulWidget {
  const AncContactScreen({
    super.key,
    required this.pregnancyId,
    required this.contactNo,
  });

  final String pregnancyId;
  final int contactNo;

  @override
  ConsumerState<AncContactScreen> createState() => _AncContactScreenState();
}

class _AncContactScreenState extends ConsumerState<AncContactScreen> {
  Findings _findings = const Findings();
  final List<String> _dangerSigns = [];
  Facility? _referralFacility;
  final _referralReason = TextEditingController();

  /// Tier 3 — free text, dictated or typed, stored inside `findings` as
  /// `notesText`. Additive: `AncContact` itself is untouched.
  final _notes = TextEditingController();
  bool _loaded = false;
  bool _showAll = false;
  bool _busy = false;

  @override
  void dispose() {
    _referralReason.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _hydrate(AncContact contact) {
    if (_loaded) return;
    _loaded = true;

    _findings = contact.findings ?? const Findings();
    _dangerSigns.addAll(contact.dangerSigns);
    _referralReason.text = contact.referral?.reason ?? '';
    _notes.text = _findings.notesText ?? '';
  }

  Future<void> _save(
    PregnancyBundle bundle,
    AncContact contact,
    TriageResult triage,
  ) async {
    setState(() => _busy = true);

    final referral = _referralFacility == null
        ? contact.referral
        : Referral(
            facilityId: _referralFacility!.id,
            facilityName: _referralFacility!.name,
            reason: _referralReason.text.trim().isEmpty
                ? triage.reasonsEn.join('; ')
                : _referralReason.text.trim(),
            urgency: triage.isRed
                ? ReferralUrgency.urgent
                : ReferralUrgency.routine,
          );

    try {
      await ref.read(pregnancyRepoProvider).recordContact(
            contact.copyWith(
              doneAt: DateTime.now().toUtc().toIso8601String(),
              findings: _findings.copyWith(
                notesText:
                    _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              ),
              dangerSigns: List.of(_dangerSigns),
              triageLevel: triage.level,
              triageReasons: triage.reasonsEn,
              referral: referral,
            ),
          );
      if (!mounted) return;
      // Spec §16: pop first, then report; the row is already durable.
      showSaveResult(
        ScaffoldMessenger.of(context),
        L.of(context),
        ref.read(databaseProvider),
        rowId: contact.id,
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
    final bundle = ref.watch(pregnancyBundleProvider(widget.pregnancyId));
    final rules = ref.watch(rulesProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ancContactTitle(widget.contactNo)),
        actions: const [SyncPill.compact()],
      ),
      body: asyncView(
        bundle,
        data: (value) {
          final contact = value.ancContacts
              .where((c) => c.contactNo == widget.contactNo)
              .firstOrNull;

          if (contact == null || rules == null) {
            return EmptyState(
              icon: Icons.help_outline,
              title: l10n.errorNotFound,
            );
          }

          _hydrate(contact);
          return _form(value, contact, rules);
        },
      ),
    );
  }

  Widget _form(PregnancyBundle bundle, AncContact contact, Rules rules) {
    final l10n = L.of(context);
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    final edd = parseIsoDate(bundle.pregnancy.edd);
    final gaDays = edd == null
        ? 0
        : gestationalAgeDays(edd, DateTime.now().toUtc());

    // Recomputed on every rebuild — the whole point of the screen.
    final triage = ref.read(rulesProvider).valueOrNull == null
        ? const TriageResult(level: TriageLevel.green)
        : computeTriage(
            findings: _findings,
            dangerSigns: _dangerSigns,
            pregnancy: bundle.pregnancy,
            gestationalAgeDays: gaDays,
            rules: rules,
          );

    final checklist = rules.contact(contact.contactNo)?.checklist ?? const [];
    final extras = _findingFields(l10n, checklist, expanded: false);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.xl,
            ),
            children: [
              // The referral card is the first thing in the body when the
              // triage is not green: on a red result somebody is about to make
              // a journey, and choosing where is the next thing that happens.
              // The banner and the call button are pinned at the bottom, so
              // both stay reachable however far the form is scrolled.
              if (triage.level != TriageLevel.green) ...[
                _ReferralCard(
                  pregnancyId: widget.pregnancyId,
                  triage: triage,
                  selected: _referralFacility,
                  reason: _referralReason,
                  onFacility: (facility) =>
                      setState(() => _referralFacility = facility),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              // Spec S13: the fields this contact's checklist calls for, and
              // nothing else — the rest stay folded away so the form is short
              // enough to finish in a minute.
              FormSection(
                title: l10n.ancFindings,
                helper: l10n.ancFindingsHelper,
                children: [
                  ..._interleave(_findingFields(l10n, checklist, expanded: true)),
                  if (extras.isNotEmpty)
                    Theme(
                      // The tile draws its own top and bottom rules, which is
                      // the one thing this restyle removes everywhere else.
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(
                          l10n.ancMore,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        initiallyExpanded: _showAll,
                        onExpansionChanged: (value) =>
                            setState(() => _showAll = value),
                        children: _interleave(extras),
                      ),
                    ),
                ],
              ),

              FormSection(
                title: l10n.ancNotes,
                helper: l10n.ancNotesHelper,
                children: [
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    minLines: 2,
                    decoration: InputDecoration(
                      hintText: l10n.ancNotes,
                      // Tier 3: dictate in Nepali. The transcript is appended
                      // here and stays editable, so nothing reaches the record
                      // unread.
                      suffixIcon: VoiceNoteButton(controller: _notes),
                    ),
                  ),
                ],
              ),

              // Danger signs are large toggles rather than a list of
              // checkboxes: they are the input most likely to be ticked in a
              // hurry, in bad light, by somebody holding a torch.
              SectionHeader(
                l10n.ancDangerSigns,
                helper: l10n.ancDangerSignsHelper,
              ),
              for (final sign in rules.dangerSignsForChecklist)
                _DangerSignTile(
                  sign: sign,
                  nepali: nepali,
                  selected: _dangerSigns.contains(sign.code),
                  onChanged: (selected) => setState(() {
                    if (selected) {
                      _dangerSigns.add(sign.code);
                    } else {
                      _dangerSigns.remove(sign.code);
                    }
                  }),
                ),
            ],
          ),
        ),

        // Pinned. The banner recomputes on every tick of a danger sign, and it
        // is only useful if the health worker can see it change while they are
        // ticking — which, on a form this long, means it cannot live at the top
        // of a scroll view.
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.md,
                  AppSpacing.gutter,
                  0,
                ),
                child: TriageBanner(result: triage),
              ),
              StickySaveBar(
                label: l10n.ancSaveContact,
                busy: _busy,
                onPressed: () => _save(bundle, contact, triage),
                // Spec S13: a call button on a red referral. A health worker
                // who has to copy a number into the dialer will not call, and
                // one who has to scroll to find the button will not either.
                leading: triage.level == TriageLevel.green
                    ? null
                    : _CallReferralButton(
                        pregnancyId: widget.pregnancyId,
                        selected: _referralFacility,
                        triage: triage,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Puts 16 px between consecutive finding fields.
  ///
  /// The fields are built by a list comprehension that cannot easily interleave
  /// its own spacers, and a column of steppers with no air between them reads
  /// as one undifferentiated block.
  static List<Widget> _interleave(List<Widget> fields) {
    return [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.lg),
        fields[i],
      ],
    ];
  }

  /// [expanded] true returns the fields this contact's checklist calls for;
  /// false returns the rest, for the "More" section.
  List<Widget> _findingFields(
    L l10n,
    List<String> checklist, {
    required bool expanded,
  }) {
    bool wanted(String key) => checklist.contains(key) == expanded;

    return [
      if (wanted('weight'))
        NumberStepper(
          label: l10n.ancWeight,
          value: _findings.weightKg,
          min: 25,
          max: 150,
          step: 0.5,
          decimals: 1,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(weightKg: value?.toDouble()),
          ),
        ),
      if (wanted('bp')) ...[
        NumberStepper(
          label: l10n.ancBpSys,
          value: _findings.bpSys,
          min: 60,
          max: 250,
          step: 2,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(bpSys: value?.toInt()),
          ),
        ),
        NumberStepper(
          label: l10n.ancBpDia,
          value: _findings.bpDia,
          min: 30,
          max: 160,
          step: 2,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(bpDia: value?.toInt()),
          ),
        ),
      ],
      if (wanted('fundalHeight'))
        NumberStepper(
          label: l10n.ancFundalHeight,
          value: _findings.fundalHeightCm,
          min: 8,
          max: 45,
          decimals: 0,
          onChanged: (value) => setState(
            () => _findings =
                _findings.copyWith(fundalHeightCm: value?.toDouble()),
          ),
        ),
      if (wanted('fhr'))
        NumberStepper(
          label: l10n.ancFhr,
          value: _findings.fhrBpm,
          min: 60,
          max: 220,
          step: 5,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(fhrBpm: value?.toInt()),
          ),
        ),
      if (wanted('hb'))
        NumberStepper(
          label: l10n.ancHb,
          value: _findings.hbGdl,
          min: 3,
          max: 20,
          step: 0.1,
          decimals: 1,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(hbGdl: value?.toDouble()),
          ),
        ),
      if (wanted('urineProtein')) ...[
        _Segmented<UrineProtein>(
          label: l10n.ancUrineProtein,
          values: UrineProtein.values,
          selected: _findings.urineProtein,
          labelOf: (value) => value.wire,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(urineProtein: value),
          ),
        ),
      ],
      if (expanded) ...[
        _Segmented<FetalMovement>(
          label: l10n.ancFetalMovement,
          values: FetalMovement.values,
          selected: _findings.fetalMovement,
          labelOf: (value) => switch (value) {
            FetalMovement.normal => l10n.ancFetalMovementNormal,
            FetalMovement.reduced => l10n.ancFetalMovementReduced,
            FetalMovement.absent => l10n.ancFetalMovementAbsent,
          },
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(fetalMovement: value),
          ),
        ),
      ],
      if (wanted('td1') || wanted('td2'))
        _Toggle(
          label: l10n.ancTdGiven,
          value: _findings.tdDoseGiven ?? false,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(tdDoseGiven: value),
          ),
        ),
      if (wanted('ifa'))
        _Toggle(
          label: l10n.ancIfaGiven,
          value: _findings.ifaGiven ?? false,
          onChanged: (value) =>
              setState(() => _findings = _findings.copyWith(ifaGiven: value)),
        ),
      if (wanted('deworming'))
        _Toggle(
          label: l10n.ancDewormingGiven,
          value: _findings.dewormingGiven ?? false,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(dewormingGiven: value),
          ),
        ),
      if (wanted('calcium'))
        _Toggle(
          label: l10n.ancCalciumGiven,
          value: _findings.calciumGiven ?? false,
          onChanged: (value) => setState(
            () => _findings = _findings.copyWith(calciumGiven: value),
          ),
        ),
    ];
  }
}

/// Named so the screen's live recomputation reads as what it is.
TriageResult computeTriage({
  required Findings findings,
  required List<String> dangerSigns,
  required Pregnancy pregnancy,
  required int gestationalAgeDays,
  required Rules rules,
}) {
  return triage(
    findings: findings,
    dangerSigns: dangerSigns,
    pregnancy: pregnancy,
    gestationalAgeDays: gestationalAgeDays,
    rules: rules,
  );
}

class _DangerSignTile extends StatelessWidget {
  const _DangerSignTile({
    required this.sign,
    required this.nepali,
    required this.selected,
    required this.onChanged,
  });

  final DangerSignRule sign;
  final bool nepali;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // Red-level signs are visibly red the moment they are ticked, so a health
    // worker scanning the list knows which ones end the conversation.
    final colour = sign.isRed ? AppColors.triageRed : AppColors.triageAmber;
    final text = Theme.of(context).textTheme;

    return Semantics(
      checked: selected,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!selected),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.lg),
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: selected
                ? TriageColors.bg(sign.level)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            // Unselected tiles carry the app's soft shadow like every other
            // card. A selected one swaps the shadow for a 2 px coloured
            // outline — the one place outside the triage banner where this
            // restyle draws a hard edge, because a ticked danger sign has to be
            // unmistakable from across a room.
            border: selected ? Border.all(color: colour, width: 2) : null,
            boxShadow: selected
                ? null
                : [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 26,
                color: selected ? colour : AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nepali ? sign.np : sign.en,
                      style: text.titleSmall?.copyWith(
                        color: selected
                            ? TriageColors.ink(sign.level)
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nepali ? sign.en : sign.np,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolves which facility a referral would go to.
///
/// Shared by the referral card and the pinned call button so the two can never
/// disagree about where she is being sent: the card offers a choice, the button
/// dials whatever that choice landed on, and neither computes its own default.
Facility? resolveReferralFacility(
  WidgetRef ref,
  String pregnancyId,
  Facility? selected,
) {
  if (selected != null) return selected;

  final patientId = ref
      .watch(pregnancyBundleProvider(pregnancyId))
      .valueOrNull
      ?.pregnancy
      .patientId;
  final all = ref.watch(facilitiesProvider).valueOrNull ?? const <Facility>[];
  final centre = mapCentre(
    all,
    municipality: patientId == null
        ? null
        : ref.watch(patientProvider(patientId)).valueOrNull?.municipality,
  );
  // Nearest first rather than in whatever order the seed happened to be
  // written: the default offered on a red triage should be the one she can
  // actually reach.
  final nearest = facilitiesByDistance(all, centre, birthingOnly: true);
  return nearest.isEmpty ? null : nearest.first;
}

/// The call button in S13's pinned bar.
///
/// Sits beside Save, under the triage banner, whenever the result is amber or
/// red — so the number is one tap away from wherever the form has been
/// scrolled to. Renders nothing when the facility has no phone on record; a
/// dead button is worse than none.
class _CallReferralButton extends ConsumerWidget {
  const _CallReferralButton({
    required this.pregnancyId,
    required this.selected,
    required this.triage,
  });

  final String pregnancyId;
  final Facility? selected;
  final TriageResult triage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final facility = resolveReferralFacility(ref, pregnancyId, selected);
    final phone = facility?.phone;
    if (phone == null || phone.isEmpty) return const SizedBox.shrink();

    return FilledButton.icon(
      onPressed: () => launchUrl(Uri.parse('tel:$phone')),
      icon: const Icon(Icons.call_rounded, size: 20),
      label: Text(l10n.ancCall),
      style: FilledButton.styleFrom(
        backgroundColor:
            triage.isRed ? AppColors.triageRed : AppColors.triageAmber,
        foregroundColor: AppColors.onBrand,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
    );
  }
}

class _ReferralCard extends ConsumerWidget {
  const _ReferralCard({
    required this.pregnancyId,
    required this.triage,
    required this.selected,
    required this.reason,
    required this.onFacility,
  });

  final String pregnancyId;
  final TriageResult triage;
  final Facility? selected;
  final TextEditingController reason;
  final ValueChanged<Facility?> onFacility;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final patientId = ref
        .watch(pregnancyBundleProvider(pregnancyId))
        .valueOrNull
        ?.pregnancy
        .patientId;
    final all = ref.watch(facilitiesProvider).valueOrNull ?? const <Facility>[];
    final centre = mapCentre(
      all,
      municipality: patientId == null
          ? null
          : ref.watch(patientProvider(patientId)).valueOrNull?.municipality,
    );
    final facilities = facilitiesByDistance(all, centre, birthingOnly: true);
    final facility = resolveReferralFacility(ref, pregnancyId, selected);

    final colour =
        triage.isRed ? AppColors.triageRed : AppColors.triageAmber;

    // A coloured left edge rather than a coloured card: the triage banner owns
    // the loud treatment, and two saturated blocks on one screen cancel each
    // other out. The edge says "this belongs to the warning" without competing
    // with it.
    return SoftCard(
      accent: colour,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_hospital_outlined, size: 18, color: colour),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.ancNearestFacility,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          PicklistField<Facility>(
            label: l10n.visitReferralFacility,
            options: facilities,
            selected: facility == null ? const [] : [facility],
            labelOf: (f) => formatDistance(f.distanceKm).isEmpty
                ? f.name
                : '${f.name} · ${formatDistance(f.distanceKm)}',
            onChanged: (value) =>
                onFacility(value.isEmpty ? null : value.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Tier 2: the list answers "which one", the map answers "where",
          // and on a red triage somebody is about to make that journey.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final picked = await context.push<Facility>(
                  '/facilities?birthing=true&pick=true'
                  '${patientId == null ? '' : '&patient=$patientId'}',
                );
                if (picked != null) onFacility(picked);
              },
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(l10n.facilityMapShowOnMap),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: reason,
            decoration: InputDecoration(
              labelText: l10n.ancReferralReason,
              hintText:
                  triage.reasonsEn.isEmpty ? null : triage.reasonsEn.first,
              isDense: true,
            ),
          ),
          // The call button itself lives in the pinned bar at the bottom of the
          // screen (see `_CallReferralButton`), where it stays reachable from
          // anywhere in the form rather than only from the top of it.
        ],
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
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
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        SegmentedControl<T>(
          values: values,
          selected: selected,
          labelOf: labelOf,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        value: value,
        title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        contentPadding: EdgeInsets.zero,
        onChanged: onChanged,
      );
}
