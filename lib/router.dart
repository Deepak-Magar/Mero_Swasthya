import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'domain/rules/provider_dashboard.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/otp_screen.dart';
import 'features/auth/phone_screen.dart';
import 'features/auth/pin_screen.dart';
import 'features/auth/set_pin_screen.dart';
import 'features/audit/audit_screen.dart';
import 'features/child/child_health_screen.dart';
import 'features/documents/documents_screen.dart';
import 'features/facilities/facility_map_screen.dart';
import 'features/family/patient_form_screen.dart';
import 'features/maternal/anc_contact_screen.dart';
import 'features/maternal/delivery_screen.dart';
import 'features/maternal/pregnancy_dashboard_screen.dart';
import 'features/maternal/register_pregnancy_screen.dart';
import 'features/patient_home/patient_home_screen.dart';
import 'features/patient_home/printed_card_screen.dart';
import 'features/provider/provider_activate_screen.dart';
import 'features/provider/provider_dashboard_screen.dart';
import 'features/provider/provider_patient_screen.dart';
import 'features/provider/scan_screen.dart';
import 'features/provider/visit_form_screen.dart';
import 'features/reminders/reminders_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/patient_shell.dart';
import 'features/shell/provider_shell.dart';
import 'features/splash/splash_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/timeline/timeline_screen.dart';

/// Spec §10's redirect rules, as a plain function of "who is signed in" and
/// "where are they going". Kept out of the `GoRouter` literal so it can be
/// exercised without building the whole screen graph.
///
/// Returns the location to send them to, or `null` to let them through.
String? authRedirect(AuthState auth, String location) {
  // S01 does the bootstrap work; it decides where to go itself.
  if (location == '/') return null;

  final isAuthRoute = location.startsWith('/auth');

  if (!auth.hasSession) return isAuthRoute ? null : '/auth/phone';
  if (!auth.unlocked) return location == '/auth/pin' ? null : '/auth/pin';

  // Signed in and unlocked: the auth screens have nothing left to say.
  if (isAuthRoute) return auth.isHealthWorker ? '/provider' : '/family';

  // A patient has no provider screens; a health worker keeps both.
  // S18's activation screen is the exception: it is how a patient account
  // becomes a health worker, so gating it on already being one locked the door
  // from the inside — S06's "I am a health worker" bounced straight back.
  if (!auth.isHealthWorker &&
      location.startsWith('/provider') &&
      location != '/provider/activate') {
    return '/family';
  }

  return null;
}

/// Spec §10 — the route table for S01–S23, and the role redirect in one place.
final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate `redirect` whenever the session or the lock state changes,
  // rather than leaving a signed-out user looking at a record.
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) =>
        authRedirect(ref.read(authProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),

      // --- Auth: S02–S05 ---------------------------------------------------
      GoRoute(path: '/auth/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(path: '/auth/otp', builder: (_, _) => const OtpScreen()),
      GoRoute(path: '/auth/pin', builder: (_, _) => const PinScreen()),
      GoRoute(path: '/auth/set-pin', builder: (_, _) => const SetPinScreen()),

      // --- Family: S06, S07 ------------------------------------------------
      // S06 is now the patient shell's Home tab rather than a screen of its
      // own: the four patient tabs all hang off this one route, and the member
      // they act on comes from `selectedMemberProvider` rather than a path
      // segment. The path is unchanged so every `context.go('/family')` and the
      // auth redirect in `authRedirect` keep working.
      GoRoute(path: '/family', builder: (_, _) => const PatientShell()),
      GoRoute(
        path: '/family/new',
        builder: (_, _) => const PatientFormScreen(),
      ),
      GoRoute(
        path: '/family/:id/edit',
        builder: (_, state) =>
            PatientFormScreen(patientId: state.pathParameters['id']),
      ),

      // --- The record: S08–S10, S15, S16 -----------------------------------
      GoRoute(
        path: '/patient/:id',
        builder: (_, state) =>
            PatientHomeScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/card',
        builder: (_, state) =>
            PrintedCardScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/child',
        builder: (_, state) =>
            ChildHealthScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/timeline',
        builder: (_, state) =>
            TimelineScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/documents',
        builder: (_, state) =>
            DocumentsScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/reminders',
        builder: (_, state) =>
            RemindersScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/patient/:id/audit',
        builder: (_, state) =>
            AuditScreen(patientId: state.pathParameters['id']!),
      ),

      // --- Maternal: S11–S14 -----------------------------------------------
      GoRoute(
        path: '/patient/:id/pregnancy/new',
        builder: (_, state) =>
            RegisterPregnancyScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pregnancy/:id',
        builder: (_, state) =>
            PregnancyDashboardScreen(pregnancyId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/pregnancy/:id/contact/:no',
        builder: (_, state) => AncContactScreen(
          pregnancyId: state.pathParameters['id']!,
          contactNo: int.parse(state.pathParameters['no']!),
        ),
      ),
      GoRoute(
        path: '/pregnancy/:id/delivery',
        builder: (_, state) =>
            DeliveryScreen(pregnancyId: state.pathParameters['id']!),
      ),

      // --- Provider: S18–S22 -----------------------------------------------
      // Likewise S19: the three provider tabs hang off '/provider', and Scan
      // is the landing tab.
      GoRoute(path: '/provider', builder: (_, _) => const ProviderShell()),
      GoRoute(
        path: '/provider/activate',
        builder: (_, _) => const ProviderActivateScreen(),
      ),
      GoRoute(path: '/provider/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(
        path: '/provider/dashboard',
        builder: (_, _) => const ProviderDashboardScreen(),
      ),
      GoRoute(
        path: '/provider/dashboard/:bucket',
        builder: (_, state) => DashboardBucketScreen(
          bucket: DashboardBucket.values.firstWhere(
            (b) => b.name == state.pathParameters['bucket'],
            orElse: () => DashboardBucket.overdueContacts,
          ),
        ),
      ),
      GoRoute(
        path: '/provider/patient/:id',
        builder: (_, state) =>
            ProviderPatientScreen(patientId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/provider/patient/:id/visit/new',
        builder: (_, state) =>
            VisitFormScreen(patientId: state.pathParameters['id']!),
      ),

      // --- Tier 2: the nearest-facility map --------------------------------
      //
      // A query string rather than a path segment because the three callers
      // want the same screen with different framing: S13's referral and S12's
      // birth plan want birthing centres and a facility back, and the plain
      // link from a referral card just wants to show where it is.
      GoRoute(
        path: '/facilities',
        builder: (_, state) => FacilityMapScreen(
          patientId: state.uri.queryParameters['patient'],
          birthingOnly: state.uri.queryParameters['birthing'] == 'true',
          picking: state.uri.queryParameters['pick'] == 'true',
        ),
      ),

      // --- S17, S23 ---------------------------------------------------------
      GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('No route for ${state.uri}')),
    ),
  );
});

/// Bridges Riverpod to go_router: `/provider/activate` changing the role, or a
/// refused refresh token, both have to move the user without anyone navigating.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _removeAuth = ref.listen<AuthState>(
      authProvider,
      (_, _) => notifyListeners(),
    ).close;

    _removeSession = ref.listen<bool>(
      sessionExpiredProvider,
      (_, expired) {
        if (expired) notifyListeners();
      },
    ).close;
  }

  late final VoidCallback _removeAuth;
  late final VoidCallback _removeSession;

  @override
  void dispose() {
    _removeAuth();
    _removeSession();
    super.dispose();
  }
}
