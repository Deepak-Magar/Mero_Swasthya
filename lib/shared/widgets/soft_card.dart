import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The one container the whole app groups things in.
///
/// It replaces `Card`, `Container(border: …)` and every ad-hoc
/// `BoxDecoration` that used to be written inline per screen. There is exactly
/// one shadow definition in the app and it lives here, which is what keeps
/// twelve screens looking like one product.
///
/// The look: a white surface lifted off the page by a wide, very faint shadow —
/// 5 % black, 20 px blur, 4 px down. Depth instead of an outline. A 1 px border
/// draws a line the eye has to cross; a soft shadow just says "this is one
/// thing", which is the whole point of the container.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.accent,
    this.color,
    this.borderRadius,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// When set, the whole card is one tap target. Keeps the ripple clipped to
  /// the same radius as the shadow so a press does not square off the corners.
  final VoidCallback? onTap;

  /// A 4 px coloured bar down the leading edge.
  ///
  /// Reserved for rows that carry clinical weight — a triage-coloured timeline
  /// item, an overdue contact. Spec §16 does not let colour stand alone, so an
  /// accent never appears without an icon or a word beside it.
  final Color? accent;

  /// Overrides the surface. Used by the tinted variants — a triage banner, the
  /// demo-OTP notice — which are still SoftCards, just not white ones.
  final Color? color;

  final BorderRadius? borderRadius;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius =
        borderRadius ?? BorderRadius.circular(AppSpacing.radius);

    Widget content = Padding(padding: padding, child: child);

    if (accent != null) {
      // The accent is a *border on the content*, not a sibling box in a Row.
      //
      // The obvious spelling — `Row(crossAxisAlignment: stretch, [Container(
      // width: 4), Expanded(content)])` — asks the 4 px bar to match its
      // sibling's height. Inside a `ListView` the incoming height constraint is
      // unbounded, so "match your sibling" resolves to infinity: in debug that
      // trips an assertion, and in a **release** build, where assertions are
      // compiled out, the row silently lays out infinitely tall. The card
      // vanishes and the list scrolls through an empty void.
      //
      // Found on the phone, in release, on S09: every triaged timeline row was
      // invisible while the untriaged ones rendered fine. A left `BorderSide`
      // paints down whatever height the content turns out to be and needs no
      // intrinsic pass, so there is nothing to resolve against infinity.
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: accent!, width: 4)),
        ),
        child: content,
      );
    }

    // The shadow is painted by a `DecoratedBox` that draws no fill, and the
    // fill and the clip come from the `Material` inside it. Doing it this way
    // round matters: a tappable card wraps its content in an `InkWell` rather
    // than laying one over the top, so a button *inside* the card — S12's call
    // button on a red referral, S21's "ANC contact 3" — still receives its own
    // taps. An overlay would have swallowed them silently.
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: color ?? scheme.surface,
        borderRadius: radius,
        // The clip is what lets the accent bar reach the card's rounded
        // corners instead of poking out of them.
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );

    if (margin != null) card = Padding(padding: margin!, child: card);
    if (semanticLabel != null) {
      card = Semantics(
        label: semanticLabel,
        button: onTap != null,
        child: card,
      );
    }
    return card;
  }
}

/// A small-caps heading above a group of cards.
///
/// The app has no dividers any more, so a section is announced rather than
/// fenced: a quiet 12 px tracked label, then whitespace, then the content.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: style,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A quiet label with its value beside it: "Expected delivery date  2083-07-23".
///
/// It exists because the obvious spelling — `Row(children: [Text(label),
/// Text(value)])` — overflows. Both halves are free text in two languages, and
/// "Expected delivery date" plus a Bikram Sambat date is already wider than a
/// card on a 360 dp phone before Devanagari is involved. Both sides are
/// [Flexible] so the pair wraps instead of running off the edge.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});

  final String label;

  /// A widget rather than a string, because most of these values are a
  /// [BsDateText] that has to do its own Bikram Sambat formatting.
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.tight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: value),
        ],
      ),
    );
  }
}

/// One statistic: a big number over a quiet label.
///
/// Used for the S21 vitals grid and the Tier 2 dashboard. Tabular figures so a
/// column of numbers lines up on the decimal rather than jittering.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.tight),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge?.copyWith(
                  color: valueColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!, style: text.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

/// A square-ish tap target with an icon over a label — the S08 quick actions
/// and the S19 provider tiles.
///
/// Sized so the icon, the gap and two lines of Devanagari all fit at 360 dp
/// width with four tiles across.
class SoftTile extends StatelessWidget {
  const SoftTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.foreground,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The tile's ground. Defaults to the brand's pale blue.
  final Color? tint;

