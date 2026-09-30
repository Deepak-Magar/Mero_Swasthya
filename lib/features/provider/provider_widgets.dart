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

/// The pieces the provider Home tab, the Reminders tab and the lists behind
/// Home's tiles have in common.

/// "28 years · Female" — the line under a name on every provider list.
String ageSexLine(L l10n, Patient patient, {DateTime? asOf}) {
  final dob = BsDate.parseAd(patient.dob);
  final sex = switch (patient.sex) {
    Sex.female => l10n.patientFormSexFemale,
    Sex.male => l10n.patientFormSexMale,
    Sex.other => l10n.patientFormSexOther,
  };
  return [
    if (dob != null) l10n.patientHomeAge(BsDate.ageInYears(dob, asOf: asOf)),
    sex,
  ].join(' · ');
}

/// A wire `YYYY-MM-DD` as a Bikram Sambat date, in the digits of the locale.
String bsDateLabel(BuildContext context, String ymd) {
  final date = BsDate.parseAd(ymd.length > 10 ? ymd.substring(0, 10) : ymd);
  if (date == null) return L.of(context).commonNotSet;
  return BsDate.formatBs(
    date,
    nepaliDigits: Localizations.localeOf(context).languageCode == 'ne',
  );
}

/// The initial-in-a-circle that stands in for a photograph.
class PatientAvatar extends StatelessWidget {
  const PatientAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandTintOf(context),
        shape: BoxShape.circle,
      ),
      // Not scaled with the system font: the circle is a fixed size, and a
      // letter that outgrows it is clipped by it.
      child: Text(
        name.characters.firstOrNull ?? '?',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: AppColors.brandOf(context),
        ),
      ),
    );
  }
}

/// One ANC contact that is owed: whose, which one, and when.
///
/// Used by Home's "Due this week" and by every section of the Reminders tab,
/// so a contact looks the same wherever it is listed.
class DueContactTile extends StatelessWidget {
  const DueContactTile({super.key, required this.row, this.overdue = false});

  final DueContact row;

  /// Amber edge and an "Overdue" chip. Colour is never the only carrier, so
  /// the chip says it in words as well.
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;

    return SoftCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      accent: overdue ? AppColors.triageAmber : null,
      onTap: () => context.push('/provider/patient/${row.patient.id}'),
      semanticLabel: row.patient.name,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.patient.name, style: text.titleSmall),
                const SizedBox(height: AppSpacing.tight),
                Text(
                  '${l10n.homeContactOrdinal('${row.contact.contactNo}')} · '
                  '${bsDateLabel(context, row.contact.dueAt)}',
                  style: text.bodySmall,
                ),
                if (overdue) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SoftPill(
                    icon: Icons.event_busy_outlined,
                    label: l10n.pregnancyContactOverdue,
                    foreground: AppColors.onTriageAmber,
                    background: AppColors.triageAmberTint,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondaryOf(context),
          ),
        ],
      ),
    );
  }
}

/// Notes that a provider opened [patientId], for Home's "Recent patients".
///
/// Wrapped around S21 by the router rather than written into the screen, so
/// the summary itself stays a pure read of the record — and so every way into
/// it (a scan, a list, a dashboard tile) is counted without each of them
/// having to remember to.
class RecentPatientRecorder extends ConsumerStatefulWidget {
  const RecentPatientRecorder({
    super.key,
    required this.patientId,
    required this.child,
  });

  final String patientId;
  final Widget child;

  @override
  ConsumerState<RecentPatientRecorder> createState() =>
      _RecentPatientRecorderState();
}

class _RecentPatientRecorderState
    extends ConsumerState<RecentPatientRecorder> {
  @override
  void initState() {
    super.initState();
    // Best-effort: a list of shortcuts is not worth failing a screen over.
    ref
        .read(databaseProvider)
        .syncMetaDao
        .recordPatientOpened(widget.patientId)
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
