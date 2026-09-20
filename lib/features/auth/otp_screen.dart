import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/app_widgets.dart';
import 'auth_controller.dart';

/// S03 — OTP entry.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _length = 6;
  static const int _resendSeconds = 60;

  final _controller = TextEditingController();
  Timer? _timer;
  int _remaining = _resendSeconds;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _remaining = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _remaining--);
      if (_remaining <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final l10n = L.of(context);
    if (_controller.text.length != _length) {
      setState(() => _error = l10n.authOtpInvalid);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final hasPin = await ref.read(authProvider.notifier).verifyOtp(
            _controller.text,
          );
      // Spec S03: an account with a PIN goes to unlock, a new one to Set PIN.
      if (mounted) context.go(hasPin ? '/auth/pin' : '/auth/set-pin');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = l10n.authOtpInvalid);
        showErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final phone = ref.read(authProvider).pendingPhone;
    if (phone == null) return;

    try {
      await ref.read(authProvider.notifier).requestOtp(phone);
      _startCountdown();
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);
    final phone = ref.watch(authProvider).pendingPhone ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.authOtpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            Text(
              l10n.authOtpSentTo(phone),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
            ),
            const SizedBox(height: 32),
            // Six wide-tracked digits on the app's card surface. A real
            // six-box field would need six controllers and six focus nodes and
            // would change how the code is entered; the tracking gives the
            // same read at a glance with the same single-field behaviour.
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 30,
                letterSpacing: 14,
                fontWeight: FontWeight.w700,
                // The scheme ink, not the light-mode token: on a dark phone
                // AppColors.textPrimary is near-black on a near-black field.
                color: Theme.of(context).colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_length),
              ],
              decoration: InputDecoration(
                errorText: _error,
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                // The tracking puts a phantom gap after the last digit; the
                // nudge re-centres the run of six.
                hintText: '      ',
              ),
              onChanged: (value) {
                if (value.length == _length) _verify();
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _verify,
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
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: _remaining > 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        l10n.authOtpResendIn(_remaining),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondaryOf(context),
                            ),
                      ),
                    )
                  : TextButton(
                      onPressed: _resend,
                      child: Text(l10n.authOtpResend),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
