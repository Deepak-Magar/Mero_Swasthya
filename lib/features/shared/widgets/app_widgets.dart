import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/dates/bs_date.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/sync/sync_status.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/rules/triage.dart';
import '../../../shared/widgets/soft_card.dart';

/// The shared widgets spec §4 lists: `BsDateText`, `TriageBanner`, `SyncPill`,
/// `PicklistField`, `NumberStepper`, `OfflineBanner`.

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

/// Spec §13: Bikram Sambat primary, Gregorian secondary.
///
/// Nepali numerals only under the Nepali locale — a date written in Devanagari
/// digits to an English reader is unreadable, and the reverse is what the
/// ministry's own forms look like.
class BsDateText extends ConsumerWidget {
  const BsDateText(this.date, {super.key, this.style, this.showAd = true});

  /// Accepts either a `DateTime` or a wire `YYYY-MM-DD` string.
  final Object? date;
  final TextStyle? style;
  final bool showAd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = switch (date) {
      final DateTime d => d,
      final String s => BsDate.parseAd(s.length > 10 ? s.substring(0, 10) : s),
      _ => null,
    };
    if (value == null) return Text(L.of(context).commonNotSet, style: style);

    final nepali = Localizations.localeOf(context).languageCode == 'ne';
    return Text(
      showAd
          ? BsDate.formatBoth(value, nepaliDigits: nepali)
          : BsDate.formatBs(value, nepaliDigits: nepali),
      style: style,
    );
  }
}

// ---------------------------------------------------------------------------
// Triage
// ---------------------------------------------------------------------------

/// Spec §16: "Red triage banner uses colour AND an icon AND text."
///
/// Colour alone fails for the roughly one man in twelve with a colour vision
/// deficiency, and this banner is the one thing on the screen that decides
/// whether somebody is sent to hospital tonight.
class TriageBanner extends ConsumerWidget {
  const TriageBanner({super.key, required this.result});

  final TriageResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final level = result.level.wire;
    final nepali = Localizations.localeOf(context).languageCode == 'ne';

    final headline = switch (result.level) {
      TriageLevel.red => l10n.ancTriageRed,
      TriageLevel.amber => l10n.ancTriageAmber,
      TriageLevel.green => l10n.ancTriageGreen,
    };
    final reasons = nepali ? result.reasonsNp : result.reasonsEn;

    // The one place in the app that keeps a hard border and a filled icon.
    // Everywhere else groups with whitespace and a soft shadow; a banner that
    // may be telling somebody to go to hospital tonight is allowed to be the
    // loudest thing on the screen, and the 2 px edge is what makes it read as
    // an interruption rather than as one more card.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: TriageColors.bg(level),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: TriageColors.fg(level), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                TriageColors.icon(level),
                color: TriageColors.fg(level),
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  headline,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: TriageColors.fg(level),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final reason in reasons)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.tight),
                // The banner paints its own light background, so the reasons
                // have to name their own colour. Inheriting the theme's made
                // them light-grey-on-pale-red in dark mode — legible enough in
                // a screenshot, not on a phone in daylight, and these two
                // lines are the *reason* somebody is being sent to hospital.
                //
                // They take the darker `ink` rather than the signal colour the
                // headline uses: #DC2626 on #FEF2F2 measures 4.41:1, which is
                // fine for a 16 px bold headline and short of the 4.5:1 body
                // threshold for a wrapped sentence. Same hue, 7.60:1.
                child: Text(
                  '• $reason',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TriageColors.ink(level),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The coloured dot on the S12 contact stepper and the S09 timeline rows.
class TriageDot extends StatelessWidget {
  const TriageDot({super.key, required this.level, this.size = 12});

  final TriageLevel? level;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      TriageColors.icon(level?.wire),
      size: size + 6,
      color: TriageColors.fg(level?.wire),
    );
  }
}

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

/// Spec S17: "grey = offline, amber = N pending, green = synced."
///
/// A labelled, tappable pill that opens S17 — never a bare glyph. "Is what I
/// just wrote off this phone yet" is the question an offline-first app is asked
/// most often, and a cloud outline does not answer it. So the pill always
/// carries words, and in its full form it says *when*: "Synced 2 min ago",
/// "3 changes waiting", "Offline".
///
/// Two forms, because an app bar and a home screen have different room:
///
///  * [SyncPill.compact] — icon plus the state in one or two words. This is
///    what sits in `AppBar.actions`, where the title has to keep most of the
///    width and a Devanagari sentence would push the row off the edge.
///  * [SyncPill] — the full sentence with the relative time, used as a
///    full-width row on the two home tabs, where the question is actually
///    asked and there is room to answer it properly.
///
/// Both go to `/sync` and both are at least 48 dp tall.
class SyncPill extends ConsumerWidget {
  const SyncPill({super.key}) : compact = false;

