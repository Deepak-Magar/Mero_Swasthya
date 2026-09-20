import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// S15 — Reminders. Read-only: the server schedules and sends them, the app
/// only shows what went where, so a family can see that the SMS is real.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh behind the cached list; failure leaves what is already there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(referenceRepoProvider).refreshReminders(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final reminders = ref.watch(remindersProvider(widget.patientId));
    final flags = ref.watch(configFlagsProvider).valueOrNull;
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remindersTitle),
        actions: const [SyncChip()],
      ),
      body: Column(
        children: [
          if (flags?.smsMode == 'mock')
            Material(
              color: AppColors.brandGreenTint,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.gutter,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sms_outlined,
                      size: 18,
                      color: AppColors.onTriageGreen,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        l10n.remindersDemoHint,
                        style: const TextStyle(
                          color: AppColors.onTriageGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: asyncView(
              reminders,
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_none,
                    title: l10n.remindersEmpty,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref
                      .read(referenceRepoProvider)
                      .refreshReminders(widget.patientId),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.md,
                      AppSpacing.gutter,
                      40,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) => _ReminderTile(
                      reminder: list[index],
                      nepali: nepali,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.nepali});

  final Reminder reminder;
  final bool nepali;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    final text = Theme.of(context).textTheme;

    final (icon, kindLabel) = switch (reminder.kind) {
      ReminderKind.ancDue => (
          Icons.event_available_outlined,
          l10n.remindersKindAncDue,
        ),
      ReminderKind.ancMissed => (
          Icons.event_busy_outlined,
          l10n.remindersKindAncMissed,
        ),
      ReminderKind.followUp => (
          Icons.replay_rounded,
          l10n.remindersKindFollowUp,
        ),
      ReminderKind.medicine => (
          Icons.medication_outlined,
          l10n.remindersKindMedicine,
        ),
    };

    // Sent / failed / scheduled, as a tinted pill. It is the answer to the one
    // question this screen exists for — did the SMS actually go? — so it gets
    // a filled ground rather than an outline nobody reads.
    final (statusLabel, statusInk, statusTint) = switch (reminder.status) {
      ReminderStatus.sent => (
          l10n.remindersStatusSent,
          AppColors.onTriageGreen,
          AppColors.triageGreenTint,
        ),
      ReminderStatus.failed => (
          l10n.remindersStatusFailed,
          AppColors.onTriageRed,
          AppColors.triageRedTint,
        ),
      ReminderStatus.pending => (
          l10n.remindersStatusPending,
          AppColors.onTriageAmber,
          AppColors.triageAmberTint,
        ),
    };

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(kindLabel, style: text.titleSmall)),
              const SizedBox(width: AppSpacing.sm),
              SoftPill(
                label: statusLabel,
                foreground: statusInk,
                background: statusTint,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            nepali ? reminder.messageNp : reminder.messageEn,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              BsDateText(
                reminder.dueAt,
                showAd: false,
                style: text.bodySmall,
              ),
              Text('  ·  ', style: text.bodySmall),
              Text(
                reminder.recipientRole == RecipientRole.family
                    ? l10n.remindersToFamily
                    : l10n.remindersToPatient,
                style: text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
