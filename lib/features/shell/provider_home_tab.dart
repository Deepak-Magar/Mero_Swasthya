import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/provider_home.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../provider/patient_picker.dart';
import '../provider/provider_widgets.dart';
import '../shared/widgets/app_widgets.dart';
import 'provider_shell.dart';

/// The provider shell's Home tab — the first screen after activation.
///
/// Top to bottom: who you are and what day it is; the scan card; four counts
/// for today; who needs attention; who is due this week; who you opened last;
/// the four actions a health post does most; the protocol version. Everything
/// on it is read from Drift through [providerHomeProvider], so it renders the
/// same with the radio off and against the mock.
///
/// The screen is a plain `ListView` rather than slivers: nothing here pins,
/// and a list is what pull-to-refresh and the layout test both want.
class ProviderHomeTab extends ConsumerWidget {
  const ProviderHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(providerHomeProvider);

    // "Re-query Drift", not "sync": the pull re-subscribes every stream with
    // the current time. A sync is one tap away on the pill.
    Future<void> refresh() async {
      ref.invalidate(providerHomeProvider);
      try {
        await ref.read(providerHomeProvider.future);
      } on Object {
        // The error state below says what went wrong.
      }
    }

    final value = home.valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.md,
                    AppSpacing.gutter,
                    // Clear of the docked Scan button, which stands proud of
                    // the bar by half its height.
                    ProviderShell.scanButtonSize,
                  ),
                  children: [
                    const _Header(),
                    const SizedBox(height: AppSpacing.lg),
                    const _ScanCard(),
                    const SizedBox(height: AppSpacing.xl),
                    if (value != null) ...[
                      _TodayStrip(home: value),
                      const SizedBox(height: AppSpacing.xl),
                      _AttentionSection(home: value),
                      const SizedBox(height: AppSpacing.xl),
                      _DueWeekSection(home: value),
                      const SizedBox(height: AppSpacing.xl),
                      _RecentSection(home: value),
                      const SizedBox(height: AppSpacing.xl),
                      _QuickActions(home: value),
                    ] else if (home.hasError)
                      ErrorState(error: home.error!, onRetry: refresh)
                    else
                      const _LoadingBlock(),
                    const SizedBox(height: AppSpacing.xl),
                    const _Footer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Greeting by time of day, the facility, today in both calendars, and the
/// sync pill.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);
    final now = ref.watch(clockProvider)();
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    final name = auth.user?.name.trim() ?? '';
    final firstName = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final greeting = firstName.isEmpty
        ? l10n.providerHomeTitle
        : switch (now.hour) {
            < 12 => l10n.homeGreetingMorning(firstName),
            < 17 => l10n.homeGreetingDay(firstName),
            _ => l10n.homeGreetingEvening(firstName),
          };
    final facility = auth.user?.facilityName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: text.titleLarge),
                  if (facility != null && facility.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      facility,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Bounded, so a long Nepali pending count shortens inside the pill
            // rather than pushing the greeting off the left edge.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: const SyncPill.compact(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spec §13: Bikram Sambat first, Gregorian small under it.
                  Text(
                    BsDate.formatBs(now, nepaliDigits: nepali),
                    style: text.titleSmall,
                  ),
                  Text(BsDate.formatAd(now), style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Scan card
// ---------------------------------------------------------------------------

/// The one brand-blue card on the screen: the reason the phone is out.
///
/// It opens the same scanner the centre button does. "Enter code instead" is
/// the scanner's own manual fallback, opened through the route so the redeem
/// path stays the one it has always been.
class _ScanCard extends StatelessWidget {
  const _ScanCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final ink = AppColors.onBrandOf(context);

    return SoftCard(
      color: AppColors.brandOf(context),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      onTap: () => context.push(ProviderTabs.scan),
      semanticLabel: l10n.providerScanQr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.qr_code_scanner_rounded, size: 28, color: ink),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.providerScanQr,
                      style: text.titleMedium?.copyWith(color: ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.homeScanSubtitle,
                      style: text.bodySmall?.copyWith(
                        color: ink.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded, color: ink),
            ],
          ),
          const SizedBox(height: AppSpacing.tight),
          // A text button inside a tappable card: the button wins the tap,
          // because SoftCard wraps its content in the InkWell rather than
          // laying one over it.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.push('${ProviderTabs.scan}?manual=1'),
              style: TextButton.styleFrom(
                foregroundColor: ink,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(0, AppTheme.minTapTarget),
              ),
              child: Text(
                l10n.providerScanManual,
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today
// ---------------------------------------------------------------------------

/// Four counts for today, each opening the list it was counted from.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.home});

  final ProviderHome home;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final brand = AppColors.brandOf(context);
    final quiet = AppColors.textSecondaryOf(context);

    final tiles = [
      _StatTile(
        icon: Icons.people_outline,
        label: l10n.homeStatSeen,
        count: home.seenToday.length,
        colour: brand,
        onTap: () => context.go('${ProviderTabs.patients}?seen=today'),
      ),
      _StatTile(
        icon: Icons.note_add_outlined,
        label: l10n.homeStatVisits,
        count: home.visitsToday.length,
        colour: AppColors.successInkOf(context),
        onTap: () => context.push('/provider/visits/today'),
      ),
      _StatTile(
        icon: Icons.pregnant_woman_outlined,
        label: l10n.homeStatAncDue,
        count: home.dueToday.length,
        colour: home.dueToday.isEmpty ? quiet : AppColors.triageAmber,
        onTap: () => context.go(ProviderTabs.reminders),
      ),
      _StatTile(
        icon: Icons.cloud_upload_outlined,
        label: l10n.homeStatPending,
        count: home.pendingSync,
        colour: home.pendingSync == 0 ? quiet : AppColors.triageAmber,
        onTap: () => context.push('/sync'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.commonToday),
        // Equal heights whatever the labels wrap to, so four tiles read as
        // one row rather than a skyline.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      onTap: onTap,
      semanticLabel: '$label: $count',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(height: 6),
          // Always a figure — "0" is an answer, blank is a question.
          Text(
            '$count',
            style: text.titleLarge?.copyWith(
              color: colour,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          // No maxLines: a Nepali label wraps to a third line at a large font
          // rather than losing its last word.
          Text(
            label,
            style: text.labelMedium?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Needs attention
// ---------------------------------------------------------------------------

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({required this.home});

  final ProviderHome home;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final rows = home.attention.take(ProviderHome.homeRowLimit).toList();

    return KeyedSubtree(
      key: ProviderCoachTargets.needsAttention,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(l10n.homeAttentionTitle),
          if (rows.isEmpty)
            const _CalmCard()
          else
            for (final item in rows) _AttentionRow(item: item),
        ],
      ),
    );
  }
}

/// "No danger signs flagged" — green, and it says why, because an empty list
/// under a heading like this one reads as "not loaded" until it does.
class _CalmCard extends StatelessWidget {
  const _CalmCard();

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;

    return SoftCard(
      color: AppColors.triageGreenTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle,
            size: 24,
            color: AppColors.triageGreen,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeAttentionEmptyTitle,
                  style: text.titleSmall?.copyWith(
                    color: AppColors.onTriageGreen,
                  ),
                ),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  l10n.homeAttentionEmptyBody,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.onTriageGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;
    final nepali = Localizations.localeOf(context).languageCode == 'ne';
    final contact = l10n.homeContactOrdinal('${item.contact.contactNo}');

    final (chipIcon, chipLabel, signal, ink, tint) = switch (item.kind) {
      AttentionKind.redTriage => (
          Icons.error,
          l10n.homeTriageRed,
          AppColors.triageRed,
          AppColors.onTriageRed,
          AppColors.triageRedTint,
        ),
      AttentionKind.amberTriage => (
          Icons.warning_amber_rounded,
          l10n.homeTriageAmber,
          AppColors.triageAmber,
          AppColors.onTriageAmber,
          AppColors.triageAmberTint,
        ),
      AttentionKind.overdueContact => (
          Icons.event_busy_outlined,
          l10n.pregnancyContactOverdue,
          AppColors.triageAmber,
          AppColors.onTriageAmber,
          AppColors.triageAmberTint,
        ),
    };

    final String reason;
    if (item.kind == AttentionKind.overdueContact) {
      reason = l10n.homeReasonOverdue(
        contact,
        bsDateLabel(context, item.contact.dueAt),
      );
    } else {
      final en = firstReadableReason(item.contact);
      final rules = ref.watch(rulesProvider).valueOrNull;
      final why = en == null
          ? (item.kind == AttentionKind.redTriage
              ? l10n.ancTriageRed
              : l10n.ancTriageAmber)
          : (nepali ? rules?.translateReason(en) ?? en : en);
      reason = '$contact · $why';
    }

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      accent: signal,
      onTap: () => context.push('/provider/patient/${item.patient.id}'),
      semanticLabel: '${item.patient.name}, $chipLabel',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.patient.name, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  ageSexLine(
                    l10n,
                    item.patient,
                    asOf: ref.watch(clockProvider)(),
                  ),
                  style: text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                // The chip on its own line: beside a long Nepali name it had
                // nowhere to go but off the card.
                Align(
                  alignment: Alignment.centerLeft,
                  child: SoftPill(
                    icon: chipIcon,
                    label: chipLabel,
                    foreground: ink,
                    background: tint,
                    dense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  reason,
                  style: text.bodySmall?.copyWith(color: ink),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.tight,
              left: AppSpacing.sm,
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Due this week
// ---------------------------------------------------------------------------

class _DueWeekSection extends StatelessWidget {
  const _DueWeekSection({required this.home});

  final ProviderHome home;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final rows = home.dueThisWeek.take(ProviderHome.homeRowLimit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          l10n.homeDueWeekTitle,
          padding: const EdgeInsets.only(bottom: AppSpacing.tight),
          trailing: TextButton(
            onPressed: () => context.go(ProviderTabs.reminders),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              minimumSize: const Size(0, AppTheme.minTapTarget),
            ),
            child: Text(l10n.homeSeeAll),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              l10n.homeDueWeekEmpty,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            ),
          )
        else
          for (final row in rows) DueContactTile(row: row),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recent patients
// ---------------------------------------------------------------------------

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.home});

  final ProviderHome home;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.providerRecentPatients),
        if (home.recentPatients.isEmpty)
          Text(
            l10n.homeRecentEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
          )
        else
          // Chips that wrap rather than a strip that scrolls: five names are
          // all visible at once, and a long Nepali name wraps inside its chip.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final patient in home.recentPatients)
                _PatientChip(patient: patient),
            ],
          ),
      ],
    );
  }
}