  /// The app-bar form: icon plus the short state word.
  const SyncPill.compact({super.key}) : compact = true;

  final bool compact;

  /// "Synced 2 min ago" / "Not synced yet" — the green state's own words.
  ///
  /// Deliberately coarse. Nobody needs the second, and a clock that counts up
  /// in the app bar is a reason to look at the app bar.
  static String syncedLabel(L l10n, String? lastSyncAt, DateTime now) {
    final at = lastSyncAt == null ? null : DateTime.tryParse(lastSyncAt);
    if (at == null) return l10n.syncNeverYet;

    final elapsed = now.difference(at.toUtc().toLocal());
    // A clock that has drifted backwards must not print "synced in 3 minutes".
    if (elapsed.isNegative || elapsed.inMinutes < 1) return l10n.syncJustNow;
    if (elapsed.inMinutes < 60) return l10n.syncMinutesAgo(elapsed.inMinutes);
    if (elapsed.inHours < 24) return l10n.syncHoursAgo(elapsed.inHours);
    return l10n.syncDaysAgo(elapsed.inDays);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final status =
        ref.watch(syncStatusProvider).valueOrNull ?? const SyncStatus();

    final (icon, colour, tint) = switch (status.chip) {
      SyncChipState.offline => (
          Icons.cloud_off_outlined,
          AppColors.textSecondaryOf(context),
          AppColors.skeleton,
        ),
      SyncChipState.failed => (
          Icons.error_outline,
          TriageColors.red,
          TriageColors.redBg,
        ),
      SyncChipState.pending => (
          Icons.cloud_upload_outlined,
          TriageColors.amber,
          TriageColors.amberBg,
        ),
      SyncChipState.synced => (
          Icons.cloud_done_outlined,
          AppColors.brandGreen,
          AppColors.brandGreenTint,
        ),
    };

    final label = switch (status.chip) {
      SyncChipState.offline => l10n.commonOffline,
      SyncChipState.failed => l10n.syncFailed,
      // The count is the message either way; the wording differs only in how
      // much room there is to say it.
      SyncChipState.pending => compact
          ? l10n.syncPendingOps(status.pending)
          : l10n.syncChangesWaiting(status.pending),
      SyncChipState.synced => compact
          ? l10n.syncSynced
          : syncedLabel(l10n, status.lastSyncAt, DateTime.now()),
    };

    final glyph = status.running
        ? SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: colour),
          )
        : Icon(icon, size: 16, color: colour);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: () => context.push('/sync'),
        borderRadius: BorderRadius.circular(compact ? 999 : AppSpacing.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTheme.minTapTarget),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 0),
          alignment: Alignment.center,
          child: Container(
            width: compact ? null : double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: tint,
              borderRadius:
                  BorderRadius.circular(compact ? 999 : AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                glyph,
                const SizedBox(width: 6),
                // Flexible in the compact form so a long Nepali state word
                // shortens rather than pushing the app-bar row off the screen.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colour,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
                if (!compact)
                  Icon(Icons.chevron_right_rounded, size: 18, color: colour),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Spec §16: a persistent thin banner on provider screens while offline.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key, this.asOf});

  /// When the record on screen was last refreshed.
  final DateTime? asOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).valueOrNull;
    if (status == null || status.online) return const SizedBox.shrink();

    final l10n = L.of(context);
    final at = asOf ?? DateTime.now();
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

    return Material(
      color: TriageColors.amberBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: 10,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: AppColors.triageAmber,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.providerOfflineBanner(time),
                style: const TextStyle(
                  color: AppColors.onTriageAmber,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown above a record this device may look at but not write to — A.7's
/// printed card, which carries a `read` grant.
///
/// It is stated rather than implied: the write buttons are simply absent, and
/// without this a provider would reasonably conclude the app was broken.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandTintOf(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 20,
              color: AppColors.brandOf(context),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                L.of(context).providerReadOnlyBanner,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandOf(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small cloud beside a row that has not reached the server (spec §7).
class PendingDot extends ConsumerWidget {
  const PendingDot({super.key, required this.rowId});

  final String rowId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingRowIdsProvider).valueOrNull ?? const {};
    if (!pending.contains(rowId)) return const SizedBox.shrink();

    return Tooltip(
      message: L.of(context).commonPending,
      child: const Icon(
        Icons.cloud_upload_outlined,
        size: 16,
        color: AppColors.triageAmber,
      ),
    );
  }
}

/// Rings a facility by id, resolving its phone number from the cached list.
///
/// Spec S13 puts a call button on a red referral; S12 repeats it on the
/// dashboard. A health worker who has to copy a number into the dialer will not
/// call, so the number is never merely displayed.
///
/// Renders nothing when the facility has no phone on record — a dead button is
/// worse than none.
class FacilityCallButton extends ConsumerWidget {
  const FacilityCallButton({
    super.key,
    required this.facilityId,
    required this.label,
  });

  final String? facilityId;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (facilityId == null) return const SizedBox.shrink();

    final facilities = ref.watch(facilitiesProvider).valueOrNull ?? const [];
    final phone = facilities
        .where((f) => f.id == facilityId)
        .map((f) => f.phone)
        .firstOrNull;
    if (phone == null || phone.isEmpty) return const SizedBox.shrink();

    return FilledButton.icon(
      onPressed: () => launchUrl(Uri.parse('tel:$phone')),
      icon: const Icon(Icons.call_rounded, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.triageRed,
        foregroundColor: AppColors.onBrand,
        minimumSize: const Size(0, AppTheme.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Allergies
// ---------------------------------------------------------------------------

/// Spec §16: "Provider summary shows allergies in a red chip row at the top,
/// always, even if empty".
///
/// Always present, in both roles, so that "no chips" can never be mistaken for
/// "nobody has asked". An empty list is a green statement — *No known
/// allergies* — not blank space; blank space reads as missing data, and the
/// difference between "we checked and there are none" and "we do not know"
/// is the difference between giving the penicillin and not.
class AllergyChipRow extends StatelessWidget {
  const AllergyChipRow({
    super.key,
    required this.allergies,
    this.dense = false,
    this.singleLine = false,
  });

  final List<String> allergies;

  /// Tighter, for the S08 header cluster. The provider summary uses the full
  /// size — it is pinned there and is meant to be unmissable.
  final bool dense;

  /// Keep every chip on one line and scroll sideways instead of wrapping.
  ///
  /// The S21 pinned header has to declare a fixed height, and a row that can
  /// grow to two lines cannot live in one. Six allergies then scroll rather
  /// than being silently clipped — which, for allergies, would be the worst
  /// possible failure mode.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    if (allergies.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SoftPill(
          icon: Icons.check_circle_outline,
          label: l10n.patientHomeNoAllergies,
          foreground: AppColors.onTriageGreen,
          background: AppColors.triageGreenTint,
          dense: dense,
        ),
      );
    }

    final pills = [
      for (final allergy in allergies)
        SoftPill(
          label: allergy,
          foreground: AppColors.allergyRed,
          background: AppColors.allergyTint,
          dense: dense,
        ),
    ];

    return Row(
      crossAxisAlignment:
          singleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: singleLine ? 0 : (dense ? 3 : 5)),
          child: Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.dangerInkOf(context),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: singleLine
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < pills.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        pills[i],
                      ],
                    ],
                  ),
                )
              : Wrap(spacing: 6, runSpacing: 6, children: pills),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/// How a [NumberStepper] arranges its label and its controls.
