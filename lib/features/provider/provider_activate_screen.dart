import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/enums.dart';
import '../../shared/widgets/soft_card.dart';
import '../auth/auth_controller.dart';
import '../shared/widgets/app_widgets.dart';

/// S18 — Provider activation: turn this phone into a health-worker phone.
class ProviderActivateScreen extends ConsumerStatefulWidget {
  const ProviderActivateScreen({super.key});

  @override
  ConsumerState<ProviderActivateScreen> createState() =>
      _ProviderActivateScreenState();
}

class _ProviderActivateScreenState
    extends ConsumerState<ProviderActivateScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  /// The field-level message for a rejected invite code.
  ///
  /// Without it the only feedback was the generic "please check the
  /// highlighted fields" snackbar — on a screen with one field and nothing
  /// highlighted, which told the health worker neither what was wrong nor
  /// where to look.
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _codeError = null;
    });

    try {
      final user =
          await ref.read(authProvider.notifier).activateProvider(_code.text);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L.of(context).providerActivated(user.facilityName ?? ''),
          ),
        ),
      );
      // The router's role redirect takes it from here.
      context.go('/provider');
    } on Object catch (error) {
      if (!mounted) return;
      final rejected =
          error is AppError && error.fieldErrors.containsKey('inviteCode');
      setState(() {
        _busy = false;
        _codeError =
            rejected ? L.of(context).providerInviteCodeUnknown : null;
      });
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final user = ref.watch(authProvider).user;
    final activated = user?.role == UserRole.patient ? null : user?.facilityName;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.providerActivateTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xl,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          // One field and one button. Activation happens once in the life of a
          // phone, so the screen's job is to be unambiguous, not efficient.
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brandTintOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.badge_outlined,
                size: 32,
                color: AppColors.brandOf(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.providerInviteCode,
              hintText: 'HA-GHORAHI-01',
              errorText: _codeError,
            ),
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onSubmitted: (_) => _activate(),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _activate,
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      // The button's ground is the light brand blue on a dark
                      // phone, where a white spinner all but disappears.
                      color: AppColors.onBrandOf(context),
                    ),
                  )
                : Text(l10n.providerActivate),
          ),
          // The success state, in brand green, so that a provider who came back
          // to this screen can see at a glance which health post this phone is
          // already attached to.
          if (activated != null) ...[
            const SizedBox(height: AppSpacing.xl),
            SoftCard(
              color: AppColors.brandGreenTint,
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_outlined,
                    size: 22,
                    color: AppColors.brandGreen,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l10n.providerActivated(activated),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.onTriageGreen,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
