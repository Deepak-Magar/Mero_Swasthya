import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates/bs_date.dart';
import '../../core/errors/app_error.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/soft_card.dart';
import '../reminders/prescription_actions.dart';
import '../shared/widgets/app_widgets.dart';
import 'local_timeline.dart';

/// The local union, in the same shape the server's `/timeline` returns.
final localTimelineProvider =
    StreamProvider.family<List<TimelineItem>, String>((ref, patientId) {
  return watchLocalTimeline(ref.watch(databaseProvider), patientId);
});

/// Spec S09: "Local DB builds the same TimelineItem list so the screen works
/// offline; when online, replace with the server list (it is authoritative for
/// titles)."
///
/// The local list is the base, so the screen paints instantly and keeps working
/// with no signal. A successful fetch replaces it wholesale — the server knows
/// about entries this device never created, and its titles carry facility and
/// diagnosis labels the device cannot resolve.
final timelineProvider =
    StreamProvider.family<List<TimelineItem>, String>((ref, patientId) async* {
  final local = ref.watch(localTimelineProvider(patientId));
  final localItems = local.valueOrNull ?? const <TimelineItem>[];
  yield localItems;

  try {
    final page = await ref.read(apiProvider).patients.timeline(patientId);
    if (page.items.isNotEmpty) {
      yield mergeTimeline(server: page.items, local: localItems);
    }
  } on AppError {
    // Offline. The local union already went out above.
  }
});

