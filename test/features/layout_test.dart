import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/config/app_config.dart';
import 'package:mero_swasthya/core/net/mock_api.dart';
import 'package:mero_swasthya/core/providers.dart';
import 'package:mero_swasthya/data/local/app_database.dart';
import 'package:mero_swasthya/data/sync/connectivity.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/audit/audit_screen.dart';
import 'package:mero_swasthya/features/auth/otp_screen.dart';
import 'package:mero_swasthya/features/auth/phone_screen.dart';
import 'package:mero_swasthya/features/auth/pin_screen.dart';
import 'package:mero_swasthya/features/auth/set_pin_screen.dart';
import 'package:mero_swasthya/features/child/child_health_screen.dart';
import 'package:mero_swasthya/features/documents/documents_screen.dart';
import 'package:mero_swasthya/features/shell/patient_home_tab.dart';
import 'package:mero_swasthya/features/shell/patient_more_tab.dart';
import 'package:mero_swasthya/features/shell/provider_more_tab.dart';
import 'package:mero_swasthya/features/family/patient_form_screen.dart';
import 'package:mero_swasthya/features/maternal/anc_contact_screen.dart';
import 'package:mero_swasthya/features/maternal/delivery_screen.dart';
import 'package:mero_swasthya/features/maternal/pregnancy_dashboard_screen.dart';
import 'package:mero_swasthya/features/maternal/register_pregnancy_screen.dart';
import 'package:mero_swasthya/features/patient_home/patient_home_screen.dart';
import 'package:mero_swasthya/features/provider/provider_activate_screen.dart';
import 'package:mero_swasthya/features/provider/provider_dashboard_screen.dart';
import 'package:mero_swasthya/features/provider/provider_home_screen.dart';
import 'package:mero_swasthya/features/provider/provider_patient_screen.dart';
import 'package:mero_swasthya/features/provider/visit_form_screen.dart';
import 'package:mero_swasthya/features/reminders/reminders_screen.dart';
import 'package:mero_swasthya/features/settings/settings_screen.dart';
import 'package:mero_swasthya/features/sync/sync_screen.dart';
import 'package:mero_swasthya/features/timeline/timeline_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

/// Layout regression cover for the restyle.
///
/// Every screen is pumped in **both locales** at **two phone sizes**, and the
/// test fails if anything reports a `RenderFlex overflowed` during layout.
///
/// Both halves of that matter:
///
///  * Nepali is not a translation of English with the same metrics. Devanagari
///    runs longer, wraps differently and sits taller, and the restyle moved a
///    lot of text into fixed-width places — chips, tiles, a two-column stepper
///    grid, a segmented control. Almost every overflow this file has to catch
///    is Nepali-only.
///  * 360×780 is the small Android phone the app is actually for. 412×915 is
///    there so a layout cannot be tuned to exactly one width and break either
///    side of it.
///
/// No goldens: a golden would pin the pixels, which is the opposite of what a
/// restyle wants. This pins the one property that must hold whatever the design
/// looks like — that it fits.
const patientId = 'p_layout';
const pregnancyId = 'preg_layout';
const childId = 'c_layout';

