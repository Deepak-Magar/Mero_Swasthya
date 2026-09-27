import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/brand_logo.dart';
import '../auth/auth_controller.dart';
import '../family/family_widgets.dart';
import '../patient_home/patient_home_screen.dart';
import '../shared/widgets/app_widgets.dart';

/// The patient shell's Home tab: the family, and the selected member's record,
/// on one screen.
///
/// This is the audit's first structural fix. Before it, S06 was a list of
/// people and S08 was the record, so the record — the reason the app exists —
/// was always one level below a directory, and switching member meant going
/// back out to the directory. Here the strip and the record share the screen:
/// the member is chosen with a single tap and the record never leaves view.
class PatientHomeTab extends ConsumerStatefulWidget {
  const PatientHomeTab({super.key});

  @override
  ConsumerState<PatientHomeTab> createState() => _PatientHomeTabState();
}

class _PatientHomeTabState extends ConsumerState<PatientHomeTab> {
  @override
  void initState() {
    super.initState();
    // Spec S06: "GET /patients (on refresh), plus local DB read". The screen
    // paints from the database first; this fills in anything the account owns
    // that this device has never seen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(patientRepoProvider).refreshFromServer();
    });
  }

  Future<void> _refresh() async {
    await ref.read(patientRepoProvider).refreshFromServer();
    await ref.read(syncEngineProvider).run();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final ownerId = auth.user?.id ?? '';
    final family = ref.watch(familyProvider(ownerId));
    final name = auth.user?.name;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        // Greeting over label. A home screen that opens with the user's own
        // name reads as *their* phone rather than as a database they have been
        // given access to.
        title: BrandAppBarTitle(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (name != null && name.isNotEmpty)
                Text(
                  l10n.familyGreeting(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                )
              else
                Text(
                  l10n.familyTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (name != null && name.isNotEmpty)
                Text(l10n.familyTitle,
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        // No compact pill here: the full one, with the time in words, is the
        // first thing under the bar. Two copies of the same control on one
        // screen is one too many.
        actions: const [SizedBox(width: AppSpacing.sm)],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // The full sync pill, with the time in words, on the one screen where
          // "is my record safe" is actually asked. The app-bar pill is the
          // compact form of the same control and opens the same screen.
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.sm,
              AppSpacing.gutter,
              0,
            ),
            child: SyncPill(),
          ),
          Expanded(
            child: asyncView(
              family,
              onRetry: _refresh,
              data: (patients) {
                if (patients.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    // A scroll view even when empty, so pull-to-refresh works
                    // in the one state where a user is most likely to try it.
                    // The audit's tenth finding was the opposite of this.
                    child: ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.62,
                          child: EmptyState(
                            icon: Icons.people_outline,
                            title: l10n.familyEmptyTitle,
                            body: l10n.familyEmptyBody,
                            action: FilledButton.icon(
                              onPressed: () => context.push('/family/new'),
                              icon: const Icon(Icons.add_rounded),
                              label: Text(l10n.familyAddMember),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final selected = _resolveSelection(patients);

                return Column(
                  children: [
                    FamilyStrip(
                      members: patients,
                      selectedId: selected.id,
                      onSelect: (id) => ref
                          .read(selectedMemberProvider.notifier)
                          .state = id,
                      onAdd: () => context.push('/family/new'),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: PatientRecordBody(patient: selected),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The selected member, or the first one when nothing has been chosen — and
  /// the first one again when the chosen member has been removed on another
  /// device. Never null once the family is non-empty, so Home cannot paint an
  /// empty record with a full strip above it.
  Patient _resolveSelection(List<Patient> patients) {
    final id = ref.watch(selectedMemberProvider);
    for (final p in patients) {
      if (p.id == id) return p;
    }
    return patients.first;
  }
}
