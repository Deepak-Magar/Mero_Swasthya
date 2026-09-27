import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/anc_schedule.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/geo.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import 'delivery_screen.dart' show complicationLabel;

/// S12 — Pregnancy dashboard: the whole pregnancy on one screen.
class PregnancyDashboardScreen extends ConsumerWidget {
  const PregnancyDashboardScreen({super.key, required this.pregnancyId});

  final String pregnancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final bundle = ref.watch(pregnancyBundleProvider(pregnancyId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pregnancyDashboardTitle),
        actions: const [SyncPill.compact()],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: asyncView(
              bundle,
              data: (value) => _Body(bundle: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.bundle});

  final PregnancyBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final pregnancy = bundle.pregnancy;
    final edd = parseIsoDate(pregnancy.edd);
    final week =
        edd == null ? null : gestationalAgeWeeks(edd, DateTime.now().toUtc());
    final overdue = overdueContacts(bundle.ancContacts)
        .map((c) => c.contactNo)
        .toSet();
    final progress = scheduleProgress(bundle.ancContacts);

    final text = Theme.of(context).textTheme;
    final highRisk = pregnancy.riskLevel == RiskLevel.high;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        40,
      ),
      children: [
        // The hero: week, EDD and risk in one block, because those three
        // numbers are what every conversation about this pregnancy starts with.
        SoftCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      week == null
                          ? l10n.pregnancyDashboardTitle
                          : l10n.pregnancyWeekOf(week),
                      style: text.headlineMedium,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  SoftPill(
                    icon: highRisk
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    label: highRisk
                        ? l10n.pregnancyRiskHigh
                        : l10n.pregnancyRiskNormal,
                    foreground: highRisk
                        ? AppColors.onTriageAmber
                        : AppColors.onTriageGreen,
                    background: highRisk
                        ? AppColors.triageAmberTint
                        : AppColors.triageGreenTint,
                  ),
                ],
              ),
              FactRow(
                label: l10n.pregnancyEdd,
                value: BsDateText(
                  pregnancy.edd,
                  showAd: false,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value:
                      progress.total == 0 ? 0 : progress.done / progress.total,
                  minHeight: 8,
                  backgroundColor: AppColors.skeleton,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.brandGreen,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${progress.done} / ${progress.total}',
                style: text.bodySmall,
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.xl),
        for (final contact in bundle.ancContacts)
          _ContactTile(
            contact: contact,
            pregnancyId: pregnancy.id,
            isOverdue: overdue.contains(contact.contactNo),
          ),

        const SizedBox(height: AppSpacing.lg),
        _BirthPlanCard(pregnancy: pregnancy),

        const SizedBox(height: AppSpacing.lg),
        // S14 closes the pregnancy. Once it is closed the dashboard is a record
        // of what happened rather than a plan for what is next, so the action
        // is replaced by the outcome instead of sitting there greyed out.
        if (pregnancy.status == PregnancyStatus.active)
          OutlinedButton.icon(
            onPressed: () =>
                context.push('/pregnancy/${pregnancy.id}/delivery'),
            icon: const Icon(Icons.child_care_outlined, size: 18),
            label: Text(l10n.pregnancyRecordDelivery),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          )
        else
          _DeliveryCard(delivery: bundle.delivery),

        if (bundle.reminders.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(l10n.remindersTitle),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < bundle.reminders.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sms_outlined,
                        size: 18,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BsDateText(
                              bundle.reminders[i].dueAt,
                              showAd: false,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              // S15 already picks the language-matched body;
                              // this preview of the same reminder showed the
                              // English one under a Nepali heading.
                              Localizations.localeOf(context).languageCode ==
                                      'ne'
                                  ? bundle.reminders[i].messageNp
                                  : bundle.reminders[i].messageEn,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.pregnancyId,
    required this.isOverdue,
  });

  final AncContact contact;
  final String pregnancyId;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final done = contact.doneAt != null;
    final referral = contact.referral;

    // The dot is the stepper's whole semantics: done carries the triage colour
    // it was recorded at, overdue is red, and everything still to come is a
    // quiet outline. Spec §16 — never colour alone, so each state also carries
    // its own glyph and a word underneath.
    final Widget dot = done
        ? TriageDot(level: contact.triageLevel ?? TriageLevel.green, size: 16)
        : Icon(
            isOverdue ? Icons.error_outline : Icons.schedule_rounded,
            size: 22,
            color: isOverdue ? AppColors.triageRed : AppColors.textSecondaryOf(context),
          );

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: () => context.push(
        '/pregnancy/$pregnancyId/contact/${contact.contactNo}',
      ),
      // Spec S12: overdue is a red edge, not just a red dot — the card has to
      // be findable while scrolling past eight of them.
      accent: isOverdue ? AppColors.triageRed : null,
      padding: EdgeInsets.fromLTRB(
        isOverdue ? AppSpacing.md : AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 24, child: Center(child: dot)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.pregnancyContactNumber(contact.contactNo)} · '
                      '${l10n.pregnancyContactWeek(contact.weekTarget)}',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.tight),
                    if (done)
                      Text(l10n.pregnancyContactDone, style: text.bodySmall)
                    else
                      Row(
                        children: [
                          if (isOverdue) ...[
                            Text(
                              l10n.pregnancyContactOverdue,
                              style: text.bodySmall?.copyWith(
                                color: AppColors.dangerInkOf(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Flexible(
                            child: BsDateText(
                              contact.dueAt,
                              showAd: false,
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              PendingDot(rowId: contact.id),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondaryOf(context),
              ),
            ],
          ),
          if (referral != null && contact.triageLevel == TriageLevel.red) ...[
            const SizedBox(height: AppSpacing.md),
            _ReferralStrip(referral: referral),
          ],
        ],
      ),
    );
  }
}

