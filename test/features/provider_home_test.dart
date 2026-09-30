import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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
import 'package:mero_swasthya/data/local/converters.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/rules.dart';
import 'package:mero_swasthya/features/auth/auth_controller.dart';
import 'package:mero_swasthya/shared/widgets/soft_card.dart';
import 'package:mero_swasthya/features/provider/provider_home_screen.dart';
import 'package:mero_swasthya/features/shell/provider_home_tab.dart';
import 'package:mero_swasthya/features/shell/provider_reminders_tab.dart';
import 'package:mero_swasthya/features/shell/provider_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// The provider Home dashboard.
///
/// Five things are pinned: the empty state shows zeroes and a calm card rather
/// than blanks; a seeded phone (Sita triaged red today, Ram seen today, Gita
/// overdue) produces the right counts and rows; each tile opens the list it
/// was counted from; the Nepali strings are the Nepali strings; and at the
/// largest font scale on a small phone nothing overflows.
void main() {
  const sitaId = 'p_home_sita';
  const ramId = 'p_home_ram';
  const gitaId = 'p_home_gita';
  const sitaPregnancy = 'preg_home_sita';
  const gitaPregnancy = 'preg_home_gita';

  /// A Tuesday morning: "Good morning", and a day with room on both sides.
  final now = DateTime(2026, 9, 29, 10, 30);
  String at(DateTime local) => local.toUtc().toIso8601String();
  String day(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  late AppDatabase db;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'coach_seen:provider': true});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  // No `db.close()` in a tearDown — see layout_test.dart.

  Future<void> seed() async {
    await db.patientsDao.upsert(
      const Patient(
        id: sitaId,
        ownerUserId: '',
        name: 'Sita Kumari Chaudhary',
        sex: Sex.female,
        dob: '1996-04-11',
      ),
    );
    await db.patientsDao.upsert(
      const Patient(
        id: ramId,
        ownerUserId: '',
        name: 'Ram Bahadur Chaudhary',
        sex: Sex.male,
        dob: '1988-01-20',
      ),
    );
    // Gita came through a grant that is still open.
    await db.patientsDao.upsert(
      const Patient(
        id: gitaId,
        ownerUserId: 'u_other',
        name: 'Gita Tharu',
        sex: Sex.female,
        dob: '1995-06-11',
      ),
      // Against the real clock, which is what the Patients tab's grant
      // window is checked with.
      accessUntil: Value(
        DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
      ),
    );

    await db.pregnanciesDao.upsertPregnancy(
      const Pregnancy(
        id: sitaPregnancy,
        patientId: sitaId,
        lmp: '2026-02-01',
        edd: '2026-11-08',
      ),
    );
    await db.pregnanciesDao.upsertContacts([
      AncContact(
        id: 'sita_4',
        pregnancyId: sitaPregnancy,
        contactNo: 4,
        weekTarget: 30,
        dueAt: day(now.subtract(const Duration(days: 4))),
        // Recorded this morning, red.
        doneAt: at(now.subtract(const Duration(hours: 1))),
        findings: const Findings(bpSys: 165, bpDia: 112),
        triageLevel: TriageLevel.red,
        triageReasons: const ['Severe hypertension (≥160/110)'],
      ),
      AncContact(
        id: 'sita_5',
        pregnancyId: sitaPregnancy,
        contactNo: 5,
        weekTarget: 34,
        dueAt: day(now.add(const Duration(days: 3))),
      ),
    ]);

    await db.pregnanciesDao.upsertPregnancy(
      const Pregnancy(
        id: gitaPregnancy,
        patientId: gitaId,
        lmp: '2026-05-01',
        edd: '2027-02-05',
      ),
    );
    await db.pregnanciesDao.upsertContacts([
      // Three weeks late, nothing recorded.
      AncContact(
        id: 'gita_2',
        pregnancyId: gitaPregnancy,
        contactNo: 2,
        weekTarget: 20,
        dueAt: day(now.subtract(const Duration(days: 21))),
      ),
      // And one due today.
      AncContact(
        id: 'gita_3',
        pregnancyId: gitaPregnancy,
        contactNo: 3,
        weekTarget: 26,
        dueAt: day(now),
      ),
    ]);

    await db.visitsDao.upsert(
      Visit(
        id: 'ram_visit_today',
        patientId: ramId,
        visitAt: at(now.subtract(const Duration(minutes: 30))),
        chiefComplaintCode: 'FEVER',
      ),
    );
    // Yesterday's visit must not count.
    await db.visitsDao.upsert(
      Visit(
        id: 'ram_visit_yesterday',
        patientId: ramId,
        visitAt: at(now.subtract(const Duration(days: 1))),
        chiefComplaintCode: 'FEVER',
      ),
    );

    // One change waiting to go out.
    await db.outboxDao.enqueue(
      table: SyncTables.visits,
      op: OutboxOp.upsert,
      rowId: 'ram_visit_today',
      baseVersion: 0,
      payload: const {},
    );
  }

  /// Pumps the shell on Home at [size] — by default tall enough for the whole
  /// page to be laid out, because the list is lazy and a section below the
  /// fold of the default 600 px test window is never built, let alone found.
  Future<GoRouter> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(412, 2200),
  }) async {
    final config = await AppConfig.load();
    final router = providerRouterForTest();
    addTearDown(router.dispose);

    tester.view.physicalSize = size;
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
          clockProvider.overrideWithValue(() => now),
          authProvider.overrideWith(_SignedInProvider.new),
          // The shipped table's version, without going through the asset
          // bundle; the reasons come from the translation table in code.
          rulesProvider.overrideWith(
            (ref) async => Rules.fromJson(const {
              'version': '2026-09-18.1',
              'ancSchedule': [],
              'dangerSigns': [],
              'riskFactors': [],
            }),
          ),
        ],
        child: routerAppForTest(router, locale: locale),
      ),
    );
    await settle(tester);
    return router;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await unmount(tester);
  }

  /// Android back, and long enough for the route to finish leaving.
  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  group('empty state', () {
    testWidgets('shows zeroes, a calm card and the quiet lines', (tester) async {
      await pump(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      // Four tiles, four zeroes — never a blank.
      expect(find.text('0'), findsNWidgets(4));
      for (final label in [
        l10n.homeStatSeen,
        l10n.homeStatVisits,
        l10n.homeStatAncDue,
        l10n.homeStatPending,
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label tile');
      }

      expect(find.text(l10n.homeAttentionEmptyTitle), findsOneWidget);
      expect(find.text(l10n.homeAttentionEmptyBody), findsOneWidget);
      expect(find.text(l10n.homeDueWeekEmpty), findsOneWidget);
      expect(find.text(l10n.homeRecentEmpty), findsOneWidget);

      // The greeting is by time of day and first name; the facility under it.
      expect(find.text(l10n.homeGreetingMorning('Anita')), findsOneWidget);
      expect(find.text('Ghorahi Health Post'), findsOneWidget);
      expect(find.text('2026-09-29'), findsOneWidget);

      // The scan card, and the manual fallback beside it.
      expect(find.text(l10n.providerScanQr), findsOneWidget);
      expect(find.text(l10n.providerScanManual), findsOneWidget);

      await finish(tester);
    });

    testWidgets('the footer names the protocol version', (tester) async {
      await pump(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      expect(
        find.text(l10n.homeProtocolVersion('2026-09-18.1')),
        findsOneWidget,
      );

      await finish(tester);
    });
  });

  group('populated', () {
    setUp(seed);

    testWidgets('counts today, flags Sita and Gita, lists what is due',
        (tester) async {
      await pump(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      /// The figure on the tile carrying [label].
      Finder tile(String label, String count) => find.descendant(
            of: find.ancestor(
              of: find.text(label),
              matching: find.byType(SoftCard),
            ),
            matching: find.text(count),
          );

      // Sita (contact recorded today) and Ram (visit today) were seen; the
      // visit is one; Gita's third contact is due today; one change waits.
      expect(tile(l10n.homeStatSeen, '2'), findsOneWidget);
      expect(tile(l10n.homeStatVisits, '1'), findsOneWidget);
      expect(tile(l10n.homeStatAncDue, '1'), findsOneWidget);
      expect(tile(l10n.homeStatPending, '1'), findsOneWidget);

      // Needs attention: Sita red first, Gita overdue second, Ram absent.
      expect(find.text(l10n.homeAttentionEmptyTitle), findsNothing);
      expect(find.text(l10n.homeTriageRed), findsOneWidget);
      expect(find.text(l10n.pregnancyContactOverdue), findsOneWidget);
      expect(
        find.textContaining('Severe hypertension'),
        findsOneWidget,
        reason: 'the reason is the rule table\'s sentence',
      );
      expect(find.textContaining('2nd contact was due on'), findsOneWidget);
      expect(find.text('30 years · Female'), findsOneWidget, reason: 'Sita');
      expect(find.text('31 years · Female'), findsOneWidget, reason: 'Gita');

      final sitaRow = tester.getTopLeft(find.text('Sita Kumari Chaudhary').first);
      final gitaRow = tester.getTopLeft(find.text('Gita Tharu').first);
      expect(sitaRow.dy, lessThan(gitaRow.dy), reason: 'red before overdue');

      // Due this week: Gita today, Sita in three days.
      expect(find.textContaining('3rd contact ·'), findsOneWidget);
      expect(find.textContaining('5th contact ·'), findsOneWidget);

      // Recent patients is topped up from the cache when nothing has been
      // opened yet: all three names appear somewhere on the screen.
      for (final name in ['Sita Kumari Chaudhary', 'Ram Bahadur Chaudhary', 'Gita Tharu']) {
        expect(find.text(name), findsWidgets, reason: name);
      }

      await finish(tester);
    });

    testWidgets('the tiles and the cards open the lists behind them',
        (tester) async {
      final router = await pump(tester);
      final l10n = await L.delegate.load(const Locale('en'));

      Future<void> home() async {
        router.go(ProviderTabs.home);
        await settle(tester);
        expect(find.byType(ProviderHomeTab), findsOneWidget);
      }

      // Patients seen → the Patients tab, filtered to today.
      await tester.tap(find.text(l10n.homeStatSeen));
      await settle(tester);
      expect(router.state.uri.toString(), '${ProviderTabs.patients}?seen=today');
      expect(find.byType(ProviderHomeScreen), findsOneWidget);
      expect(find.text(l10n.providerSeenTodayFilter), findsWidgets);
      // Ram is owned rather than granted, and still listed: seen is seen.
      expect(find.text('Ram Bahadur Chaudhary'), findsOneWidget);
      expect(find.text('Gita Tharu'), findsNothing);

      // Clearing the chip goes back to the whole (granted) list.
      await tester.tap(find.byTooltip(l10n.providerShowAllPatients));
      await settle(tester);
      expect(router.state.uri.toString(), ProviderTabs.patients);
      expect(find.text('Gita Tharu'), findsOneWidget);
      expect(find.text('Ram Bahadur Chaudhary'), findsNothing);

      await home();

      // Visits recorded → today's visits.
      await tester.tap(find.text(l10n.homeStatVisits));
      await settle(tester);
      expect(find.text('stub:visits'), findsOneWidget);
      await back(tester);

      // ANC due → the Reminders tab, with Gita in "Due today".
      await tester.tap(find.text(l10n.homeStatAncDue));
      await settle(tester);
      expect(router.state.uri.path, ProviderTabs.reminders);
      expect(find.byType(ProviderRemindersTab), findsOneWidget);
      expect(find.text('${l10n.providerRemindersDueToday} · 1'.toUpperCase()),
          findsOneWidget);
      expect(find.text('${l10n.dashboardOverdue} · 1'.toUpperCase()),
          findsOneWidget);

      await home();

      // Pending sync → the sync screen.
      await tester.tap(find.text(l10n.homeStatPending));
      await settle(tester);
      expect(find.text('stub:sync'), findsOneWidget);
      await back(tester);

      // The scan card and its text link both open the scanner — the link
      // asks for the manual dialog through the route.
      await tester.tap(find.text(l10n.homeScanSubtitle));
      await settle(tester);
      expect(find.text('stub:scan'), findsOneWidget);
      await back(tester);

      await tester.tap(find.text(l10n.providerScanManual));
      await settle(tester);
      expect(find.text('stub:scan ?manual=1'), findsOneWidget);
      await back(tester);

      // A needs-attention row opens the summary.
      await tester.tap(find.text('Gita Tharu').first);
      await settle(tester);
      expect(find.text('stub:patient $gitaId'), findsOneWidget);
      await back(tester);

      // "See all" under Due this week → Reminders.
      await tester.tap(find.text(l10n.homeSeeAll));
      await settle(tester);
      expect(router.state.uri.path, ProviderTabs.reminders);

      await finish(tester);
    });

    testWidgets('speaks Nepali', (tester) async {
      await pump(tester, locale: const Locale('ne'));
      final l10n = await L.delegate.load(const Locale('ne'));

      expect(find.text('शुभ प्रभात, Anita'), findsOneWidget);
      expect(find.text('ध्यान दिनुपर्ने'), findsOneWidget);
      expect(find.text('खतरा'), findsOneWidget);
      expect(find.text('म्याद नाघ्यो'), findsOneWidget);
      expect(find.text('यो हप्ताका जाँच'), findsOneWidget);
      expect(find.text('छिटो काम'), findsOneWidget);
      expect(find.text('गर्भावस्था दर्ता'), findsOneWidget);
      expect(find.text('नयाँ भेट'), findsOneWidget);
      // The rule table's reason, translated; the contact number as an ordinal.
      expect(find.textContaining('अति उच्च रक्तचाप'), findsOneWidget);
      expect(find.textContaining('दोस्रो जाँच'), findsOneWidget);
      // Bikram Sambat digits in the date line.
      expect(find.textContaining('२०८३'), findsWidgets);
      expect(find.text(l10n.homeProtocolVersion('2026-09-18.1')), findsOneWidget);

      await finish(tester);
    });

    for (final locale in const [Locale('en'), Locale('ne')]) {
      testWidgets(
          'does not overflow at font scale 1.3 on 360x780 in '
          '${locale.languageCode}', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final overflows = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          final text = details.exceptionAsString();
          if (text.contains('overflowed by')) {
            overflows.add(
              details
                  .toString()
                  .split('\n')
                  .where((line) => line.trim().isNotEmpty)
                  .take(14)
                  .join('\n  '),
            );
          } else {
            previous?.call(details);
          }
        };

        try {
          await pump(tester, locale: locale, size: const Size(360, 780));
          // Every section, not just the ones above the fold.
          final list = find.byType(Scrollable).first;
          for (var i = 0; i < 6; i++) {
            await tester.drag(list, const Offset(0, -400));
            await settle(tester);
          }
        } finally {
          FlutterError.onError = previous;
        }
        tester.takeException();

        expect(overflows, isEmpty, reason: overflows.join('\n'));

        await finish(tester);
      });
    }
  });
}

/// A signed-in, unlocked health worker, so the greeting has a name and a
/// facility to use.
class _SignedInProvider extends AuthController {
  @override
  AuthState build() => const AuthState(
        unlocked: true,
        hasPin: true,
        user: User(
          id: 'u_provider',
          phone: '+9779801000002',
          role: UserRole.provider,
          name: 'Anita Sharma',
          facilityId: 'f_0001',
          facilityName: 'Ghorahi Health Post',
          createdAt: '2026-01-01T00:00:00Z',
        ),
      );
}
