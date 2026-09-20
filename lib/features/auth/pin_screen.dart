import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';
import 'auth_controller.dart';
import 'pin_keypad.dart';

/// S04 — PIN unlock.
///
/// The PIN is verified against the locally stored PBKDF2 verifier, so a health
/// worker with no signal still gets into the record. That is the whole point of
/// the screen: it is the daily login, and the network is optional.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final unlocked = await ref.read(authProvider.notifier).unlock(_pin);

    if (!mounted) return;
    if (!unlocked) {
      setState(() {
        _busy = false;
        _pin = '';
        _error = L.of(context).authPinWrong;
      });
      return;
    }

    // Spec §7: the engine starts after the PIN unlock, never before.
    unawaited(ref.read(syncEngineProvider).start());

    final auth = ref.read(authProvider);
    context.go(auth.isHealthWorker ? '/provider' : '/family');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final name = ref.watch(authProvider).user?.name;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            BrandLogo.full(
              width: MediaQuery.sizeOf(context).width * 0.40,
              semanticLabel: l10n.appTitle,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              l10n.authPinUnlockTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.tight),
            // The name sits tight under the title: they are one cluster —
            // "whose phone this is" — not two separate statements.
            Text(
              name ?? l10n.authPinUnlockSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            ),
            const SizedBox(height: 32),
            PinDots(length: _pin.length, error: _error != null),
            if (_error != null) ...[
              SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.dangerInkOf(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const Spacer(),
            PinKeypad(
              enabled: !_busy,
              onDigit: (digit) {
                if (_pin.length >= PinKeypad.pinLength) return;
                setState(() {
                  _pin += digit;
                  _error = null;
                });
                if (_pin.length == PinKeypad.pinLength) _submit();
              },
              onBackspace: () {
                if (_pin.isEmpty) return;
                setState(() => _pin = _pin.substring(0, _pin.length - 1));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.go('/auth/phone'),
              child: Text(l10n.authPinForgot),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

void unawaited(Future<void> future) {}
