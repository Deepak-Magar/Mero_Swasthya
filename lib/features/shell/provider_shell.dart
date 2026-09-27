import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../provider/provider_home_screen.dart';
import '../provider/scan_screen.dart';
import 'coach_marks.dart';
import 'provider_more_tab.dart';
import 'shell_scaffold.dart';

/// The provider side, as three labelled tabs: Scan, Patients, More.
///
/// Scan is the landing tab, so the camera is up with no taps at all. That is
/// the single biggest change on this side of the app: the scanner used to be a
/// tile on a list screen, which meant the thing the phone came out of the
/// pocket for was always one tap behind something else.
///
/// The Scan tab holds a live [ScanScreen], and `ShellScaffold` builds only the
/// current tab — so leaving Scan disposes the camera rather than leaving it
/// running behind a dashboard.
class ProviderShell extends ConsumerWidget {
  const ProviderShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);

    return ShellScaffold(
      tabs: [
        ShellTab(
          icon: Icons.qr_code_scanner_outlined,
          selectedIcon: Icons.qr_code_scanner_rounded,
          label: l10n.navScan,
          builder: (_) => const ScanScreen(),
        ),
        ShellTab(
          icon: Icons.people_outline,
          selectedIcon: Icons.people_rounded,
          label: l10n.navPatients,
          builder: (_) => const ProviderHomeScreen(),
        ),
        ShellTab(
          icon: Icons.more_horiz_outlined,
          selectedIcon: Icons.more_horiz_rounded,
          label: l10n.navMore,
          builder: (_) => const ProviderMoreTab(),
        ),
      ],
      // Two cards, not three. A health worker was trained on this app; a
      // patient was handed it. Padding the tour out to three would be padding.
      overlay: (context, index) => index != 0
          ? const SizedBox.shrink()
          : CoachMarks(
              tour: CoachTour.provider,
              marks: [
                CoachMark(
                  icon: Icons.qr_code_scanner_rounded,
                  title: l10n.coachScanTitle,
                  body: l10n.coachScanBody,
                ),
                CoachMark(
                  icon: Icons.people_outline,
                  title: l10n.coachPatientsTitle,
                  body: l10n.coachPatientsBody,
                ),
              ],
            ),
    );
  }
}