  /// The icon and label colour. Defaults to brand blue.
  final Color? foreground;

  /// A dot or count in the corner — an overdue contact, an unread reminder.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.brandOf(context);
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: tint ?? AppColors.brandTintOf(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: AppSpacing.md,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 26, color: fg),
                      if (badge != null)
                        Positioned(right: -6, top: -4, child: badge!),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Two lines at the tile's own width, and only then shrunk.
                  //
                  // Four tiles across a 393 dp phone leave about 70 dp of text
                  // per tile, and "Documents" needs a little more than that —
                  // on the device it wrapped and left a single orphaned "s" on
                  // the second line. Forcing one line fixed that but let long
                  // Nepali labels shrink without a floor: "मेरो रेकर्ड कसले
                  // हेर्‍यो" came out at roughly half the size of the tile
                  // next to it. Wrapping inside the tile's real width first
                  // keeps the type at size for every label that fits in two
                  // lines, and the FittedBox is left as the last resort so
                  // nothing is ever ellipsed away.
                  LayoutBuilder(
                    builder: (context, box) => FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: box.maxWidth),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: fg,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill: tinted ground, optional leading icon, short bold label.
///
/// This is the app's one chip shape — allergies, triage level, sync state,
/// "pregnant · week 30", a document type. Keeping them identical is what stops
/// the record screens turning into a bag of mismatched badges.
class SoftPill extends StatelessWidget {
  const SoftPill({
    super.key,
    required this.label,
    this.icon,
    this.foreground,
    this.background,
    this.onTap,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? foreground;
  final Color? background;
  final VoidCallback? onTap;

  /// Slightly tighter, for a chip sitting inside another card's header.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.brandOf(context);
    final bg = background ?? AppColors.brandTintOf(context);

    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 6,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: dense ? 11 : 12.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: pill,
    );
  }
}

/// One block of a long form: a tracked header, then a [SoftCard] holding the
/// fields.
///
/// This is what replaced the `Divider(height: 32)` that used to separate the
/// parts of S22 and S13. A rule says "something changes here"; a heading over a
/// card says *what* changes, and a provider scrolling a seven-part form needs
/// the second one.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    this.title,
    required this.children,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  /// Null renders the card with no heading.
  ///
  /// The first block of a form usually needs none — the app bar has just said
  /// what the screen is, and "FULL NAME" over a card holding a name, a sex, a
  /// date of birth and a blood group labels one field and mis-labels four.
  final String? title;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) SectionHeader(title!, trailing: trailing),
          SoftCard(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A two-column grid of stacked number steppers.
///
/// Two columns rather than three: at 360 dp a third column leaves about 90 dp
/// per cell, which is not enough for a Devanagari vitals label and two 48 dp
/// bump buttons, and the label is the first thing that would be ellipsed away.
class StepperGrid extends StatelessWidget {
  const StepperGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: i + 1 < children.length
                    ? children[i + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A single-row segmented control.
///
/// Hand-rolled rather than Material's `SegmentedButton` because the medicine
/// frequency has six options (OD / BD / TDS / QID / SOS / HS) and
/// `SegmentedButton` sizes each segment to its content and then overflows.
/// Equal-width [Expanded] segments with a scaled-down label always fit, which
/// matters more here than matching Material's metrics exactly.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.skeleton,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: _Segment(
                label: labelOf(value),
                selected: value == selected,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brandOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.sm + 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? AppColors.onBrandOf(context)
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The save bar pinned to the bottom of a long form.
///
/// It carries the same upward shadow as the S21 action bar so that "the thing
/// you press to finish" looks identical wherever it appears, and it sits inside
/// a [SafeArea] so a gesture-navigation bar cannot swallow the tap.
class StickySaveBar extends StatelessWidget {
  const StickySaveBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.leading,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  /// An extra control to the left of the save button — S13 puts its triage
  /// banner above this bar rather than inside it, but the referral call button
  /// belongs beside the save.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onBrandOf(context),
                          ),
                        )
                      : Text(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page gutter, applied once per screen rather than per widget.
class PageGutter extends StatelessWidget {
  const PageGutter({
    super.key,
    required this.child,
    this.top = AppSpacing.sm,
    this.bottom = AppSpacing.xl,
  });

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        top,
        AppSpacing.gutter,
        bottom,
      ),
      child: child,
    );
  }
}
