import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The four-digit keypad S04 and S05 share.
///
/// A custom keypad rather than a text field with a numeric keyboard: the keys
/// are large enough to hit in a hurry with cold hands, and it cannot be
/// switched to a keyboard that offers autofill or a clipboard paste of somebody
/// else's PIN.
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  static const int pinLength = 4;

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Filled keys rather than outlined ones: twelve outlined boxes is twelve
    // borders, which is exactly the look the restyle takes out everywhere
    // else. A pale ground reads as a key just as clearly and much more calmly.
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          height: 64,
          child: FilledButton(
            onPressed: enabled ? onTap : null,
            style: FilledButton.styleFrom(
              backgroundColor: icon != null
                  ? Colors.transparent
                  : AppColors.brandTintOf(context),
              foregroundColor: AppColors.brandOf(context),
              disabledBackgroundColor: AppColors.skeleton,
              elevation: 0,
              minimumSize: const Size.square(AppTheme.minTapTarget),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
            ),
            child: icon != null
                ? Icon(icon, color: AppColors.textSecondaryOf(context))
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandOf(context),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              children: [
                for (final digit in row)
                  Expanded(
                    child: key(digit, onTap: () => onDigit(digit)),
                  ),
              ],
            ),
          Row(
            children: [
              const Expanded(child: SizedBox()),
              Expanded(child: key('0', onTap: () => onDigit('0'))),
              Expanded(
                child: key(
                  '',
                  icon: Icons.backspace_outlined,
                  onTap: onBackspace,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The filled/empty dots above the keypad.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, this.error = false});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filled = error ? scheme.error : AppColors.brandOf(context);

    // The empty ring is drawn from the *theme's* secondary ink, not from a
    // fixed 12–18 % grey. On the phone in dark mode the fixed value came out as
    // four almost-invisible smudges on the navy background — the screen gave no
    // feedback that a digit had landed. At 45 % of `onSurfaceVariant` the ring
    // reads in both themes without competing with a filled dot.
    final empty = error
        ? scheme.error.withValues(alpha: 0.4)
        : scheme.onSurfaceVariant.withValues(alpha: 0.45);
    final emptyFill = scheme.onSurfaceVariant.withValues(alpha: 0.12);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < PinKeypad.pinLength; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // An unfilled dot is a hollow ring, not a transparent hole with
              // a hard grey edge — it has to be visible without competing with
              // the digits that have already landed.
              color: i < length ? filled : emptyFill,
              border: Border.all(color: i < length ? filled : empty, width: 2),
            ),
          ),
      ],
    );
  }
}
