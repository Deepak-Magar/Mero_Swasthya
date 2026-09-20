import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/app_widgets.dart';
import 'auth_controller.dart';
import 'pin_keypad.dart';

/// S05 — Set PIN and name. First-time account creation.
class SetPinScreen extends ConsumerStatefulWidget {
  const SetPinScreen({super.key});

  @override
  ConsumerState<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends ConsumerState<SetPinScreen> {
  final _nameController = TextEditingController();
  String _pin = '';
  String _confirm = '';
  bool _confirming = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    setState(() {
      _error = null;
      if (_confirming) {
        if (_confirm.length < PinKeypad.pinLength) _confirm += digit;
      } else {
        if (_pin.length < PinKeypad.pinLength) _pin += digit;
      }
    });

    if (!_confirming && _pin.length == PinKeypad.pinLength) {
      setState(() => _confirming = true);
    } else if (_confirming && _confirm.length == PinKeypad.pinLength) {
      _submit();
    }
  }

  void _onBackspace() {
    setState(() {
      if (_confirming) {
        if (_confirm.isEmpty) {
          _confirming = false;
          _pin = _pin.substring(0, _pin.length - 1);
        } else {
          _confirm = _confirm.substring(0, _confirm.length - 1);
        }
      } else if (_pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  Future<void> _submit() async {
    final l10n = L.of(context);

    if (_nameController.text.trim().length < 2) {
      setState(() {
        _error = l10n.authNameTooShort;
        _confirming = false;
        _confirm = '';
      });
      return;
    }
    if (_pin != _confirm) {
      setState(() {
        _error = l10n.authPinMismatch;
        _confirming = false;
        _pin = '';
        _confirm = '';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).setPin(
            pin: _pin,
            name: _nameController.text.trim(),
          );
      if (!mounted) return;

      // Spec §7: the sync engine starts once the database is unlocked.
      unawaited(ref.read(syncEngineProvider).start());
      context.go('/family');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirming = false;
        _pin = '';
        _confirm = '';
      });
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final entered = _confirming ? _confirm : _pin;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.authSetPinTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.lg,
                AppSpacing.gutter,
                AppSpacing.xl,
              ),
              child: TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l10n.authNameLabel),
              ),
            ),
            Text(
              _confirming ? l10n.authPinConfirmLabel : l10n.authPinLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.tight),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Text(
                l10n.authSetPinSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PinDots(length: entered.length, error: _error != null),
            if (_error != null) ...[
              SizedBox(height: AppSpacing.md),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.dangerInkOf(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
            const Spacer(),
            PinKeypad(
              enabled: !_busy,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

void unawaited(Future<void> future) {}