/// S09 — Timeline, grouped by Bikram Sambat month.
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final items = ref.watch(timelineProvider(patientId));
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.timelineTitle),
        actions: const [SyncChip()],
      ),
      body: asyncView(
        items,
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.history_rounded,
              title: l10n.timelineEmpty,
            );
          }

          final groups = _groupByBsMonth(list, nepali: nepali);

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              40,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The BS month is a quiet tracked label, not a heading that
                  // competes with the entries under it. It marks where one
                  // month stops; the record is the thing being read.
                  Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? AppSpacing.sm : AppSpacing.xl,
                    ),
                    child: SectionHeader(group.label),
                  ),
                  for (final item in group.items) _TimelineRow(item: item),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});

  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    // A.2: the title is pre-formatted by whoever produced the item, and the
    // server is authoritative for it. Only the icon is chosen locally.
    final icon = switch (item.kind) {
      TimelineKind.visit => Icons.medical_services_outlined,
      TimelineKind.document => Icons.description_outlined,
      TimelineKind.pregnancyRegistered => Icons.pregnant_woman_outlined,
      TimelineKind.ancContact => Icons.checklist_rtl_rounded,
      TimelineKind.delivery => Icons.child_care_outlined,
      TimelineKind.immunisation => Icons.vaccines_outlined,
      TimelineKind.growth => Icons.monitor_weight_outlined,
    };
    final title = item.title;
    final text = Theme.of(context).textTheme;

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      onTap: () => _showDetail(context, item, title),
      // The left accent is reserved for triaged entries. A coloured edge on
      // every row is stripes; on one row in twenty it is a warning, and that is
      // the only thing it is allowed to mean here.
      accent: item.badge == null ? null : TriageColors.fg(item.badge),
      padding: EdgeInsets.fromLTRB(
        item.badge == null ? AppSpacing.lg : AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                if (item.subtitle != null) ...[
                  const SizedBox(height: AppSpacing.tight),
                  Text(item.subtitle!, style: text.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.tight),
                Row(
                  children: [
                    Flexible(
                      child: BsDateText(item.at, style: text.bodySmall),
                    ),
                    // A visit written in a village with no signal looks
                    // exactly like one the server already has, and this is
                    // the screen the health worker checks. S06, S12 and the
                    // child schedule all mark a queued row; the timeline did
                    // not, so "did that save?" had no answer here.
                    const SizedBox(width: AppSpacing.sm),
                    PendingDot(rowId: item.refId),
                  ],
                ),
              ],
            ),
          ),
          if (item.badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(
              TriageColors.icon(item.badge),
              size: 20,
              color: TriageColors.fg(item.badge),
            ),
          ],
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, TimelineItem item, String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DetailSheet(item: item, title: title),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.item, required this.title});

  final TimelineItem item;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      // The transparent `Scaffold` is not decoration: `ScaffoldMessenger`
      // attaches a snackbar to the nearest one, and without it the sheet's
      // messages are drawn by the page underneath and never seen.
      builder: (context, controller) => Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.tight),
          BsDateText(
            item.at,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (item.kind == TimelineKind.visit)
            ..._visitDetail(context, Visit.fromJson(item.payload), l10n)
          else if (item.kind == TimelineKind.ancContact)
            ..._contactDetail(context, AncContact.fromJson(item.payload), l10n)
          else if (item.subtitle != null)
            Text(item.subtitle!),
        ],
        ),
      ),
    );
  }

  List<Widget> _visitDetail(BuildContext context, Visit visit, L l10n) {
    // Who wrote this, and where. The record carries both — the server stamps
    // them on push — and a patient reading their own history, or the next
    // health worker to open it, has no other way to find out.
    final byline = [
      if (visit.providerName.isNotEmpty) visit.providerName,
      if (visit.facilityName != null && visit.facilityName!.isNotEmpty)
        visit.facilityName!,
    ].join(' · ');

    return [
      if (byline.isNotEmpty) ...[
        Text(
          byline,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (visit.vitals != null) ...[
        _SectionTitle(l10n.timelineVitals),
        _VitalsGrid(vitals: visit.vitals!),
        const SizedBox(height: 16),
      ],
      if (visit.diagnosisCodes.isNotEmpty) ...[
        _SectionTitle(l10n.timelineDiagnoses),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final code in visit.diagnosisCodes) SoftPill(label: code),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      if (visit.prescriptions.isNotEmpty) ...[
        _SectionTitle(l10n.timelinePrescriptions),
        for (final rx in visit.prescriptions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rx.drugName.isEmpty ? rx.drugCode : rx.drugName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${rx.dose} · ${rx.frequency.wire} · ${rx.durationDays}d',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (rx.instructionsNp != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          rx.instructionsNp!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ],
                  ),
                ),
                // Tier 2. This is the patient's own copy of the record, so it
                // is the place where hearing the dose read out matters most —
                // the provider already knows what they wrote.
                SpeakPrescriptionButton(prescription: rx),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        PrescriptionActions(
          patientId: visit.patientId,
          prescriptions: visit.prescriptions,
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
      if (visit.advice != null) ...[
        _SectionTitle(l10n.timelineAdvice),
        Text(visit.advice!, style: Theme.of(context).textTheme.bodyMedium),
      ],
      if (visit.notes != null) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(visit.notes!, style: Theme.of(context).textTheme.bodyMedium),
      ],
      // A referral written on this visit is the instruction the patient has to
      // act on, and the follow-up date is when they are expected back. Both
      // were saved and neither was shown.
      if (visit.followUpAt != null) ...[
        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(l10n.visitFollowUp),
        BsDateText(
          visit.followUpAt!,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
      if (visit.referral != null) ...[
        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(l10n.visitReferral),
        Text(
          visit.referral!.facilityName,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (visit.referral!.reason.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            visit.referral!.reason,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
          ),
        ],
      ],
    ];
  }

  List<Widget> _contactDetail(
    BuildContext context,
    AncContact contact,
    L l10n,
  ) {
    final findings = contact.findings;
    return [
      if (contact.triageLevel != null)
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: TriageColors.bg(contact.triageLevel!.wire),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    TriageColors.icon(contact.triageLevel!.wire),
                    size: 18,
                    color: TriageColors.fg(contact.triageLevel!.wire),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Spec S16: the band is colour AND icon AND *text*, and the
                  // text has to be readable by the person holding the phone.
                  // The raw wire word ("GREEN") said nothing to a Nepali
                  // reader; the localised headline is the same sentence the
                  // ANC banner shows.
                  Expanded(
                    child: Text(
                      switch (contact.triageLevel!) {
                        TriageLevel.red => l10n.ancTriageRed,
                        TriageLevel.amber => l10n.ancTriageAmber,
                        TriageLevel.green => l10n.ancTriageGreen,
                      },
                      style: TextStyle(
                        color: TriageColors.fg(contact.triageLevel!.wire),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              for (final reason in contact.triageReasons)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.tight),
                  child: Text(
                    '• $reason',
                    style: TextStyle(
                      color: TriageColors.ink(contact.triageLevel!.wire),
                    ),
                  ),
                ),
            ],
          ),
        ),
      const SizedBox(height: AppSpacing.xl),
      if (findings != null) ...[
        _SectionTitle(l10n.ancFindings),
        _FindingsList(findings: findings, l10n: l10n),
      ],
      if (contact.referral != null) ...[
        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(l10n.ancSetReferral),
        Text(
          contact.referral!.facilityName,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.tight),
        Text(
          contact.referral!.reason,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SectionHeader(text);
}

class _VitalsGrid extends StatelessWidget {
  const _VitalsGrid({required this.vitals});

  final Vitals vitals;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      if (vitals.bpSys != null && vitals.bpDia != null)
        ('BP', '${vitals.bpSys}/${vitals.bpDia}'),
      if (vitals.pulse != null) ('Pulse', '${vitals.pulse}'),
      if (vitals.tempC != null) ('Temp', '${vitals.tempC} °C'),
      if (vitals.weightKg != null) ('Weight', '${vitals.weightKg} kg'),
      if (vitals.spo2 != null) ('SpO2', '${vitals.spo2}%'),
    ];

    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.lg,
      children: [
        for (final (label, value) in entries)
          SizedBox(
            width: 96,
            child: StatTile(label: label, value: value),
          ),
      ],
    );
  }
}

class _FindingsList extends StatelessWidget {
  const _FindingsList({required this.findings, required this.l10n});

  final Findings findings;
  final L l10n;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (findings.weightKg != null) (l10n.ancWeight, '${findings.weightKg}'),
      if (findings.bpSys != null && findings.bpDia != null)
        ('BP', '${findings.bpSys}/${findings.bpDia}'),
      if (findings.fundalHeightCm != null)
        (l10n.ancFundalHeight, '${findings.fundalHeightCm}'),
      if (findings.fhrBpm != null) (l10n.ancFhr, '${findings.fhrBpm}'),
      if (findings.hbGdl != null) (l10n.ancHb, '${findings.hbGdl}'),
      if (findings.urineProtein != null)
        (l10n.ancUrineProtein, findings.urineProtein!.wire),
      if (findings.fetalMovement != null)
        (l10n.ancFetalMovement, findings.fetalMovement!.wire),
    ];

    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.tight),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthGroup {
  const _MonthGroup(this.label, this.items);

  final String label;
  final List<TimelineItem> items;
}

/// Spec S09: "Grouped by BS month."
List<_MonthGroup> _groupByBsMonth(
  List<TimelineItem> items, {
  required bool nepali,
}) {
  final groups = <String, List<TimelineItem>>{};

  for (final item in items) {
    final date = BsDate.parseAd(
      item.at.length > 10 ? item.at.substring(0, 10) : item.at,
    );
    final label = date == null
        ? '—'
        // The day is dropped; only the month heading is wanted.
        : BsDate.formatBs(date, nepaliDigits: nepali)
            .split(' ')
            .take(2)
            .join(' ');
    groups.putIfAbsent(label, () => []).add(item);
  }

  return [for (final entry in groups.entries) _MonthGroup(entry.key, entry.value)];
}