void main() {
  // 360×780 is a Redmi-class handset; 412×915 a Pixel-class one.
  const sizes = <String, Size>{
    '360x780': Size(360, 780),
    '412x915': Size(412, 915),
  };
  const locales = [Locale('en'), Locale('ne')];

  late AppDatabase db;

  setUpAll(() {
    // Every test opens its own in-memory database and never closes it (see
    // below), so drift sees the class constructed many times and warns about a
    // shared executor. There is no shared executor here — each one is its own
    // `NativeDatabase.memory()` — and the warning is forty lines per test.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seed(db);
  });

  // No `db.close()` in a tearDown, deliberately — the same choice
  // `grant_sections_test.dart` and `printed_card_test.dart` make.
  //
  // Closing a Drift database waits for its open query streams to finish
  // cancelling, and cancellation completes on a zero-duration timer. Inside
  // `testWidgets` the clock is fake, so nothing advances it once the body has
  // returned and the close never completes — the test passes and then the
  // suite hangs in teardown. The database is in memory and per test; letting
  // it fall out of scope is enough.

  /// Pumps [screen] at [size] in [locale] and fails on any overflow.
  ///
  /// The overflow is captured through `FlutterError.onError` rather than
  /// `tester.takeException()` because a single frame can report several, and
  /// all of them are worth naming in the failure message.
  Future<void> expectNoOverflow(
    WidgetTester tester,
    String label,
    Widget screen, {
    required Size size,
    required Locale locale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      // "A RenderFlex overflowed by 23 pixels on the right." — the only
      // failure this test is interested in. Anything else (a missing plugin,
      // an image that cannot be decoded in a headless test) is passed through
      // to the normal reporter so it is not silently swallowed.
      if (text.contains('overflowed by')) {
        // The message says how much but not what, and "what" is the only part
        // anybody fixing this needs. `details.toString()` carries the render
        // object's `debugCreator` chain, which names the widget and the file
        // it was written in; the first few lines of it are enough.
        final report = details
            .toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .take(14)
            .join('\n  ');
        overflows.add('${text.split('\n').first.trim()}\n  $report');
      } else {
        previous?.call(details);
      }
    };

    try {
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
    } finally {
      FlutterError.onError = previous;
    }

    // Drain anything the binding latched onto so it cannot leak into the next
    // test as a spurious failure.
    tester.takeException();

    expect(
      overflows,
      isEmpty,
      reason: '$label overflowed at ${size.width.toInt()}x'
          '${size.height.toInt()} in ${locale.languageCode}:\n'
          '${overflows.join('\n')}',
    );

    // Let anything the screen scheduled on open — a mock API's simulated
    // latency, a codelist warm-up — come back before the tree is torn down, so
    // it is not reported as a leaked timer.
    await tester.pump(const Duration(seconds: 3));
    await unmount(tester);
  }

  /// One screen, four combinations.
  void screenFits(String label, Widget Function() build) {
    for (final entry in sizes.entries) {
      for (final locale in locales) {
        testWidgets('$label fits at ${entry.key} in ${locale.languageCode}',
            (tester) async {
          await expectNoOverflow(
            tester,
            label,
            build(),
            size: entry.value,
            locale: locale,
          );
        });
      }
    }
  }

  group('patient screens', () {
    screenFits('S02 phone', () => const PhoneScreen());
    screenFits('S03 OTP', () => const OtpScreen());
    screenFits('S04 PIN unlock', () => const PinScreen());
    screenFits('S05 set PIN', () => const SetPinScreen());
    // S06 is the shell's Home tab now: the family strip and the selected
    // member's record on one screen.
    screenFits('S06 home tab', () => const PatientHomeTab());
    screenFits('patient More tab', () => const PatientMoreTab());
    screenFits('S07 patient form', () => const PatientFormScreen());
    screenFits('S08 patient home',
        () => const PatientHomeScreen(patientId: patientId));
    screenFits(
        'S09 timeline', () => const TimelineScreen(patientId: patientId));
    screenFits(
        'S10 documents', () => const DocumentsScreen(patientId: patientId));
    screenFits(
      'S11 register pregnancy',
      () => const RegisterPregnancyScreen(patientId: patientId),
    );
    screenFits(
      'S12 pregnancy dashboard',
      () => const PregnancyDashboardScreen(pregnancyId: pregnancyId),
    );
    screenFits(
      'S14 delivery',
      () => const DeliveryScreen(pregnancyId: pregnancyId),
    );
    screenFits(
        'S15 reminders', () => const RemindersScreen(patientId: patientId));
    screenFits('S16 audit', () => const AuditScreen(patientId: patientId));
    screenFits('S17 sync', () => const SyncScreen());
    screenFits('S23 settings', () => const SettingsScreen());
    screenFits(
      'child health',
      () => const ChildHealthScreen(patientId: childId),
    );
  });

  group('provider screens', () {
    screenFits('S18 activation', () => const ProviderActivateScreen());
    screenFits('S19 patients tab', () => const ProviderHomeScreen());
    screenFits('provider More tab', () => const ProviderMoreTab());
    screenFits(
      'S21 provider summary',
      () => const ProviderPatientScreen(patientId: patientId),
    );
    screenFits(
      'S22 add visit',
      () => const VisitFormScreen(patientId: patientId),
    );
    screenFits('Tier 2 dashboard', () => const ProviderDashboardScreen());
  });

  group('S13 ANC contact', () {
    // The one screen whose layout changes with its own data: the triage banner
    // and the referral card only appear once something has gone wrong, and the
    // referral card is the widest thing on the screen when they do. Both
    // states are covered.
    screenFits(
      'S13 ANC contact (routine)',
      () => const AncContactScreen(pregnancyId: pregnancyId, contactNo: 1),
    );
    screenFits(
      'S13 ANC contact (red, with referral)',
      () => const AncContactScreen(pregnancyId: pregnancyId, contactNo: 2),
    );
  });
}