/// Spec S12: "nearestReferral shown on red contacts."
///
/// The dashboard is where somebody checks on a woman between visits, so a red
/// contact has to carry the facility she was sent to and a way to ring it —
/// not just a red dot that means "open this to find out".
class _ReferralStrip extends StatelessWidget {
  const _ReferralStrip({required this.referral});

  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.triageRedTint,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_hospital_outlined,
            size: 18,
            color: AppColors.triageRed,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  referral.facilityName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.dangerInkOf(context),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  referral.reason,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FacilityCallButton(
            facilityId: referral.facilityId,
            label: l10n.ancCall,
          ),
        ],
      ),
    );
  }
}

class _BirthPlanCard extends ConsumerWidget {
  const _BirthPlanCard({required this.pregnancy});

  final Pregnancy pregnancy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final plan = pregnancy.birthPlan;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionHeader(
                  l10n.pregnancyBirthPlan,
                  padding: EdgeInsets.zero,
                ),
              ),
              TextButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.commonEdit),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (plan == null)
            Text(
              l10n.commonNotSet,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            )
          else ...[
            if (plan.facilityName != null)
              _row(context, l10n.pregnancyBirthPlanFacility, plan.facilityName!),
            if (plan.transport != null)
              _row(context, l10n.pregnancyBirthPlanTransport, plan.transport!),
            if (plan.bloodDonorName != null)
              _row(context, l10n.pregnancyBirthPlanDonor, plan.bloodDonorName!),
            if (plan.companionName != null)
              _row(
                context,
                l10n.pregnancyBirthPlanCompanion,
                plan.companionName!,
              ),
            _row(
              context,
              l10n.pregnancyBirthPlanMoneySaved,
              (plan.moneySaved ?? false) ? l10n.commonYes : l10n.commonNo,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.tight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final updated = await showModalBottomSheet<BirthPlan>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BirthPlanSheet(
        plan: pregnancy.birthPlan,
        patientId: pregnancy.patientId,
      ),
    );
    if (updated == null) return;

    await ref
        .read(pregnancyRepoProvider)
        .updatePregnancy(pregnancy.copyWith(birthPlan: updated));

    if (context.mounted) showSavedSnackBar(context);
  }
}

class _BirthPlanSheet extends ConsumerStatefulWidget {
  const _BirthPlanSheet({this.plan, required this.patientId});

  final BirthPlan? plan;
  final String patientId;

  @override
  ConsumerState<_BirthPlanSheet> createState() => _BirthPlanSheetState();
}

class _BirthPlanSheetState extends ConsumerState<_BirthPlanSheet> {
  late final _transport =
      TextEditingController(text: widget.plan?.transport ?? '');
  late final _donor =
      TextEditingController(text: widget.plan?.bloodDonorName ?? '');
  late final _donorPhone =
      TextEditingController(text: widget.plan?.bloodDonorPhone ?? '');
  late final _companion =
      TextEditingController(text: widget.plan?.companionName ?? '');
  late bool _moneySaved = widget.plan?.moneySaved ?? false;
  Facility? _facility;

