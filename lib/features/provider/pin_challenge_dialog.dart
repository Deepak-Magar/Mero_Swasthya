import 'package:flutter/material.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../auth/pin_keypad.dart';

/// Spec A.7: a long-lived printed card is only half a credential.
///
/// The other half is the patient standing there to say four digits, so this is
/// deliberately the provider asking *them* rather than typing something they
/// know — the title says whose PIN it is, and the keypad is the same one S04
/// uses so nothing about it invites a paste from elsewhere.
///
/// Returns the digits, or null if the provider backed out.
///
/// A bottom sheet rather than a dialog: it rises from the bottom of a
/// full-bleed camera screen without boxing the preview inside a small white
/// rectangle, and the keypad sits where a thumb already is.
Future<String?> showPinChallenge(BuildContext context, {bool retry = false}) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => PinChallengeDialog(retry: retry),
  );
}

class PinChallengeDialog extends StatefulWidget {
  const PinChallengeDialog({super.key, this.retry = false});

  /// True when a previous attempt was refused, which swaps the hint for the
  /// error so the provider is not left guessing whether it even registered.
  final bool retry;

  @override
  State<PinChallengeDialog> createState() => _PinChallengeDialogState();
}

class _PinChallengeDialogState extends State<PinChallengeDialog> {
  String _pin = '';

  void _digit(String digit) {
    if (_pin.length >= PinKeypad.pinLength) return;
    setState(() => _pin += digit);
    if (_pin.length == PinKeypad.pinLength) {
      // Four digits is the whole input; making them press a button as well is
      // one more thing to explain across a table.
      Navigator.of(context).pop(_pin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.providerPinChallengeTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                widget.retry
                    ? l10n.providerPinChallengeWrong
                    : l10n.providerPinChallengeBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.retry
                      ? AppColors.dangerInkOf(context)
                      : AppColors.textSecondaryOf(context),
                  fontWeight: widget.retry ? FontWeight.w600 : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PinDots(length: _pin.length, error: widget.retry),
              const SizedBox(height: AppSpacing.lg),
              PinKeypad(
                onDigit: _digit,
                onBackspace: () => setState(
                  () => _pin = _pin.isEmpty
                      ? _pin
                      : _pin.substring(0, _pin.length - 1),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
