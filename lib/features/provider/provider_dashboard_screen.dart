import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/provider_dashboard.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// Tier 2 — the health-post dashboard, reached from S19.
///
/// Everything here is counted from the records already on this phone. That is a
/// limitation and also the point: the question a health post asks at the end of
/// a week — who is due, who was missed, who was flagged — has to be answerable
/// with the radio off, which is exactly when a server-side report is not.
class ProviderDashboardScreen extends ConsumerWidget {
  const ProviderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final dashboard = ref.watch(providerDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: const [SyncPill.compact()],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            // The counts are computed from the cached bundles, so a pull is a
            // sync: it is how a health worker who has just come back into signal
            // makes the dashboard agree with the server.
            child: RefreshIndicator(
              onRefresh: () => ref.read(syncEngineProvider).run(),
              child: asyncView(
              dashboard,
              data: (value) {
                if (value.isEmpty) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.55,
                        child: EmptyState(
                          icon: Icons.insights_outlined,
                          title: l10n.dashboardEmpty,
                          action: FilledButton.icon(
                            onPressed: () => context.push('/provider/scan'),
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            label: Text(l10n.providerScanQr),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    40,
                  ),
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // Tall enough for a 32 px count over two lines of a
                      // Devanagari label at 360 dp, which is the tightest this
                      // grid ever gets. Measured, not guessed: 1.25 clipped the
                      // second label line by 6.8 px on a 360-wide phone.
                      childAspectRatio: 1.05,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      children: [
                        for (final bucket in DashboardBucket.values)
                          _Tile(bucket: bucket, count: value.count(bucket)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.dashboardLocalOnly,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.bucket, required this.count});

  final DashboardBucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final colour = bucketColour(bucket, context);

    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      // Every tile taps through. A count nobody can open is a number nobody
      // trusts, and the follow-up question is always "which women?".
      onTap: () => context.push('/provider/dashboard/${bucket.name}'),
      semanticLabel: '${bucketLabel(l10n, bucket)}: $count',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bucketIcon(bucket), size: 20, color: colour),
          const Spacer(),
          Text(
            '$count',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: colour,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: AppSpacing.tight),
          Text(
            bucketLabel(l10n, bucket),
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The filtered list behind a tile.
class DashboardBucketScreen extends ConsumerWidget {
  const DashboardBucketScreen({super.key, required this.bucket});

  final DashboardBucket bucket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final dashboard = ref.watch(providerDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(bucketLabel(l10n, bucket)),
        actions: const [SyncPill.compact()],
      ),
      body: asyncView(
        dashboard,
        data: (value) {
          final rows = value.of(bucket);
          if (rows.isEmpty) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              title: l10n.dashboardBucketEmpty,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: rows.length,
            itemBuilder: (context, index) =>
                _EntryTile(bucket: bucket, entry: rows[index]),
          );
        },
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.bucket, required this.entry});

  final DashboardBucket bucket;
  final DashboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final pregnancy = entry.pregnancy;
    final contact = entry.contact;
    final delivery = entry.delivery;

    final edd = pregnancy == null ? null : parseIsoDate(pregnancy.edd);
    final week =
        edd == null ? null : gestationalAgeWeeks(edd, DateTime.now().toUtc());

    final text = Theme.of(context).textTheme;

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      // Into the record, not into a report: the point of finding somebody on
      // this list is to do something about them.
      onTap: () => context.push('/provider/patient/${entry.patient.id}'),
      semanticLabel: entry.patient.name,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Center(
              child: contact?.triageLevel != null
                  ? TriageDot(level: contact!.triageLevel!, size: 16)
                  : Icon(
                      bucketIcon(bucket),
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.patient.name, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                if (contact != null)
                  Row(
                    children: [
                      Text(
                        '${l10n.pregnancyContactNumber(contact.contactNo)} · ',
                        style: text.bodySmall,
                      ),
                      Flexible(
                        child: BsDateText(
                          contact.doneAt ?? contact.dueAt,
                          showAd: false,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  )
                else if (delivery != null)
                  BsDateText(
                    delivery.deliveredAt,
                    showAd: false,
                    style: text.bodySmall,
                  )
                else if (week != null)
                  Text(l10n.pregnancyWeekOf(week), style: text.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }
}

String bucketLabel(L l10n, DashboardBucket bucket) => switch (bucket) {
      DashboardBucket.trimester1 => l10n.dashboardTrimester1,
      DashboardBucket.trimester2 => l10n.dashboardTrimester2,
      DashboardBucket.trimester3 => l10n.dashboardTrimester3,
      DashboardBucket.overdueContacts => l10n.dashboardOverdue,
      DashboardBucket.recentTriage => l10n.dashboardRecentTriage,
      DashboardBucket.deliveriesThisMonth => l10n.dashboardDeliveries,
    };

IconData bucketIcon(DashboardBucket bucket) => switch (bucket) {
      DashboardBucket.trimester1 ||
      DashboardBucket.trimester2 ||
      DashboardBucket.trimester3 =>
        Icons.pregnant_woman_outlined,
      DashboardBucket.overdueContacts => Icons.error_outline,
      DashboardBucket.recentTriage => Icons.warning_amber_rounded,
      DashboardBucket.deliveriesThisMonth => Icons.child_care_outlined,
    };

/// Amber for what is late, red for what was flagged, green for what happened,
/// and the theme's own colour for the plain counts — so the two tiles that mean
/// "act on this" are the two that stand out.
Color bucketColour(DashboardBucket bucket, BuildContext context) =>
    switch (bucket) {
      DashboardBucket.overdueContacts => AppColors.triageAmber,
      DashboardBucket.recentTriage => AppColors.triageRed,
      DashboardBucket.deliveriesThisMonth => AppColors.brandGreen,
      _ => AppColors.brandOf(context),
    };