/// A record with something in every section, so the layouts are exercised full
/// rather than empty.
///
/// The long Nepali strings are deliberate: an allergy chip, a medicine
/// instruction and a reminder body are exactly where a Devanagari overflow
/// shows up, and seeding them short would make this file pass for the wrong
/// reason.
Future<void> _seed(AppDatabase db) async {
  const patient = Patient(
    id: patientId,
    // Empty owner: S06 reads `auth.user?.id ?? ''`, and these tests run with no
    // session, so this is the id the family list will actually query for.
    ownerUserId: '',
    name: 'Sita Kumari Chaudhary',
    sex: Sex.female,
    dob: '1996-04-11',
    bloodGroup: 'B+',
    ward: 7,
    municipality: 'Ghorahi Upa-Mahanagarpalika',
    allergies: ['sulpha', 'पेनिसिलिन', 'धुलो र परागकण'],
    chronicConditions: ['E11', 'I10'],
    emergencyContactPhone: '+9779841000000',
  );

  const child = Patient(
    id: childId,
    ownerUserId: '',
    name: 'Ram Bahadur Chaudhary',
    sex: Sex.male,
    dob: '2024-02-01',
  );

  await db.patientsDao.upsert(patient);
  await db.patientsDao.upsert(child);

  // S19 lists patients whose grant has not expired yet.
  await db.patientsDao.upsert(
    patient,
    accessUntil: Value(
      DateTime.now().toUtc().add(const Duration(hours: 6)).toIso8601String(),
    ),
  );
  await db.syncMetaDao.setReadOnlyAccess(patientId, value: false);
  await db.syncMetaDao.setGrantSections(patientId, const []);

  await db.visitsDao.upsert(
    Visit(
      id: 'v_layout',
      patientId: patientId,
      providerName: 'Anita Sharma, ANM',
      facilityName: 'Ghorahi Primary Health Care Centre',
      visitAt: '2026-09-01T10:00:00Z',
      chiefComplaintCode: 'FEVER',
      vitals: const Vitals(
        bpSys: 150,
        bpDia: 95,
        pulse: 88,
        tempC: 38.4,
        weightKg: 52.5,
        spo2: 96,
      ),
      diagnosisCodes: const ['E11', 'I10'],
      advice: 'Rest, fluids, and return if the fever does not settle.',
      prescriptions: const [
        Prescription(
          id: 'rx_layout',
          drugCode: 'AMOX500',
          drugName: 'Amoxicillin 500 mg',
          dose: '1 tab',
          frequency: PrescriptionFrequency.tds,
          durationDays: 5,
          instructionsNp: 'खाना खाएपछि दिनको तीन पटक न्यानो पानीसँग खानुहोस्',
        ),
      ],
    ),
  );

  await db.documentsDao.upsert(
    const Document(
      id: 'doc_layout',
      patientId: patientId,
      type: DocumentType.discharge,
      title: 'Bharatpur Hospital discharge sheet',
      takenAt: '2026-08-20',
    ),
  );

  await db.pregnanciesDao.upsertPregnancy(
    const Pregnancy(
      id: pregnancyId,
      patientId: patientId,
      lmp: '2026-02-01',
      edd: '2026-11-08',
      gravida: 3,
      para: 1,
      riskFactors: ['PREV_CS'],
      riskLevel: RiskLevel.high,
      birthPlan: BirthPlan(
        facilityName: 'Ghorahi Birthing Centre',
        transport: 'Neighbour\'s jeep',
        moneySaved: true,
        bloodDonorName: 'Hari Chaudhary',
        companionName: 'Maya Chaudhary',
      ),
    ),
  );

  await db.pregnanciesDao.upsertContacts([
    const AncContact(
      id: 'anc_1',
      pregnancyId: pregnancyId,
      contactNo: 1,
      weekTarget: 12,
      dueAt: '2026-04-26',
      doneAt: '2026-04-26T09:00:00Z',
      triageLevel: TriageLevel.green,
    ),
    const AncContact(
      id: 'anc_2',
      pregnancyId: pregnancyId,
      contactNo: 2,
      weekTarget: 20,
      dueAt: '2026-06-21',
      // Red, so S13 renders the banner, the referral card and the call button.
      findings: Findings(bpSys: 160, bpDia: 110, hbGdl: 6.2),
      dangerSigns: ['SEVERE_HEADACHE'],
      triageLevel: TriageLevel.red,
      triageReasons: [
        'Severe hypertension (BP 160/110)',
        'Severe anaemia (Hb < 7)',
      ],
      referral: Referral(
        facilityId: 'f_bc_ghorahi',
        facilityName: 'Ghorahi Birthing Centre',
        reason: 'Severe hypertension with headache at 20 weeks',
        urgency: ReferralUrgency.urgent,
      ),
    ),
    const AncContact(
      id: 'anc_3',
      pregnancyId: pregnancyId,
      contactNo: 3,
      weekTarget: 26,
      dueAt: '2026-08-02',
    ),
  ]);

  await db.cacheDao.replaceReminders(patientId, const [
    Reminder(
      id: 'rem_layout',
      patientId: patientId,
      pregnancyId: pregnancyId,
      kind: ReminderKind.ancDue,
      dueAt: '2026-08-02',
      recipientRole: RecipientRole.family,
      messageNp: 'तपाईंको गर्भ जाँचको समय आयो — नजिकैको स्वास्थ्य चौकीमा जानुहोस्',
      messageEn: 'Your antenatal check-up is due. Please visit the health post.',
      status: ReminderStatus.sent,
    ),
  ]);

  await db.cacheDao.upsertAudit(const [
    AuditEntry(
      id: 'aud_layout',
      patientId: patientId,
      actorUserId: 'u_provider',
      actorName: 'Anita Sharma',
      actorFacilityName: 'Ghorahi Primary Health Care Centre',
      action: AuditAction.grantRedeemed,
      at: '2026-09-01T10:00:00Z',
    ),
  ]);

  await db.childHealthDao.upsertImmunisations(const [
    Immunisation(
      id: 'imm_1',
      patientId: childId,
      vaccineCode: 'BCG',
      doseNo: 1,
      dueAt: '2024-02-01',
      givenAt: '2024-02-03',
    ),
    Immunisation(
      id: 'imm_2',
      patientId: childId,
      vaccineCode: 'PENTA',
      doseNo: 2,
      dueAt: '2024-04-01',
    ),
  ]);

  await db.childHealthDao.upsertGrowth(
    const GrowthMeasurement(
      id: 'gm_1',
      patientId: childId,
      measuredAt: '2024-06-01',
      weightKg: 6.4,
      heightCm: 62,
    ),
  );
}
