import 'package:flutter/material.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/edd.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';

/// The horizontal family strip along the top of the patient Home tab.
///
/// This replaces S06's full-screen list. The audit's finding was that switching
/// member cost a trip out to a list and back, which put the record — the thing
/// the app is for — one level below a directory of people. A strip keeps every
/// member visible *while* their record is on screen, so switching is a single
/// tap with no navigation at all.
///
/// "Add family member" is the last chip rather than a floating button: it
/// belongs to this row of people, and a FAB over a record would compete with
/// Share record, which is the one action that gets to be loud.
class FamilyStrip extends StatelessWidget {
  const FamilyStrip({
    super.key,
    required this.members,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Patient> members;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  static const double height = 104;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        children: [
          for (final member in members) ...[
            _MemberChip(
              patient: member,
              selected: member.id == selectedId,
              onTap: () => onSelect(member.id),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          _AddChip(label: l10n.familyAddMember, onTap: onAdd),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.patient,
    required this.selected,
    required this.onTap,
  });

  final Patient patient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brandOf(context);
    final icon = switch (patient.sex) {
      Sex.female => Icons.woman_outlined,
      Sex.male => Icons.man_outlined,
      Sex.other => Icons.person_outline,
    };

    return Semantics(
      button: true,
      selected: selected,
      label: patient.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: SizedBox(
          // Wide enough for two lines of a Devanagari given name at 11 px
          // without the label being shrunk away, and narrow enough that four
          // members fit on a 360 dp phone with the fifth peeking.
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.brandTintOf(context),
                  shape: BoxShape.circle,
                  // A ring rather than a colour swap: the avatars must stay
                  // recognisable as the same row of people, with one of them
                  // marked.
                  border: selected
                      ? Border.all(color: brand, width: 2.5)
                      : Border.all(color: Colors.transparent, width: 2.5),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(child: Icon(icon, size: 26, color: brand)),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: PendingDot(rowId: patient.id),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.tight),
              Text(
                // Given name only. The strip is a row of faces, not a register,
                // and a full Nepali name at 11 px over 72 dp is unreadable.
                patient.name.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? brand : AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: secondary.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.person_add_alt_1_rounded,
                    size: 24, color: secondary),
              ),
              const SizedBox(height: AppSpacing.tight),
              Text(
                // "Add family member" is three words too long for 72 dp, so
                // the chip carries the verb and the semantic label carries the
                // sentence. The verb is its own key: Nepali puts it last, so
                // the first word of the sentence would read "family's".
                L.of(context).commonAdd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Pregnant · week N" while it is open, "Delivered" once S14 has closed it.
///
/// A pregnancy that ended is still the most useful thing on the card for weeks
/// afterwards — it is what postnatal care hangs off — so the badge changes
/// rather than disappearing.
class PregnantBadge extends StatelessWidget {
  const PregnantBadge({super.key, required this.pregnancy});

  final Pregnancy pregnancy;

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    if (pregnancy.status == PregnancyStatus.delivered) {
      return SoftPill(
        icon: Icons.child_care_outlined,
        label: l10n.familyDeliveredBadge,
        foreground: AppColors.onTriageGreen,
        background: AppColors.triageGreenTint,
      );
    }

    final edd = parseIsoDate(pregnancy.edd);
    final week = edd == null
        ? null
        : gestationalAgeWeeks(edd, DateTime.now().toUtc());

    return SoftPill(
      icon: Icons.pregnant_woman_outlined,
      label: week == null
          ? l10n.familyPregnantBadge(0)
          : l10n.familyPregnantBadge(week),
    );
  }
}
