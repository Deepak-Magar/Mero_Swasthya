import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';

/// One card in a first-run tour.
class CoachMark {
  const CoachMark({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

/// The two tours, named so the "seen" flag and the widget cannot drift apart.
class CoachTour {
  const CoachTour._();

  static const String patient = 'patient';
  static const String provider = 'provider';
}

/// A first-run tour: at most three cards, dismissable at any point, shown once.
///
/// Three rules it follows, all of them the reason coach marks usually fail:
///
///  * **It never blocks the app.** The scrim is tappable-through only on Skip,
///    but Skip is always on screen, the navigation bar underneath stays live
///    (see `ShellScaffold.overlay`), and the flag is written the moment the tour
///    is dismissed by *any* route out of it — Skip, Got it, or the last Next.
///  * **It says something the screen does not.** "This is your family" is
///    paired with what the strip is *for*; "Health workers scan here" explains
///    that everything after the scan works with no signal. A card that only
///    names what is already labelled is noise.
///  * **It is not a substitute for labels.** The tour exists on top of an
///    interface where every destination already has a word under it. If the
///    coach marks were load-bearing, the navigation would be wrong.
///
/// The flag lives in shared preferences via [AppConfig], so it survives a
/// relaunch and is cleared by a reinstall — a fresh install of the app should
/// explain itself again.
class CoachMarks extends ConsumerStatefulWidget {
  const CoachMarks({super.key, required this.tour, required this.marks});

  /// [CoachTour.patient] or [CoachTour.provider].
  final String tour;

  /// At most three. Anything longer is a manual, and nobody reads a manual on
  /// a phone handed to them in a queue.
  final List<CoachMark> marks;

  @override
  ConsumerState<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends ConsumerState<CoachMarks> {
  /// null until the preference has been read — the overlay must not flash on
  /// screen for a user who dismissed it last week.
  bool? _show;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    final seen = ref.read(appConfigProvider).coachSeen(widget.tour);
    _show = !seen && widget.marks.isNotEmpty;
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    // Fire and forget after the frame: the flag is a convenience, and making
    // the user wait on a preference write to close a card would be absurd.
    await ref.read(appConfigProvider).setCoachSeen(widget.tour);
  }

  void _next() {
    if (_step + 1 >= widget.marks.length) {
      _dismiss();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    if (_show != true) return const SizedBox.shrink();

    final l10n = L.of(context);
    final mark = widget.marks[_step];
    final isLast = _step + 1 >= widget.marks.length;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.brandTintOf(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            mark.icon,
                            size: 24,
                            color: AppColors.brandOf(context),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(mark.title, style: text.titleMedium),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      mark.body,
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        // The dots are the only thing that says how long this
                        // is going to take, which is the first thing anybody
                        // wants to know about an overlay.
                        for (var i = 0; i < widget.marks.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Container(
                            width: i == _step ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? AppColors.brandOf(context)
                                  : AppColors.skeleton,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                        const Spacer(),
                        // Skip stays available on every card, including the
                        // last one, so the tour is never a gate.
                        TextButton(
                          onPressed: _dismiss,
                          style: TextButton.styleFrom(
                            minimumSize:
                                const Size(0, AppTheme.minTapTarget),
                          ),
                          child: Text(l10n.coachSkip),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton(
                          onPressed: _next,
                          // The theme makes buttons full-width by default,
                          // which is an infinite width inside a Row.
                          style: FilledButton.styleFrom(
                            minimumSize:
                                const Size(0, AppTheme.minTapTarget),
                          ),
                          child: Text(isLast ? l10n.coachDone : l10n.coachNext),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