enum NumberStepperLayout {
  /// Label on the left, controls on the right. Fits a full-width form row.
  row,

  /// Label above, controls beneath. What the S22 and S13 vitals grids use —
  /// at 360 dp a two-column grid gives each cell about 160 dp, and the row
  /// layout cannot fit a Devanagari label and three controls in that.
  stacked,
}

/// Spec §16: "never require typing for vitals". A big stepper either side of a
/// value, with a 48 dp tap target.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 400,
    this.step = 1,
    this.decimals = 0,
    this.suffix,
    this.layout = NumberStepperLayout.row,
  });

  final String label;
  final num? value;
  final ValueChanged<num?> onChanged;
  final num min;
  final num max;
  final num step;
  final int decimals;
  final String? suffix;
  final NumberStepperLayout layout;

  void _bump(num delta) {
    final next = (value ?? _startingPoint) + delta;
    if (next < min || next > max) return;
    onChanged(decimals == 0 ? next.round() : next);
  }

  /// Where the first tap lands.
  ///
  /// Starting from the middle of the range beats starting from zero — a weight
  /// stepper that begins at 0 kg needs sixty taps to reach a plausible number —
  /// but the midpoint is then **snapped onto the step grid**.
  ///
  /// Without that snap, BP systolic (60..250 by 2) started at 155 and could
  /// only ever produce odd numbers: 140, 150 and 160 were unreachable, and
  /// those are the exact thresholds spec A.5 triages on. Found on device.
  num get _startingPoint {
    final midpoint = min + (max - min) / 2;
    final steps = ((midpoint - min) / step).round();
    final snapped = min + steps * step;
    return decimals == 0 ? snapped.round() : snapped;
  }

  Future<void> _type(BuildContext context) async {
    final l10n = L.of(context);
    final controller = TextEditingController(
      text: value == null
          ? ''
          : (decimals == 0
              ? value!.round().toString()
              : value!.toStringAsFixed(decimals)),
    );

    final entered = await showDialog<num?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
          decoration: InputDecoration(suffixText: suffix),
          onSubmitted: (text) =>
              Navigator.of(context).pop(num.tryParse(text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(num.tryParse(controller.text.trim())),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );

    if (entered == null) return;
    // Out-of-range input is clamped rather than rejected: a mistyped 1500 is
    // better answered with 250 than with a silent no-op.
    onChanged(entered.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final display = value == null
        ? '—'
        : (decimals == 0
            ? value!.round().toString()
            : value!.toStringAsFixed(decimals));

    final isSet = value != null;

    final minus = IconButton.filledTonal(
      onPressed: () => _bump(-step),
      icon: const Icon(Icons.remove_rounded),
      tooltip: '$label −$step',
      style: _bumpStyle(context),
    );

    final plus = IconButton.filledTonal(
      onPressed: () => _bump(step),
      icon: const Icon(Icons.add_rounded),
      tooltip: '$label +$step',
      style: _bumpStyle(context),
    );

    // Spec §16 says never *require* typing for vitals; it does not say to make
    // a value unreachable. The steppers carry the common case and a tap on the
    // number handles anything off the step grid — an odd diastolic, say.
    //
    // The number is the loudest thing in the control: a vitals grid is read at
    // a glance, so the figure gets the weight and the label stays quiet.
    Widget readout(double width) => InkWell(
          onTap: () => _type(context),
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: SizedBox(
            width: width,
            height: AppTheme.minTapTarget,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  suffix == null ? display : '$display $suffix',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: isSet
                            ? Theme.of(context).colorScheme.onSurface
                            : AppColors.textSecondaryOf(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: AppColors.textSecondaryOf(context),
                      ),
                ),
              ),
            ),
          ),
        );

    final clear = isSet
        ? IconButton(
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.backspace_outlined, size: 18),
            tooltip: L.of(context).commonRemove,
          )
        : null;

    if (layout == NumberStepperLayout.stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (clear != null)
                SizedBox(width: 32, height: 32, child: clear),
            ],
          ),
          const SizedBox(height: AppSpacing.tight),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [minus, Expanded(child: readout(double.infinity)), plus],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        minus,
        readout(72),
        plus,
        ?clear,
      ],
    );
  }

  /// The two bump buttons carry the brand tint rather than the M3 default
  /// surface-variant, which on a white card was barely a button at all.
  ///
  /// A function of the context, not a `static final`: the brand colour differs
  /// between light and dark, and a field evaluated once at class-load would
  /// freeze whichever theme happened to be up first.
  static ButtonStyle _bumpStyle(BuildContext context) => IconButton.styleFrom(
        backgroundColor: AppColors.brandTintOf(context),
        foregroundColor: AppColors.brandOf(context),
        minimumSize: const Size.square(AppTheme.minTapTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      );
}