class _PatientChip extends StatelessWidget {
  const _PatientChip({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: patient.name,
      child: Material(
        color: AppColors.brandTintOf(context),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => context.push('/provider/patient/${patient.id}'),
          borderRadius: BorderRadius.circular(999),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.minTapTarget),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, AppSpacing.lg, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PatientAvatar(name: patient.name, size: 32),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      patient.name,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: AppColors.brandOf(context),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.home});

  final ProviderHome home;

  Future<void> _registerPregnancy(BuildContext context, WidgetRef ref) async {
    final l10n = L.of(context);
    // Spec S11: female, and no pregnancy open — the same rule S21 applies.
    final picked = await pickProviderPatient(
      context,
      ref,
      title: l10n.patientHomeRegisterPregnancy,
      emptyText: l10n.homePickPregnancyEmpty,
      candidates: [
        for (final p in home.patients)
          if (p.sex == Sex.female && !home.pregnantPatientIds.contains(p.id)) p,
      ],
      needs: GrantSection.pregnancy,
    );
    if (picked != null && context.mounted) {
      context.push('/patient/${picked.id}/pregnancy/new');
    }
  }

  Future<void> _newVisit(BuildContext context, WidgetRef ref) async {
    final l10n = L.of(context);
    final picked = await pickProviderPatient(
      context,
      ref,
      title: l10n.providerAddVisit,
      emptyText: l10n.homePickPatientEmpty,
      candidates: home.patients,
      needs: GrantSection.visits,
    );
    if (picked != null && context.mounted) {
      context.push('/provider/patient/${picked.id}/visit/new');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);

    final actions = [
      _QuickAction(
        icon: Icons.pregnant_woman_outlined,
        label: l10n.patientHomeRegisterPregnancy,
        onTap: () => _registerPregnancy(context, ref),
      ),
      _QuickAction(
        icon: Icons.add_rounded,
        label: l10n.homeQuickNewVisit,
        onTap: () => _newVisit(context, ref),
      ),
      _QuickAction(
        icon: Icons.people_outline,
        label: l10n.navPatients,
        onTap: () => context.go(ProviderTabs.patients),
      ),
      _QuickAction(
        icon: Icons.notifications_none_rounded,
        label: l10n.navReminders,
        onTap: () => context.go(ProviderTabs.reminders),
      ),
    ];

    // Four across at the phone's own font size; two by two once the font is
    // large enough that "Register pregnancy" would have to break mid-word to
    // fit a quarter of the width.
    final twoByTwo = MediaQuery.textScalerOf(context).scale(12) > 14;

    Widget row(List<Widget> cells) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(child: cells[i]),
              ],
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.homeQuickActions),
        if (twoByTwo) ...[
          row(actions.sublist(0, 2)),
          const SizedBox(height: AppSpacing.sm),
          row(actions.sublist(2)),
        ] else
          row(actions),
      ],
    );
  }
}

/// An icon over a label that wraps. Unlike `SoftTile` it never shrinks or
/// clips the label: the tile grows instead, and the row it is in grows with
/// it.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brandOf(context);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.brandTintOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.tight,
                vertical: AppSpacing.md,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: brand),
                  const SizedBox(height: AppSpacing.sm),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: brand,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading, footer
// ---------------------------------------------------------------------------

/// The silhouette of the first two sections while Drift answers. Inline
/// rather than `LoadingList`, which is a list of its own and cannot sit
/// inside this one.
class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.skeleton,
            borderRadius: BorderRadius.circular(7),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(160),
                  const SizedBox(height: AppSpacing.sm),
                  bar(96),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Protocol v2026-09-18.1" — which rule table this phone triages with.
class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(rulesProvider).valueOrNull?.version;
    if (version == null || version.isEmpty) return const SizedBox.shrink();

    return Center(
      child: Text(
        L.of(context).homeProtocolVersion(version),
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
      ),
    );
  }
}
