import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_error.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/l10n/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/brand_logo.dart';
import '../shared/widgets/app_widgets.dart';
import 'auth_controller.dart';

/// S02 — Phone entry.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = L.of(context);
    if (!AuthController.isValidPhone(_controller.text)) {
      setState(() => _error = l10n.authPhoneInvalid);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authProvider.notifier).requestOtp(_controller.text);
      if (mounted) context.go('/auth/otp');
    } on AppError catch (error) {
      if (!mounted) return;
      // Spec S02: a rate limit says when to come back, not just that it failed.
      if (error.code == AppError.rateLimited) {
        setState(() => _error = l10n.authRateLimited(_retryMinutes(error)));
      } else {
        showErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The server reports the wait in `details.retryAfterSec` when it can; ten
  /// minutes is the window spec A.4 rate-limits OTP requests over.
  int _retryMinutes(AppError error) {
    final seconds = error.details?['retryAfterSec'];
    if (seconds is num) return (seconds / 60).ceil().clamp(1, 60);
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final flags = ref.watch(configFlagsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: TextButton(
              onPressed: () =>
                  ref.read(localeControllerProvider.notifier).toggle(),
              child: Text(
                Localizations.localeOf(context).languageCode == 'ne'
                    ? 'EN'
                    : 'नेपाली',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xl,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            // One purpose, one field, one button. The auth screens are the
            // first thing a new user sees and the only place the app can
            // afford to be almost empty.
            Center(
              child: BrandLogo.full(
                width: MediaQuery.sizeOf(context).width * 0.40,
                semanticLabel: l10n.appTitle,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              l10n.authPhoneTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.authPhoneSubtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.phone,
              // Latin digits: a phone number is not a display string.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(15),
              ],
              decoration: InputDecoration(
                labelText: l10n.authPhoneLabel,
                hintText: l10n.authPhoneHint,
                prefixText: '+977 ',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onBrandOf(context),
                      ),
                    )
                  : Text(l10n.commonContinue),
            ),
            if (flags?.otpDemo ?? false) ...[
              const SizedBox(height: AppSpacing.xl),
              DemoNotice(message: l10n.authDemoOtpBanner('123456')),
            ],
          ],
        ),
      ),
    );
  }
}

// The tinted glyph disc that used to head each auth screen is gone: the brand
// lock-up now does that job, and two badges stacked on one short screen read
// as clutter.

/// The demo-OTP notice on S02 and the "demo data" note elsewhere.
///
/// Green rather than blue or amber: it is telling the user something helpful is
/// switched on, not warning them. Amber would read as a fault, and this screen
/// is the demo's happy path.
class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: AppColors.brandGreenTint,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline,
            size: 20,
            color: AppColors.onTriageGreen,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onTriageGreen,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
