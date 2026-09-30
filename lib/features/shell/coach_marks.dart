import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';

/// One card in a first-run tour.
class CoachMark {
  const CoachMark({
    required this.icon,
    required this.title,
    required this.body,
    this.target,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The widget this card is about, if it is about one in particular.
  ///
  /// When the key is mounted and on screen the scrim is cut away around it, so
  /// the card is visibly *pointing* at something rather than describing it from
  /// across the screen. Null, or a target that is scrolled out of view, leaves
  /// the plain scrim — the card still reads on its own.
  final GlobalKey? target;
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

  /// Where the current card's target sits inside this overlay, once measured.
  Rect? _targetRect;

  /// Where the card itself sits, so a tall target is not lit underneath it.
  Rect? _cardRect;

  final GlobalKey _cardKey = GlobalKey();
  bool _tracking = false;

  @override
  void initState() {
    super.initState();
    final seen = ref.read(appConfigProvider).coachSeen(widget.tour);
    _show = !seen && widget.marks.isNotEmpty;
  }

  /// Keeps [_targetRect] in step with the layout underneath.
  ///
  /// Re-armed after every frame for as long as a card with a target is up. A
  /// post-frame callback does not ask for a frame, so this costs nothing while
  /// the screen is still — but the list under the scrim is fed by streams, and
  /// a banner arriving above it moves the thing being pointed at.
  void _trackTarget() {
    if (_tracking) return;
    _tracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tracking = false;
      if (!mounted || _show != true) return;
      final key = widget.marks[_step].target;
      if (key == null) return;

      final target = _rectOf(key);
      final card = _rectOf(_cardKey);
      if (target != _targetRect || card != _cardRect) {
        setState(() {
          _targetRect = target;
          _cardRect = card;
        });
      }
      _trackTarget();
    });
  }

  /// [key]'s box in this overlay's coordinates, or null when it is not laid
  /// out or not on screen.
  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    final own = context.findRenderObject();
    if (box is! RenderBox || own is! RenderBox) return null;
    if (!box.attached || !box.hasSize || !own.hasSize) return null;

    final rect = own.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
    return (Offset.zero & own.size).overlaps(rect) ? rect : null;
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
    setState(() {
      _step++;
      // The next card points somewhere else; the old cut-out must not be lit
      // under it for a frame.
      _targetRect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_show != true) return const SizedBox.shrink();

    final l10n = L.of(context);
    final mark = widget.marks[_step];
    final isLast = _step + 1 >= widget.marks.length;
    final text = Theme.of(context).textTheme;

    if (mark.target != null) _trackTarget();

    final card = Container(
      key: _cardKey,
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
              // The dots are the only thing that says how long this is going
              // to take, which is the first thing anybody wants to know about
              // an overlay.
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
              // Skip stays available on every card, including the last one, so
              // the tour is never a gate.
              TextButton(
                onPressed: _dismiss,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTapTarget),
                ),
                child: Text(l10n.coachSkip),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _next,
                // The theme makes buttons full-width by default, which is an
                // infinite width inside a Row.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.minTapTarget),
                ),
                child: Text(isLast ? l10n.coachDone : l10n.coachNext),
              ),
            ],
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final target = mark.target == null ? null : _targetRect;

        // The card lives at the bottom of the screen, where the thumb is —
        // unless that is where the thing it points at lives, in which case it
        // moves up to sit directly above it.
        final cardAbove = target != null && target.center.dy > size.height / 2;

        var hole = target?.inflate(6);
        if (hole != null && !cardAbove && _cardRect != null) {
          // Light the target only down to the card: a list five rows tall
          // would otherwise glow out from underneath the text explaining it.
          final limit = _cardRect!.top - AppSpacing.md;
          hole = limit - hole.top < AppTheme.minTapTarget
              ? null
              : Rect.fromLTRB(
                  hole.left,
                  hole.top,
                  hole.right,
                  math.min(hole.bottom, limit),
                );
        }

        final gap = cardAbove
            ? math.max(
                0.0,
                size.height -
                    target.top +
                    AppSpacing.lg -
                    AppSpacing.gutter -
                    MediaQuery.paddingOf(context).bottom,
              )
            : 0.0;

        return CustomPaint(
          painter: _ScrimPainter(hole: hole),
          // Transparent, but still a Material: it is what swallows a tap on
          // the scrim, so the screen underneath cannot be operated by accident
          // through a tour the user has not dismissed.
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    card,
                    if (gap > 0) SizedBox(height: gap),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The tour's scrim, with the current card's target cut out of it.
///
/// Painted rather than stacked from four boxes for the reason the scanner's
/// viewfinder is: a real rounded hole, and no seams where the pieces meet.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.hole});

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }

    // A round target gets a round window; anything else a card-shaped one.
    final round = (hole.width - hole.height).abs() < 4;
    final window = RRect.fromRectAndRadius(
      hole,
      Radius.circular(round ? hole.shortestSide / 2 : AppSpacing.radius),
    );

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      scrim,
    );
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.onBrand.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