  @override
  void dispose() {
    _transport.dispose();
    _donor.dispose();
    _donorPhone.dispose();
    _companion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    // Only facilities that can actually deliver a baby, nearest first: the
    // birth plan is a plan to travel, so distance is the first fact about
    // each option rather than an afterthought.
    final all = ref.watch(facilitiesProvider).valueOrNull ?? const <Facility>[];
    final facilities = facilitiesByDistance(
      all,
      mapCentre(
        all,
        municipality:
            ref.watch(patientProvider(widget.patientId)).valueOrNull
                ?.municipality,
      ),
      birthingOnly: true,
    );

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
          children: [
            PicklistField<Facility>(
              label: l10n.pregnancyBirthPlanFacility,
              options: facilities,
              selected: _facility == null ? const [] : [_facility!],
              labelOf: (f) => formatDistance(f.distanceKm).isEmpty
                  ? f.name
                  : '${f.name} · ${formatDistance(f.distanceKm)}',
              onChanged: (value) =>
                  setState(() => _facility = value.isEmpty ? null : value.first),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await context.push<Facility>(
                    '/facilities?birthing=true&pick=true'
                    '&patient=${widget.patientId}',
                  );
                  if (picked != null) setState(() => _facility = picked);
                },
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(l10n.facilityMapChooseOnMap),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _transport,
              decoration:
                  InputDecoration(labelText: l10n.pregnancyBirthPlanTransport),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _donor,
              decoration:
                  InputDecoration(labelText: l10n.pregnancyBirthPlanDonor),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _donorPhone,
              keyboardType: TextInputType.phone,
              decoration:
                  InputDecoration(labelText: l10n.pregnancyBirthPlanDonorPhone),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _companion,
              decoration:
                  InputDecoration(labelText: l10n.pregnancyBirthPlanCompanion),
            ),
            SwitchListTile(
              value: _moneySaved,
              title: Text(l10n.pregnancyBirthPlanMoneySaved),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => _moneySaved = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                BirthPlan(
                  facilityId: _facility?.id ?? widget.plan?.facilityId,
                  facilityName: _facility?.name ?? widget.plan?.facilityName,
                  transport: _text(_transport),
                  moneySaved: _moneySaved,
                  bloodDonorName: _text(_donor),
                  bloodDonorPhone: _text(_donorPhone),
                  companionName: _text(_companion),
                ),
              ),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  String? _text(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();
}

/// The "Delivered" state of S12: what happened, in the order somebody reading
/// the card would want it.
///
/// [delivery] can be null when the pregnancy was closed on another device and
/// only the pregnancy row has arrived so far — the status is still the truth,
/// so the card says so rather than showing nothing at all.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.delivery});

  final Delivery? delivery;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final value = delivery;

    // Deliberately the ordinary card surface. An explicit light-green
    // background reads beautifully in the light theme and is unreadable in the
    // dark one, where the body text stays light-on-light — the tick and the
    // green heading carry the meaning without repainting the whole card.
    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 22,
                  color: AppColors.successInkOf(context),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.pregnancyDelivered,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.onTriageGreen),
                  ),
                ),
                if (value != null) PendingDot(rowId: value.id),
              ],
            ),
            if (value != null) ...[
              const SizedBox(height: AppSpacing.sm),
              FactRow(
                label: l10n.deliveryAt,
                value: BsDateText(value.deliveredAt, showAd: false),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${_placeLabel(l10n, value.place)} · '
                '${_modeLabel(l10n, value.mode)} · '
                '${_outcomeLabel(l10n, value.outcome)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (value.babyWeightKg != null || value.babySex != null) ...[
                const SizedBox(height: AppSpacing.tight),
                Text(
                  '${l10n.deliveryBabyLabel}: ${[
                    if (value.babySex != null)
                      value.babySex == Sex.female
                          ? l10n.patientFormSexFemale
                          : l10n.patientFormSexMale,
                    if (value.babyWeightKg != null)
                      '${value.babyWeightKg!.toStringAsFixed(1)} kg',
                  ].join(' · ')}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                l10n.deliveryComplications,
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              ),
              if (value.complications.isEmpty)
                Text(
                  l10n.deliveryComplicationNone,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                )
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final code in value.complications)
                      SoftPill(
                        label: complicationLabel(l10n, code),
                        foreground: AppColors.onTriageAmber,
                        background: AppColors.triageAmberTint,
                      ),
                  ],
                ),
            ],
          ],
        ),
    );
  }

  static String _placeLabel(L l10n, DeliveryPlace place) => switch (place) {
        DeliveryPlace.home => l10n.deliveryPlaceHome,
        DeliveryPlace.birthingCentre => l10n.deliveryPlaceBirthingCentre,
        DeliveryPlace.hospital => l10n.deliveryPlaceHospital,
        DeliveryPlace.onTheWay => l10n.deliveryPlaceOnTheWay,
      };

  static String _modeLabel(L l10n, DeliveryMode mode) => switch (mode) {
        DeliveryMode.normal => l10n.deliveryModeNormal,
        DeliveryMode.assisted => l10n.deliveryModeAssisted,
        DeliveryMode.cs => l10n.deliveryModeCs,
      };

  static String _outcomeLabel(L l10n, DeliveryOutcome outcome) =>
      switch (outcome) {
        DeliveryOutcome.liveBirth => l10n.deliveryOutcomeLive,
        DeliveryOutcome.stillbirth => l10n.deliveryOutcomeStill,
      };
}
