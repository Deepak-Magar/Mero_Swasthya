import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// S16 — "Who viewed my record".
///
/// The trust feature: the patient owns the record, so the patient can see every
/// provider who opened it. Server-owned and append-only; the last result is
/// cached so it still reads with no signal.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(referenceRepoProvider).refreshAudit(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final entries = ref.watch(auditProvider(widget.patientId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.auditTitle),
        actions: const [SyncChip()],
      ),
      body: asyncView(
        entries,
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.visibility_off_outlined,
              title: l10n.auditEmpty,
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.read(referenceRepoProvider).refreshAudit(widget.patientId),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                40,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) => _AuditTile(entry: list[index]),
            ),
          );
        },
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    final text = Theme.of(context).textTheme;

    final (icon, label) = switch (entry.action) {
      AuditAction.grantCreated => (
          Icons.qr_code_2_rounded,
          l10n.auditActionGrantCreated,
        ),
      AuditAction.grantRedeemed => (
          Icons.key_outlined,
          l10n.auditActionGrantRedeemed,
        ),
      AuditAction.recordViewed => (
          Icons.visibility_outlined,
          l10n.auditActionRecordViewed,
        ),
      AuditAction.visitAdded => (
          Icons.medical_services_outlined,
          l10n.auditActionVisitAdded,
        ),
      AuditAction.contactRecorded => (
          Icons.checklist_rtl_rounded,
          l10n.auditActionContactRecorded,
        ),
      AuditAction.documentAdded => (
          Icons.description_outlined,
          l10n.auditActionDocumentAdded,
        ),
      AuditAction.grantRevoked => (
          Icons.block_outlined,
          l10n.auditActionGrantRevoked,
        ),
    };

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: AppSpacing.md),
          // What happened, then who, then where and when — one cluster at 4 px,
          // because it is a single sentence broken across four lines.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  entry.actorName.isEmpty
                      ? l10n.commonUnknown
                      : entry.actorName,
                  style: text.bodyMedium,
                ),
                if (entry.actorFacilityName != null) ...[
                  const SizedBox(height: 2),
                  Text(entry.actorFacilityName!, style: text.bodySmall),
                ],
                const SizedBox(height: 2),
                BsDateText(entry.at, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