/// A searchable single- or multi-select over a codelist (spec S07, S13, S22).
class PicklistField<T> extends StatelessWidget {
  const PicklistField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.multi = false,
    this.enabled = true,
  });

  final String label;
  final List<T> options;
  final List<T> selected;
  final ValueChanged<List<T>> onChanged;
  final String Function(T) labelOf;
  final bool multi;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<List<T>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PicklistSheet<T>(
        label: label,
        options: options,
        selected: selected,
        labelOf: labelOf,
        multi: multi,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: selected.isEmpty
            ? Text(
                l10n.commonSelect,
                style: TextStyle(color: AppColors.textSecondaryOf(context)),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in selected) SoftPill(label: labelOf(item)),
                ],
              ),
      ),
    );
  }
}

class _PicklistSheet<T> extends StatefulWidget {
  const _PicklistSheet({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.multi,
  });

  final String label;
  final List<T> options;
  final List<T> selected;
  final String Function(T) labelOf;
  final bool multi;

  @override
  State<_PicklistSheet<T>> createState() => _PicklistSheetState<T>();
}

class _PicklistSheetState<T> extends State<_PicklistSheet<T>> {
  late final List<T> _selected = [...widget.selected];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final matches = widget.options
        .where((o) =>
            _query.isEmpty ||
            widget.labelOf(o).toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: l10n.commonSearch,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final option = matches[index];
                  final isSelected = _selected.contains(option);

                  return widget.multi
                      ? CheckboxListTile(
                          value: isSelected,
                          title: Text(widget.labelOf(option)),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selected.add(option);
                            } else {
                              _selected.remove(option);
                            }
                          }),
                        )
                      : ListTile(
                          title: Text(widget.labelOf(option)),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: AppColors.successInkOf(context),
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(<T>[option]),
                        );
                },
              ),
            ),
            if (widget.multi)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: Text(l10n.commonOk),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// Spec §16: "empty-state illustration with a one-line message and the primary
