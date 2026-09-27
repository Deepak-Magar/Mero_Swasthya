import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// One destination in a role's bottom navigation bar.
///
/// [label] is not optional and there is no icon-only variant, deliberately. The
/// audit's first two findings were both features hidden behind a bare glyph;
/// a tab bar is the last place in the app that should repeat that mistake.
class ShellTab {
  const ShellTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.builder,
  });

  final IconData icon;

  /// The filled counterpart, shown while this tab is the current one.
  final IconData selectedIcon;

  final String label;

  /// Built on demand rather than held in an `IndexedStack`.
  ///
  /// This is load-bearing on the provider side: the Scan tab *is* the camera,
  /// and an `IndexedStack` would keep `MobileScannerController` running — and
  /// the torch available — while the provider reads a dashboard on another tab.
  /// Building one tab at a time means leaving Scan disposes the camera, which
  /// is both the correct behaviour and the one the battery wants.
  ///
  /// The cost is a scroll position: coming back to a tab rebuilds it at the
  /// top. On four short screens driven by Drift streams that is not a cost
  /// worth an always-live camera.
  final WidgetBuilder builder;
}

/// Lets a screen inside the shell move between tabs.
///
/// Home's tiles for Timeline and Documents should *switch tabs* rather than
/// push a second copy of a screen that is already one tap away — otherwise the
/// back stack fills up with duplicates of the Records tab.
///
/// `maybeOf` rather than `of`, because the same screens are also reachable as
/// pushed routes (`/patient/:id/timeline` from the provider side) and in widget
/// tests, where there is no shell. Callers fall back to pushing.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.index,
    required this.select,
    required super.child,
  });

  /// The tab currently on screen.
  final int index;

  /// Move to a tab by its index in the shell's `tabs` list.
  final void Function(int index) select;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => old.index != index;
}

/// The bottom-navigation host for a role.
///
/// Three things it is responsible for, all of them things the audit found
/// missing:
///
///  * **Flat reach.** Every tab is one tap from every other tab, so nothing
///    that belongs on the surface can end up three levels down.
///  * **Labelled destinations.** Text under every icon, in both languages.
///  * **Back that never traps.** Android back from any tab returns to the first
///    tab; from the first tab it leaves the app. It never pops the shell out
///    from under a tab, and it never dead-ends.
class ShellScaffold extends StatefulWidget {
  const ShellScaffold({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.overlay,
  });

  final List<ShellTab> tabs;

  /// Which tab opens first. The provider shell opens on Scan, because that is
  /// why the phone came out of the pocket.
  final int initialIndex;

  /// Drawn above the current tab and below the navigation bar — the first-run
  /// coach marks. A builder so it can be told which tab is showing.
  final Widget Function(BuildContext context, int index)? overlay;

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  late int _index = widget.initialIndex.clamp(0, widget.tabs.length - 1);

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The shell is the root route of its branch, so letting the pop through
      // on the home tab is what exits the app — which is exactly what a user
      // pressing back on a home screen expects.
      canPop: _index == widget.initialIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _index = widget.initialIndex);
      },
      child: ShellScope(
        index: _index,
        select: _select,
        child: Stack(
          children: [
            // Keyed by index so switching tabs builds a fresh element tree
            // rather than trying to reuse the previous tab's state for a
            // different screen.
            KeyedSubtree(
              key: ValueKey<int>(_index),
              child: Scaffold(
                // A Builder so the tab's own context is below `ShellScope` and
                // can read it; the shell's build context is above it.
                body: Builder(builder: widget.tabs[_index].builder),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  destinations: [
                    for (final t in widget.tabs)
                      NavigationDestination(
                        icon: Icon(t.icon),
                        selectedIcon: Icon(t.selectedIcon),
                        // Never icon-only, and never ellipsed: a destination
                        // whose label has been cut in half is an icon with
                        // decoration.
                        label: t.label,
                        tooltip: t.label,
                      ),
                  ],
                ),
              ),
            ),
            if (widget.overlay != null)
              Positioned.fill(
                // The navigation bar stays reachable under the coach marks, so
                // a user who ignores them is not held hostage by them.
                bottom: AppTheme.navBarHeight,
                child: widget.overlay!(context, _index),
              ),
          ],
        ),
      ),
    );
  }
}
