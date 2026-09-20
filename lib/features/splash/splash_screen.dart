import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';
import '../auth/auth_controller.dart';
import '../reminders/medicine_notifications.dart';

/// S01 — Splash / Bootstrap.
///
/// Opens the local database, seeds the picklists from the shipped assets, warms
/// the rule table, and then decides where to go: no session → S02, session but
/// locked → S04, unlocked → S06/S19 by role.
///
/// Every network call here is fire-and-forget. A phone with no signal must get
/// all the way to a usable family list, so nothing on this screen is allowed to
/// block on the server.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final reference = ref.read(referenceRepoProvider);
    final router = GoRouter.of(context);

    // Tier 2. Awaited because `getNotificationAppLaunchDetails` is how we find
    // out whether a tapped reminder is what started the app, and the answer is
    // wanted before the first `go`.
    await ref.read(medicineNotificationsProvider).init(
          onSelectPatient: (patientId) =>
              router.push('/patient/$patientId/timeline'),
        );

    // Local seeding first, and awaited: S21's picklists and the referral picker
    // are useless without it, and it is only a JSON asset.
    await reference.seedFromAssetsIfEmpty();
    await reference.seedFacilitiesFromAssetsIfEmpty();

    await ref.read(authProvider.notifier).restore();
    // Spec S01: renew a token that is nearly out, before anything needs it.
    unawaited(ref.read(authProvider.notifier).refreshTokenIfExpiringSoon());

    // Warm the rule table, then let the mock have it if we are in mock mode.
    unawaited(_refreshInBackground());

    if (!mounted) return;
    final auth = ref.read(authProvider);

    if (!auth.hasSession) {
      context.go('/auth/phone');
    } else if (!auth.unlocked) {
      context.go('/auth/pin');
    } else {
      context.go(auth.isHealthWorker ? '/provider' : '/family');

      // A reminder that launched the app should land on the record it is
      // about — after the unlock, never instead of it.
      final pending = MedicineNotifications.pendingPatientId;
      if (pending != null) {
        MedicineNotifications.pendingPatientId = null;
        router.push('/patient/$pending/timeline');
      }
    }
  }

  /// Spec S01: "all fire-and-forget; failures are ignored and cached copies are
  /// used".
  Future<void> _refreshInBackground() async {
    try {
      await ref.read(rulesProvider.future);
      ref.read(mockRulesBinderProvider);

      final flags = await ref.read(configFlagsProvider.future);
      await ref
          .read(referenceRepoProvider)
          .refreshCodelistsIfStale(flags.codelistVersion);
    } on Object {
      // Offline. The shipped copies are already in the database.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The lock-up already carries the name, so the separate
                // title that used to sit under the glyph would say it twice.
                BrandLogo.full(
                  width: MediaQuery.sizeOf(context).width * 0.60,
                  semanticLabel: l10n.appTitle,
                ),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.splashLoading,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                ),
              ],
            ),
          ),
          // Spec S01: the gear reaches Settings even before a session exists,
          // which is how a demo phone is pointed at a new tunnel URL.
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settingsTitle,
              onPressed: () => context.push('/settings'),
            ),
          ),
        ],
      ),
    );
  }
}

void unawaited(Future<void> future) {}
