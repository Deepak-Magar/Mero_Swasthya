import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../domain/models/models.dart';
import '../auth/auth_controller.dart';
import '../documents/documents_screen.dart';
import '../shared/widgets/app_widgets.dart';
import '../timeline/timeline_screen.dart';
import 'coach_marks.dart';
import 'patient_home_tab.dart';
import 'patient_more_tab.dart';
import 'shell_scaffold.dart';

/// The patient side, as four labelled tabs.
///
/// Home, Records, Documents, More — the four things a family does with this app,
/// each one tap from each other one. Records and Documents are the existing
/// S09 and S10 screens, unchanged, given the selected member from
/// [selectedMemberProvider] rather than from a route parameter; that is what
/// lets a tab bar show them at all, since a tab has no path segment to carry an
/// id in.
class PatientShell extends ConsumerWidget {
  const PatientShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);

    return ShellScaffold(
      tabs: [
        ShellTab(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
          label: l10n.navHome,
          builder: (_) => const PatientHomeTab(),
        ),
        ShellTab(
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          label: l10n.navRecords,
          builder: (_) => const _SelectedMemberTab(kind: _TabKind.timeline),
        ),
        ShellTab(
          icon: Icons.folder_outlined,
          selectedIcon: Icons.folder_rounded,
          label: l10n.navDocuments,
          builder: (_) => const _SelectedMemberTab(kind: _TabKind.documents),
        ),
        ShellTab(
          icon: Icons.more_horiz_outlined,
          selectedIcon: Icons.more_horiz_rounded,
          label: l10n.navMore,
          builder: (_) => const PatientMoreTab(),
        ),
      ],
      // Three cards, once, on the Home tab only. Shown over Home rather than
      // spread across the tabs because a tour that makes the user change tabs
      // to finish it is a tour most people abandon halfway.
      overlay: (context, index) => index != 0
          ? const SizedBox.shrink()
          : CoachMarks(
              tour: CoachTour.patient,
              marks: [
                CoachMark(
                  icon: Icons.people_outline,
                  title: l10n.coachFamilyTitle,
                  body: l10n.coachFamilyBody,
                ),
                CoachMark(
                  icon: Icons.qr_code_2_rounded,
                  title: l10n.coachShareTitle,
                  body: l10n.coachShareBody,
                ),
                CoachMark(
                  icon: Icons.more_horiz_rounded,
                  title: l10n.coachMoreTitle,
                  body: l10n.coachMoreBody,
                ),
              ],
            ),
    );
  }
}

enum _TabKind { timeline, documents }

/// Hands the selected member to a screen that was written to take an id.
///
/// The empty case is its own state rather than an error: a phone with no family
/// member yet has a Records tab, and it has to say so and point at the thing
/// that fixes it.
class _SelectedMemberTab extends ConsumerWidget {
  const _SelectedMemberTab({required this.kind});

  final _TabKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final auth = ref.watch(authProvider);
    final family =
        ref.watch(familyProvider(auth.user?.id ?? '')).valueOrNull ?? const [];

    if (family.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            kind == _TabKind.timeline ? l10n.navRecords : l10n.navDocuments,
          ),
          actions: const [SyncPill.compact(), SizedBox(width: 8)],
        ),
        body: EmptyState(
          icon: Icons.people_outline,
          title: l10n.familyEmptyTitle,
          body: l10n.homeNoMemberBody,
          action: FilledButton.icon(
            onPressed: () => ShellScope.maybeOf(context)?.select(0),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.familyAddMember),
          ),
        ),
      );
    }

    final selectedId = ref.watch(selectedMemberProvider);
    final Patient patient = family.firstWhere(
      (p) => p.id == selectedId,
      orElse: () => family.first,
    );

    return switch (kind) {
      _TabKind.timeline => TimelineScreen(patientId: patient.id),
      _TabKind.documents => DocumentsScreen(patientId: patient.id),
    };
  }
}
