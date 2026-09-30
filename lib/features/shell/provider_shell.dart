import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'coach_marks.dart';

/// The provider side's locations, in one place so the shell, the Home tiles
/// and the tests cannot spell them three different ways.
class ProviderTabs {
  const ProviderTabs._();

  static const String home = '/provider';
  static const String patients = '/provider/patients';
  static const String reminders = '/provider/reminders';
  static const String more = '/provider/more';

  /// Not a tab: the scanner is pushed over the shell from the centre button,
  /// so the camera is never left running behind a list.
  static const String scan = '/provider/scan';

  /// The four branches, in bar order. `StatefulShellRoute` indexes by this.
  static const List<String> branches = [home, patients, reminders, more];
}

/// What the provider tour points at.
///
/// Keys rather than widget references, because the tour is drawn by the shell
/// and the "Needs attention" list is drawn by the Home tab, two widgets that
/// otherwise know nothing about each other.
class ProviderCoachTargets {
  const ProviderCoachTargets._();

  static final GlobalKey scanButton = GlobalKey(debugLabel: 'coach:scan');
  static final GlobalKey needsAttention =
      GlobalKey(debugLabel: 'coach:attention');
}

/// The provider side: Home · Patients · [Scan] · Reminders · More.
///
/// Four tabs in a `StatefulShellRoute`, and a raised brand-blue Scan button
/// docked in the middle of the bar. The button is the same on every tab — a
/// health worker's phone comes out of the pocket to scan, and that must never
/// depend on which tab was left open.
///
/// Two consequences of the scanner no longer being a tab:
///
///  * The branches can live in an `IndexedStack`, so switching tabs keeps a
///    list's scroll position. The old shell built one tab at a time because
///    its first tab *was* the camera.
///  * The camera is pushed on the root navigator and popped when the summary
///    is done with, which is the lifecycle a `MobileScannerController` wants.
///
/// Back from any tab returns to Home; back from Home leaves the shell to the
/// platform, which exits the app. The coach marks on Home cover the whole
/// shell, bar included, because the first card points at the Scan button.
class ProviderShell extends ConsumerWidget {
  const ProviderShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// The diameter of the centre button.
  static const double scanButtonSize = 60;

  void _select(WidgetRef ref, int index) {
    // The tabs stay mounted, so their streams keep the "now" they were
    // subscribed with. Coming back to a tab is the moment to ask again with
    // the current time — a phone left open overnight must not call
    // yesterday "today".
    switch (ProviderTabs.branches[index]) {
      case ProviderTabs.home || ProviderTabs.reminders:
        ref.invalidate(providerHomeProvider);
      case ProviderTabs.patients:
        ref.invalidate(grantedPatientsProvider);
    }
    // Always the branch root: nothing is pushed inside a branch, and a filter
    // Home applied to the Patients list must not survive a tap on the tab.
    navigationShell.goBranch(index, initialLocation: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final index = navigationShell.currentIndex;

    void openScanner() => context.push(ProviderTabs.scan);

    return PopScope(
      // On Home the pop goes through to the platform and exits the app; on
      // any other tab it is turned into "go to Home".
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(ref, 0);
      },
      child: Stack(
        children: [
          Scaffold(
            body: navigationShell,
            floatingActionButton: _ScanButton(
              key: ProviderCoachTargets.scanButton,
              label: l10n.providerScanQr,
              onPressed: openScanner,
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.centerDocked,
            bottomNavigationBar: _ProviderBar(
              index: index,
              onSelect: (i) => _select(ref, i),
              onScan: openScanner,
            ),
          ),
          if (index == 0)
            Positioned.fill(
              child: CoachMarks(
                tour: CoachTour.provider,
                marks: [
                  CoachMark(
                    icon: Icons.qr_code_scanner_rounded,
                    title: l10n.coachScanButtonTitle,
                    body: l10n.coachScanButtonBody,
                    target: ProviderCoachTargets.scanButton,
                  ),
                  CoachMark(
                    icon: Icons.warning_amber_rounded,
                    title: l10n.coachAttentionTitle,
                    body: l10n.coachAttentionBody,
                    target: ProviderCoachTargets.needsAttention,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The raised circular Scan button, docked into the bar's notch.
class _ScanButton extends StatelessWidget {
  const _ScanButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: ProviderShell.scanButtonSize,
      child: FloatingActionButton(
        // Two shells can be in the tree during a role switch; a shared default
        // hero tag would throw.
        heroTag: 'provider-scan',
        onPressed: onPressed,
        tooltip: label,
        shape: const CircleBorder(),
        elevation: 4,
        highlightElevation: 6,
        child: const Icon(Icons.qr_code_scanner_rounded, size: 28),
      ),
    );
  }
}

/// The notched bar: two labelled tabs, the Scan label, two labelled tabs.
///
/// Hand-built rather than a `NavigationBar` because Material's bar has no
/// notch and no room for a docked button. It keeps the theme's metrics —
/// 68 dp tall, tinted pill behind the selected icon, 12 px label — so the two
/// roles' bars still read as one product.
class _ProviderBar extends StatelessWidget {
  const _ProviderBar({
    required this.index,
    required this.onSelect,
    required this.onScan,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    final tabs = [
      (Icons.home_outlined, Icons.home_rounded, l10n.navHome),
      (Icons.people_outline, Icons.people_rounded, l10n.navPatients),
      (
        Icons.notifications_none_rounded,
        Icons.notifications_rounded,
        l10n.navReminders,
      ),
      (Icons.more_horiz_outlined, Icons.more_horiz_rounded, l10n.navMore),
    ];

    Widget item(int i) => Expanded(
          child: _BarItem(
            icon: tabs[i].$1,
            selectedIcon: tabs[i].$2,
            label: tabs[i].$3,
            selected: index == i,
            onTap: () => onSelect(i),
          ),
        );

    // The labels are capped at 1.3× so the bar keeps its height on a phone
    // set to the largest font; that is also the largest scale the layout
    // tests run at.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: BottomAppBar(
        height: AppTheme.navBarHeight,
        padding: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.cardShadow,
        elevation: 12,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            item(0),
            item(1),
            // The button's own label. It sits under the docked circle in the
            // same place the other four labels sit, so the centre control is
            // a word as well as a glyph.
            SizedBox(
              width: ProviderShell.scanButtonSize + 16,
              child: GestureDetector(
                onTap: onScan,
                behavior: HitTestBehavior.opaque,
                child: ExcludeSemantics(
                  child: _BarLabel(
                    label: l10n.navScan,
                    selected: false,
                    // Leaves the top of the cell to the docked button.
                    leading: const SizedBox(height: _BarItem.indicatorHeight),
                  ),
                ),
              ),
            ),
            item(2),
            item(3),
          ],
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const double indicatorHeight = 30;

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brandOf(context);
    final quiet = AppColors.textSecondaryOf(context);

    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          child: ExcludeSemantics(
            child: _BarLabel(
              label: label,
              selected: selected,
              leading: Container(
                width: 56,
                height: indicatorHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.brandTintOf(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  size: 24,
                  color: selected ? brand : quiet,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [leading] over a one-line label — the shape every cell of the bar shares.
class _BarLabel extends StatelessWidget {
  const _BarLabel({
    required this.label,
    required this.selected,
    required this.leading,
  });

  final String label;
  final bool selected;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        const SizedBox(height: AppSpacing.tight),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          // Shrunk rather than ellipsed: a destination whose label has been
          // cut in half is an icon with decoration.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.brandOf(context)
                    : AppColors.textSecondaryOf(context),
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
