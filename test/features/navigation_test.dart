import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mero_swasthya/core/config/app_config.dart';
import 'package:mero_swasthya/core/l10n/gen/app_localizations.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/documents/documents_screen.dart';
import 'package:mero_swasthya/features/provider/provider_home_screen.dart';
import 'package:mero_swasthya/features/shell/coach_marks.dart';
import 'package:mero_swasthya/features/shell/patient_home_tab.dart';
import 'package:mero_swasthya/features/shell/patient_more_tab.dart';
import 'package:mero_swasthya/features/shell/patient_shell.dart';
import 'package:mero_swasthya/features/shell/provider_home_tab.dart';
import 'package:mero_swasthya/features/shell/provider_more_tab.dart';
import 'package:mero_swasthya/features/shell/provider_reminders_tab.dart';
import 'package:mero_swasthya/features/shell/provider_shell.dart';
import 'package:mero_swasthya/features/shell/shell_scaffold.dart';
import 'package:mero_swasthya/features/timeline/timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// The UX pass's navigation contract.
///
/// Three things are pinned here, because all three are the sort of thing that
/// works when it is written and quietly stops working two refactors later:
///
///  1. **Tab switching.** Four labelled patient tabs, each one showing its own
///     screen, all reachable from each other.
///  2. **Back never traps.** Android back from any tab returns to Home; from
///     Home it leaves the shell alone to be popped (which exits the app).
///  3. **Coach marks are shown once.** First run shows them, a second run with
///     the same preferences does not, and dismissing writes the flag.
void main() {
  const ownerId = '';
  const sitaId = 'p_nav_sita';
  const ramId = 'p_nav_ram';

  late AppDatabase db;

  setUpAll(() {
    // Every test opens its own in-memory database and never closes it — the
    // repo's convention, because closing a Drift db inside `testWidgets` waits
    // on a timer the fake clock never advances.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.patientsDao.upsert(
      const Patient(
        id: sitaId,
        ownerUserId: ownerId,
        name: 'Sita Kumari Chaudhary',
        sex: Sex.female,
        dob: '1996-04-11',
        bloodGroup: 'B+',
      ),
    );
    await db.patientsDao.upsert(
      const Patient(
        id: ramId,
        ownerUserId: ownerId,
        name: 'Ram Bahadur Chaudhary',
        sex: Sex.male,
        dob: '1988-01-20',
      ),
    );
  });

  /// Pumps [screen] with the shell's dependencies in place.
  ///
  /// [prefs] seeds shared preferences, which is how the coach-mark flag is
  /// controlled — the tour's "seen" state is a device preference, so a test that
  /// wants a first run starts from an empty map.
  Future<AppConfig> pump(
    WidgetTester tester,
    Widget screen, {
    Map<String, Object> prefs = const {},
    Locale locale = const Locale('en'),
  }) async {
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
    final config = await AppConfig.load();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          databaseProvider.overrideWithValue(db),
          connectivityProvider.overrideWithValue(const AlwaysOnline()),
          apiTransportProvider.overrideWithValue(MockApi()),
        ],
        child: appShellForTest(screen, locale: locale),
      ),
    );
    await settle(tester);
    return config;
  }

  /// The Android system back button, as the framework sees it.
  ///
  /// `maybePop` is what the back gesture ends up calling, and it is the call
  /// that consults `PopScope` — which is the whole point of the assertion.
  Future<void> systemBack(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await settle(tester);
  }

  /// Drain anything the mock API or the coach-mark preference write scheduled,
  /// so it is not reported as a leaked timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await unmount(tester);
  }

  group('patient shell', () {
    testWidgets('shows four labelled tabs, never icon-only', (tester) async {
      await pump(tester, const PatientShell(),
          prefs: {'coach_seen:patient': true});

      final l10n = await L.delegate.load(const Locale('en'));
      for (final label in [
        l10n.navHome,
        l10n.navRecords,
        l10n.navDocuments,
        l10n.navMore,
      ]) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: 'the $label tab must carry its name, not just a glyph',
        );
      }

      await finish(tester);
    });

    testWidgets('each tab shows its own screen', (tester) async {
      await pump(tester, const PatientShell(),
          prefs: {'coach_seen:patient': true});
      final l10n = await L.delegate.load(const Locale('en'));

      expect(find.byType(PatientHomeTab), findsOneWidget);

      Future<void> tapTab(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await settle(tester);
      }

      await tapTab(l10n.navRecords);
      expect(find.byType(TimelineScreen), findsOneWidget);
      expect(find.byType(PatientHomeTab), findsNothing);

      await tapTab(l10n.navDocuments);
      expect(find.byType(DocumentsScreen), findsOneWidget);

      await tapTab(l10n.navMore);
      expect(find.byType(PatientMoreTab), findsOneWidget);

      // And back to where it started, without a route push in between.
      await tapTab(l10n.navHome);
      expect(find.byType(PatientHomeTab), findsOneWidget);

      await finish(tester);
    });

    testWidgets(
      'the More tab names the features the audit found buried',
      (tester) async {
        await pump(tester, const PatientShell(),
            prefs: {'coach_seen:patient': true});
        final l10n = await L.delegate.load(const Locale('en'));

        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(l10n.navMore),
          ),
        );
        await settle(tester);

        // Each of these was two or three taps deep behind an unlabeled glyph.
        // The list is longer than the test viewport, so the tail is scrolled
        // into view rather than asserted blind — a `SliverChildListDelegate`
        // only mounts what is laid out.
        for (final label in [
          l10n.patientHomeReminders,
          l10n.patientHomeWhoViewed,
          l10n.printedCardAction,
          l10n.moreEditDetails,
          l10n.exportPdf,
          l10n.familyIAmHealthWorker,
          l10n.syncTitle,
          l10n.settingsTitle,
        ]) {
          await tester.scrollUntilVisible(
            find.text(label),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await settle(tester);
          expect(find.text(label), findsOneWidget, reason: '$label is missing');
        }

        await finish(tester);
      },
    );

    testWidgets('back from a tab returns to Home rather than exiting',
        (tester) async {
      await pump(tester, const PatientShell(),
          prefs: {'coach_seen:patient': true});
      final l10n = await L.delegate.load(const Locale('en'));

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(l10n.navDocuments),
        ),
      );
      await settle(tester);
      expect(find.byType(DocumentsScreen), findsOneWidget);

      await systemBack(tester);
      expect(
        find.byType(PatientHomeTab),
        findsOneWidget,
        reason: 'back from a tab goes to Home',
      );
      expect(find.byType(DocumentsScreen), findsNothing);

      // And back again from Home does not trap: the shell is still there, ready
      // to be popped by the platform, rather than swallowing the gesture and
      // leaving the user on a screen they cannot leave.
      await systemBack(tester);
      expect(find.byType(PatientHomeTab), findsOneWidget);

      await finish(tester);
    });
  });

  group('coach marks', () {
    testWidgets('shown on a first run, and not on the next one',
        (tester) async {
      final config = await pump(tester, const PatientShell());
      final l10n = await L.delegate.load(const Locale('en'));

      expect(find.text(l10n.coachFamilyTitle), findsOneWidget);
      expect(config.coachSeen(CoachTour.patient), isFalse);

      // Three cards, then the flag.
      await tester.tap(find.text(l10n.coachNext));
      await settle(tester);
      expect(find.text(l10n.coachShareTitle), findsOneWidget);

      await tester.tap(find.text(l10n.coachNext));
      await settle(tester);
      expect(find.text(l10n.coachMoreTitle), findsOneWidget);
      expect(find.text(l10n.coachDone), findsOneWidget);

      await tester.tap(find.text(l10n.coachDone));
      await settle(tester);
      expect(find.text(l10n.coachMoreTitle), findsNothing);
      expect(config.coachSeen(CoachTour.patient), isTrue);

      await finish(tester);

      // A second launch with the flag already written shows nothing.
      await pump(tester, const PatientShell(),
          prefs: {'coach_seen:patient': true});
      expect(find.text(l10n.coachFamilyTitle), findsNothing);

      await finish(tester);
    });

    testWidgets('Skip dismisses the whole tour and writes the flag',
        (tester) async {
      final config = await pump(tester, const PatientShell());
      final l10n = await L.delegate.load(const Locale('en'));

      expect(find.text(l10n.coachFamilyTitle), findsOneWidget);

      await tester.tap(find.text(l10n.coachSkip));
      await settle(tester);

      expect(find.text(l10n.coachFamilyTitle), findsNothing);
      expect(find.text(l10n.coachShareTitle), findsNothing);
      expect(config.coachSeen(CoachTour.patient), isTrue);

      await finish(tester);
    });

    testWidgets('the patient tour is three cards and no more', (tester) async {
      await pump(tester, const PatientShell());
      // Spec for this pass: at most three. A longer tour is a manual.
      final marks = tester
          .widget<CoachMarks>(find.byType(CoachMarks))
          .marks;
      expect(marks.length, lessThanOrEqualTo(3));

      await finish(tester);
    });
  });

  group('provider shell', () {
    // The provider shell is a `StatefulShellRoute`, so it is pumped inside a
    // router of its own with the pushed screens — the camera above all —
    // replaced by stubs that name themselves. See `providerRouterForTest`.
    Future<(GoRouter, AppConfig)> pumpProvider(
      WidgetTester tester, {
      Map<String, Object> prefs = const {'coach_seen:provider': true},
    }) async {
      SharedPreferences.setMockInitialValues(Map<String, Object>.from(prefs));
      final config = await AppConfig.load();
      final router = providerRouterForTest();
      addTearDown(router.dispose);

      // A phone, not the 800×600 default: the Patients tab's empty state is
      // sized as a share of the screen height and is four pixels too tall
      // for a window that short.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(config),
            databaseProvider.overrideWithValue(db),
            connectivityProvider.overrideWithValue(const AlwaysOnline()),
            apiTransportProvider.overrideWithValue(MockApi()),
          ],
          child: routerAppForTest(router),
        ),
      );
      await settle(tester);
      return (router, config);
    }

    Finder barLabel(String label) => find.descendant(
          of: find.byType(BottomAppBar),
          matching: find.text(label),
        );

    /// The Android back button as the router sees it, and long enough for
    /// the popped route to finish leaving.
    Future<void> routerBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }

    testWidgets('Home · Patients · [Scan] · Reminders · More, all labelled',
        (tester) async {
      final (router, _) = await pumpProvider(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      expect(router.state.uri.path, ProviderTabs.home);
      expect(find.byType(ProviderHomeTab), findsOneWidget);

      for (final label in [
        l10n.navHome,
        l10n.navPatients,
        l10n.navScan,
        l10n.navReminders,
        l10n.navMore,
      ]) {
        expect(barLabel(label), findsOneWidget,
            reason: 'the $label destination must carry its name');
      }

      // The centre button: raised, round, docked, and named.
      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.shape, isA<CircleBorder>());
      expect(fab.tooltip, l10n.providerScanQr);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).first)
            .floatingActionButtonLocation,
        FloatingActionButtonLocation.centerDocked,
      );

      await finish(tester);
    });

    testWidgets('each tab shows its own screen, and Scan works from all of them',
        (tester) async {
      final (router, _) = await pumpProvider(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      Future<void> scanFromHere() async {
        await tester.tap(find.byType(FloatingActionButton));
        await settle(tester);
        expect(find.text('stub:scan'), findsOneWidget);
        expect(router.state.uri.path, ProviderTabs.scan);
        await routerBack(tester);
        expect(find.text('stub:scan'), findsNothing);
      }

      await scanFromHere();
      expect(find.byType(ProviderHomeTab), findsOneWidget);

      await tester.tap(barLabel(l10n.navPatients));
      await settle(tester);
      expect(find.byType(ProviderHomeScreen), findsOneWidget);
      expect(router.state.uri.path, ProviderTabs.patients);
      await scanFromHere();
      expect(find.byType(ProviderHomeScreen), findsOneWidget);

      await tester.tap(barLabel(l10n.navReminders));
      await settle(tester);
      expect(find.byType(ProviderRemindersTab), findsOneWidget);
      await scanFromHere();

      await tester.tap(barLabel(l10n.navMore));
      await settle(tester);
      expect(find.byType(ProviderMoreTab), findsOneWidget);
      for (final label in [
        l10n.dashboardAction,
        l10n.providerMyFamily,
        l10n.settingsTitle,
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is missing');
      }
      await scanFromHere();

      await tester.tap(barLabel(l10n.navHome));
      await settle(tester);
      expect(find.byType(ProviderHomeTab), findsOneWidget);

      await finish(tester);
    });

    testWidgets('back from any tab goes to Home; back from Home leaves the app',
        (tester) async {
      final (router, _) = await pumpProvider(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      await tester.tap(barLabel(l10n.navMore));
      await settle(tester);
      expect(router.state.uri.path, ProviderTabs.more);

      await routerBack(tester);
      expect(router.state.uri.path, ProviderTabs.home);
      expect(find.byType(ProviderHomeTab), findsOneWidget);

      // On Home the shell lets the pop through to the platform, which is
      // what exits the app: the router reports nothing left to pop.
      expect(await tester.binding.handlePopRoute(), isFalse);
      await settle(tester);
      expect(find.byType(ProviderHomeTab), findsOneWidget);

      await finish(tester);
    });

    testWidgets('the tour points at Scan, then at Needs attention, once',
        (tester) async {
      final (_, config) = await pumpProvider(tester, prefs: const {});
      final l10n = await L.delegate.load(const Locale('en'));

      expect(config.coachSeen(CoachTour.provider), isFalse);
      expect(find.text(l10n.coachScanButtonTitle), findsOneWidget);

      final marks =
          tester.widget<CoachMarks>(find.byType(CoachMarks)).marks;
      expect(marks.length, lessThanOrEqualTo(3));
      expect(marks[0].target, ProviderCoachTargets.scanButton);
      expect(marks[1].target, ProviderCoachTargets.needsAttention);

      await tester.tap(find.text(l10n.coachNext));
      await settle(tester);
      expect(find.text(l10n.coachAttentionTitle), findsOneWidget);
      expect(find.text(l10n.coachDone), findsOneWidget);

      await tester.tap(find.text(l10n.coachDone));
      await settle(tester);
      expect(find.text(l10n.coachAttentionTitle), findsNothing);
      expect(config.coachSeen(CoachTour.provider), isTrue);

      await finish(tester);

      await pumpProvider(tester);
      expect(find.text(l10n.coachScanButtonTitle), findsNothing);

      await finish(tester);
    });
  });

  group('shell mechanics', () {
    // The shell is tested on its own as well as through PatientShell: the
    // contract — one tab built at a time, the index visible to the tab — is
    // the shell's, not the patient screens'.
    testWidgets('only the current tab is built', (tester) async {
      var builtA = 0;
      var builtB = 0;

      await pump(
        tester,
        ShellScaffold(
          tabs: [
            ShellTab(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Alpha',
              builder: (_) {
                builtA++;
                return const Scaffold(body: Text('A body'));
              },
            ),
            ShellTab(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Beta',
              builder: (_) {
                builtB++;
                return const Scaffold(body: Text('B body'));
              },
            ),
          ],
        ),
      );

      expect(builtA, greaterThan(0));
      expect(
        builtB,
        0,
        reason: 'a tab that is not on screen must not be built',
      );
      expect(find.text('B body'), findsNothing);

      await tester.tap(find.text('Beta'));
      await settle(tester);
      expect(find.text('B body'), findsOneWidget);
      expect(find.text('A body'), findsNothing);

      await finish(tester);
    });

    testWidgets('ShellScope reports the current tab to its children',
        (tester) async {
      await pump(
        tester,
        ShellScaffold(
          tabs: [
            ShellTab(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Alpha',
              builder: (context) => Scaffold(
                body: Text('index ${ShellScope.maybeOf(context)?.index}'),
              ),
            ),
            ShellTab(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Beta',
              builder: (context) => Scaffold(
                body: Text('index ${ShellScope.maybeOf(context)?.index}'),
              ),
            ),
          ],
        ),
      );

      expect(find.text('index 0'), findsOneWidget);

      await tester.tap(find.text('Beta'));
      await settle(tester);
      expect(find.text('index 1'), findsOneWidget);

      await finish(tester);
    });
  });
}