/// action".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The glyph sits in its own tinted disc rather than floating as a
            // grey outline. An empty list should look deliberate, not broken.
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.brandTintOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: AppColors.brandOf(context)),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            if (body != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Spec §16: "skeleton loader → content".
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    // Skeleton rows are SoftCards with their content greyed out, not grey
    // slabs: the placeholder has the same silhouette as what replaces it, so
    // the list does not jump when the data lands.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.xl,
      ),
      itemCount: rows,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: const SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBar.wide,
              SizedBox(height: AppSpacing.sm),
              _SkeletonBar.narrow,
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  static const _SkeletonBar wide = _SkeletonBar(width: 160, height: 16);
  static const _SkeletonBar narrow = _SkeletonBar(width: 96, height: 12);

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeleton,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    return EmptyState(
      icon: Icons.error_outline,
      title: localizedError(l10n, error),
      action: onRetry == null
          ? null
          : FilledButton.tonal(onPressed: onRetry, child: Text(l10n.commonRetry)),
    );
  }
}

/// `AsyncValue.when` with the project's three states, so no screen invents its
/// own spinner.
Widget asyncView<T>(
  AsyncValue<T> value, {
  required Widget Function(T data) data,
  VoidCallback? onRetry,
  int skeletonRows = 4,
}) {
  return value.when(
    data: data,
    loading: () => LoadingList(rows: skeletonRows),
    error: (error, _) => ErrorState(error: error, onRetry: onRetry),
  );
}

/// Spec §16: "save locally, pop the screen, show snackbar 'Saved · will sync'
/// (or 'Saved · synced' if online and push succeeded within 2 s)".
///
/// Call it *before* popping and do not await it. It shows "will sync"
/// immediately, then watches the outbox for up to [within]; if the op clears,
/// the message is replaced with "synced". The user is never made to wait — the
/// row was already durable before this was called.
///
/// It holds the [ScaffoldMessengerState] rather than a [BuildContext] because
/// the screen is about to be popped and its context will be defunct.
void showSaveResult(
  ScaffoldMessengerState messenger,
  L l10n,
  AppDatabase db, {
  required String rowId,
  Duration within = const Duration(seconds: 2),
}) {
  void show(String text) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  show(l10n.commonSavedWillSync);

  unawaited(() async {
    final deadline = DateTime.now().add(within);
    while (DateTime.now().isBefore(deadline)) {
      if (!await db.outboxDao.hasPendingOp(rowId)) {
        show(l10n.commonSavedSynced);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }());
}

/// Spec §16: "Saved · will sync" (or "· synced" when it already went).
void showSavedSnackBar(BuildContext context, {bool synced = false}) {
  final l10n = L.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(synced ? l10n.commonSavedSynced : l10n.commonSavedWillSync),
        duration: const Duration(seconds: 2),
      ),
    );
}

void showErrorSnackBar(BuildContext context, Object error, {bool isWrite = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(localizedError(L.of(context), error, isWrite: isWrite))),
    );
}
