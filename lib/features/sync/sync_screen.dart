import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/app_database.dart';
import '../../data/sync/sync_status.dart';
import '../../shared/widgets/soft_card.dart';

/// S17 — Sync status. "Make offline-first visible."
///
/// The screen exists so a health worker can tell the difference between "the
/// app lost my work" and "the app is holding my work until there is signal" —
/// and so a rejected op is something they can see and act on rather than a
/// silent failure.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final status = ref.watch(syncStatusProvider).valueOrNull ??
        const SyncStatus();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncTitle)),
      body: ListView(
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
                Row(
                  children: [
                    Icon(
                      status.online
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 22,
                      color: status.online
                          ? AppColors.successInkOf(context)
                          : AppColors.textSecondaryOf(context),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    // The headline answers the only question: is my work still
                    // on this phone, or has it left?
                    Expanded(
                      child: Text(
                        status.pending == 0
                            ? l10n.syncNothingPending
                            : l10n.syncPendingOps(status.pending),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.tight),
                Padding(
                  padding: const EdgeInsets.only(left: 34),
                  child: Text(
                    status.lastSyncAt == null
                        ? l10n.syncNever
                        : l10n.syncLastSync(_relative(status.lastSyncAt!, l10n)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (status.stuckUploads > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.triageAmberTint,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.image_not_supported_outlined,
                          size: 18,
                          color: AppColors.triageAmber,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.syncStuckUploads(status.stuckUploads),
                            style: const TextStyle(
                              color: AppColors.onTriageAmber,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: status.running
                      ? null
                      : () => ref.read(syncEngineProvider).run(),
                  icon: status.running
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onBrandOf(context),
                          ),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(l10n.syncNow),
                ),
              ],
            ),
          ),
          if (status.errors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(l10n.syncFailedOps),
            for (final op in status.errors) _FailedOpCard(op: op),
          ],
        ],
      ),
    );
  }

  /// Deliberately coarse. A precise timestamp invites the reader to compare it
  /// with a phone clock that may be wrong by hours.
  static String _relative(String iso, L l10n) {
    final at = DateTime.tryParse(iso);
    if (at == null) return iso;

    final delta = DateTime.now().toUtc().difference(at.toUtc());
    if (delta.inMinutes < 1) return l10n.syncJustNow;
    if (delta.inMinutes < 60) return l10n.syncMinutesAgo(delta.inMinutes);
    if (delta.inHours < 24) return l10n.syncHoursAgo(delta.inHours);
    return l10n.syncDaysAgo(delta.inDays);
  }
}

class _FailedOpCard extends ConsumerWidget {
  const _FailedOpCard({required this.op});

  final OutboxRow op;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final engine = ref.read(syncEngineProvider);

    // A red left edge, because this is the one list in the app where a row is
    // a problem the user has to resolve rather than a record they are reading.
    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      accent: AppColors.triageRed,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(op.targetTable, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.tight),
          Text(
            op.lastError ?? l10n.commonSomethingWentWrong,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.dangerInkOf(context),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => engine.retry(op.opId),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(l10n.commonRetry),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDiscard(context, ref, op),
                  icon: Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.syncDiscard),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerInkOf(context),
                    side: BorderSide(
                      color: AppColors.triageRed.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Discarding a create deletes the local row too (spec §7), which is not
  /// something to do on a single tap.
  Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    OutboxRow op,
  ) async {
    final l10n = L.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.syncDiscard),
        content: Text(op.lastError ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.syncDiscard),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(syncEngineProvider).discard(op.opId);
    }
  }
}
