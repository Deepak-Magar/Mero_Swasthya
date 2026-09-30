import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../shared/widgets/app_widgets.dart';
import 'provider_widgets.dart';

/// "Which patient?" — the question Home's *New visit* and *Register pregnancy*
/// have to ask, because unlike S21 they are not standing on a record.
///
/// Only patients this device may write to are offered: a printed-card
/// redemption (read-only) and a grant that withholds the section [needs] are
/// filtered out here rather than refused on the form, so the health worker is
/// never shown a name they cannot then use.
///
/// Returns the chosen patient, or null when the sheet is dismissed.
Future<Patient?> pickProviderPatient(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String emptyText,
  required List<Patient> candidates,
  required GrantSection needs,
}) async {
  final meta = ref.read(databaseProvider).syncMetaDao;

  final eligible = <Patient>[];
  for (final patient in candidates) {
    if (await meta.readOnlyAccess(patient.id)) continue;
    final sections = await meta.grantSections(patient.id);
    if (sections.isNotEmpty && !sections.contains(needs.wire)) continue;
    eligible.add(patient);
  }

  if (!context.mounted) return null;

  return showModalBottomSheet<Patient>(
    context: context,
    // Over the whole shell, bar and Scan button included — a sheet confined
    // to the tab's body leaves the bar live underneath it.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) => _PickerSheet(
      title: title,
      emptyText: emptyText,
      patients: eligible,
    ),
  );
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.emptyText,
    required this.patients,
  });

  final String title;
  final String emptyText;
  final List<Patient> patients;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: patients.isEmpty ? 0.45 : 0.6,
      minChildSize: 0.3,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: text.titleLarge)),
                Text(
                  l10n.homePickPatientTitle,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: patients.isEmpty
                ? ListView(
                    controller: controller,
                    children: [
                      EmptyState(
                        icon: Icons.person_search_outlined,
                        title: emptyText,
                        action: FilledButton.icon(
                          onPressed: () {
                            // Resolved before the pop: the sheet's context is
                            // on its way out by the time the push runs.
                            final router = GoRouter.of(context);
                            Navigator.of(context).pop();
                            router.push('/provider/scan');
                          },
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: Text(l10n.providerScanQr),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      0,
                      AppSpacing.sm,
                      AppSpacing.xl,
                    ),
                    itemCount: patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return ListTile(
                        leading: PatientAvatar(name: patient.name),
                        title: Text(patient.name),
                        subtitle: Text(ageSexLine(l10n, patient)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(patient),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
