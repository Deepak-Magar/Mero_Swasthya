/**
 * Content for docs/EndUser_Verification_Report.docx.
 *
 * Kept apart from build_report.js so the findings can be edited without
 * touching the document structure.
 */
'use strict';

module.exports = {
  meta: {
    app: 'Mero Swasthya',
    subtitle: 'End-user (patient) phone — verification report',
    date: '20 September 2026',
    device: 'POCO M2102J20SI (Xiaomi), serial 483a08e5',
    android: 'Android 13 (SDK 33), MIUI',
    screen: '1080 × 2400 @ 440 dpi  (≈ 393 × 873 dp)',
    apk: 'build/MeroSwasthya-enduser-arm64-v8a.apk',
    apkSize: '33,818,767 bytes (32.3 MB)',
    flags: '--release --split-per-abi --dart-define=MOCK_API=true',
    analyze: 'No issues found',
    tests: '632 passing, 0 failing',
  },

  section1: {
    intro:
      'Every patient-side screen was opened on the phone in both languages and '
      + 'checked for overflow, clipped or truncated text, Devanagari rendering, '
      + 'contrast on the safety colours, touch targets, colours that escaped the '
      + 'token system, and consistent use of the soft-card style. "Restyled" means '
      + 'the screen uses the token system described in docs/UI_RESTYLE_REPORT.md; '
      + '"Verified" means it was seen on this handset, in both locales, on the '
      + 'final build. Screen numbers follow docs/FRONTEND_SPEC.md §11. A final '
      + 'walk of every screen with a cleared log buffer produced zero '
      + '"overflowed" lines and zero Flutter exceptions in logcat.',
    rows: [
      ['S01 Splash', 'Yes', 'n/a', 'Resolves in well under a second on this handset — it could not be caught in a screenshot even at a 0.3 s delay on a cold, logged-out start. No flash of white.'],
      ['S02 Phone entry', 'Yes', 'Yes', 'Field hairline added this session; language switch, Continue and the demo-code note all legible; targets ≥48 dp.'],
      ['S03 OTP', 'Yes', 'Yes', 'Tracked six-digit field; its ink is now taken from the colour scheme rather than the light-mode token.'],
      ['S04 PIN unlock', 'Yes', 'Yes', 'Dots carry a visible unfilled outline; keypad keys are 96 dp.'],
      ['S05 Set PIN + name', 'Yes', 'Yes', 'Name field and keypad on one screen; the confirm step repeats without a layout jump.'],
      ['S06 Family list', 'Yes', 'Yes', '"Namaste, <name>" over "My family"; last visit shown as a BS date with no AD tail; pregnancy badge on the card.'],
      ['S06 Overflow menu', 'Yes', 'Yes', '"I am a health worker" and Settings, both localised.'],
      ['S07 Add / edit patient', 'Yes', 'Yes', 'First section is headerless; every input has a hairline; sex segmented control; allergy and condition chips.'],
      ['S07 BS date picker', 'Yes', 'Yes', 'Devanagari weekday initials and day numerals in Nepali; future days correctly disabled for a date of birth.'],
      ['S08 Patient home (adult)', 'Yes', 'Yes', 'Allergy chip, QR call to action, four tiles, pregnancy card with week, EDD and next contact.'],
      ['S08 Patient home (child)', 'Yes', 'Yes', '"No known allergy" green chip; red overdue count badge on the child-health tile.'],
      ['S08 Patient home (not pregnant)', 'Yes', 'Yes', 'Third tile becomes "Register pregnancy"; the long Nepali label now wraps to two lines at full size.'],
      ['S08 Share record (QR)', 'Yes', 'Yes', 'Scope chips, QR, countdown, Regenerate and Revoke.'],
      ['S08 More sheet', 'Yes', 'Yes', 'Who viewed my record, printable card, export PDF.'],
      ['S09 Timeline', 'Yes', 'Yes', 'Grouped by BS month; triaged rows carry a coloured left edge that survives the release build.'],
      ['S09 Detail sheet', 'Yes', 'Yes', 'Vitals, diagnoses, prescriptions with the Nepali instruction and Speak; the triage band now reads the localised sentence instead of the wire word.'],
      ['S10 Documents (empty)', 'Yes', 'Yes', 'One call to action — the duplicate floating button is hidden while the grid is empty.'],
      ['S10 Documents (grid)', 'Yes', 'Yes', 'Type chip, BS date, upload state; the floating button returns once there is content.'],
      ['S10 Document detail', 'Yes', 'Yes', 'Zoomable viewer, type chip, upload state, AI draft-summary action.'],
      ['S11 Register pregnancy', 'Yes', 'Yes', 'LMP and EDD pickers, gravida/para steppers, eight bilingual risk factors; targets ≥48 dp.'],
      ['S12 Pregnancy dashboard', 'Yes', 'Yes', 'Week of 40, risk chip, EDD in BS, eight contacts, birth plan, delivery record, reminder previews.'],
      ['S12 Birth plan sheet', 'Yes', 'Yes', 'Facility picker with a map option, transport, blood donor and phone, escort, money set aside.'],
      ['S14 Printable card', 'Yes', 'Yes', 'QR, bilingual "ask for the PIN" note, share/save, one-year validity note.'],
      ['S15 Reminders', 'Yes', 'Yes', 'Demo SMS banner, scheduled chips, reminder bodies in the selected language.'],
      ['S16 Who saw my record', 'Yes', 'Yes', 'Audit rows with BS and AD dates.'],
      ['S17 Sync status', 'Yes', 'Yes', '"Everything is synced", 0 pending; the relative last-sync time is now localised.'],
      ['S23 Settings', 'Yes', 'Yes', 'Language, demo-data mode, server address, test connection, test reminder, versions, three integrations, logout.'],
      ['Child health', 'Yes', 'Yes', 'Vaccine list with given/overdue states, schedule-source banner, dose progress.'],
      ['Child growth', 'Yes', 'Yes', 'WHO weight-for-age band, Devanagari axis label, add-measurement action.'],
      ['PDF export', 'Yes', 'Yes', 'Shares as Sita-Chaudhary-2026-09-20.pdf; opens in an external viewer with Devanagari headings and the allergy band intact.'],
    ],
  },

  section2: {
    intro:
      'Run in order on a freshly installed app with the seeded demo data, in '
      + 'demo-data mode. Evidence is the screenshot named in the note, plus '
      + 'logcat where a check needed it. Screenshot names are relative to '
      + 'docs/screens/ and carry the enduser_ prefix.',
    rows: [
      [
        'a',
        'Fresh install → phone → OTP → PIN + name → family list',
        'PASS',
        'Phone 9801000009, OTP 123456, PIN 1234, name "Sita Chaudhary". The list comes back with Sita (Pregnant · week 30, allergy sulpha), Ram Bahadur (allergy penicillin) and Aarav (child). s02_phone_en, s03_otp_en, s05_setpin_en, s06_family_en.',
      ],
      [
        'b',
        'Kill → relaunch → PIN unlock with airplane mode on → data intact',
        'PASS',
        'Unlocks offline and every record is still there; the sync chip goes grey and returns to green when airplane mode is switched off. s04_pin_offline_en, s06_family_offline_en, s06_family_offline_relaunch_en.',
      ],
      [
        'c',
        'Add a member with a BS date of birth → pending → synced; edit → no duplicate',
        'PASS',
        'The new member appears at once with the pending mark, then clears; the edit bumps the version and produces no second row. s07_addmember_en, s06_family_pending_en, s06_family_synced_en, s06_family_added_en.',
      ],
      [
        'd',
        'Share record (QR): renders, counts down, regenerates, revokes; offline message',
        'PARTIAL',
        'QR, 10-minute countdown, Regenerate (new code) and Revoke (greyed, redeem refused) all pass. The "internet needed" path could not be exercised: with --dart-define=MOCK_API=true the transport runs inside the app, so turning the radio off does not make it unreachable. s08_share_en, s08_share_regenerated_en, s08_share_revoked_en, s08_share_offline_en.',
      ],
      [
        'e',
        'Timeline grouped by BS month; visit and contact detail sheets',
        'PASS',
        'Sita\'s contacts 1–3 and Ram\'s visit and two documents group under the right BS months. The visit sheet shows BP 138/86, weight 71.5 kg, diagnosis E11 and Metformin 500 mg with the Nepali instruction "खाना पछि"; the contact sheet shows findings and the triage band. s09_timeline_en/ne, s09_visit_medicines_en, s09_visit_detail_en/ne.',
      ],
      [
        'f',
        'Documents: capture with the real camera → thumbnail → detail → uploaded',
        'FAIL',
        'The MIUI camera service crashes before the app ever gets a frame — see section 4, defect F-1. Everything downstream of the capture was verified with the seeded documents instead: grid, detail, zoom and the uploaded state. s10_camera_crash.png, s10_documents_list_en/ne, s10_detail_en/ne.',
      ],
      [
        'g',
        'Pregnancy dashboard and birth plan',
        'PASS',
        'Week 30 of 40, EDD 2083 Mangsir 12 (2026-11-28), contacts 1–3 recorded and green, contact 4 due 2083 Ashoj 3 (today in device-local terms), 5–8 scheduled. Transport "Ambulance 9801000123" saved, app force-stopped, relaunched — still there. s12_pregnancy_en/ne, s12_birthplan_sheet_ne, s12_birthplan_typed_ne, s12_birthplan_persisted_ne.',
      ],
      [
        'h',
        'Register pregnancy visibility and the computed schedule',
        'PASS',
        'Hidden for Sita (active pregnancy — the tile reads "Pregnancy") and for Ram (male — the tile is the audit log); shown for Gita. EDD is LMP + 280 days and the schedule is exactly eight contacts at weeks 12, 20, 26, 30, 34, 36, 38 and 40. s08_home_ne, s08_home_ram_ne, s08_home_gita_en/ne, s11_register_pregnancy_en/ne, s11_edd_computed_en, s11_schedule_preview_en.',
      ],
      [
        'i',
        'Reminders, audit list, sync status',
        'PASS',
        'Two ANC reminders for Sita with the demo SMS banner; the audit list shows the two share codes that were generated; Sync reports "Everything is synced" with nothing pending. Forcing a rejected op was skipped: the build exposes no test hook for writing an invalid table, and faking one would have meant changing production code. s15_reminders_en/ne, s16_audit_en/ne, s17_sync_en/ne.',
      ],
      [
        'j',
        'Settings: language, demo mode, test connection, server URL, logout',
        'PASS',
        'The toggle flips every visible string — spot-checked on Settings, Family, Patient home, Timeline, Pregnancy, Reminders, Documents and Add member. Demo data mode on; Test connection returns the green tick with rules 2026-09-18.1. Server URL persistence failed at first and was fixed (defect D-8); it now survives a force-stop without pressing Test connection. Logout warns, erases the local records and returns to phone entry — after logging back in only the server-seeded household comes back. s23_settings_en/ne, s23_test_connection_en, s23_server_url_persisted_en, s23_logout_confirm_en/ne, s02_phone_en/ne, s06_family_en.',
      ],
      [
        'k',
        'Tier 2/3: printable card, PDF, child health, medicine reminder, Speak',
        'PASS',
        'Card renders and shares as a PNG with a print target; PDF exports, opens in an external viewer and keeps its Devanagari; child health shows the vaccine list with two overdue doses and the WHO growth band; the test medicine reminder fired 30 s later and appeared in the shade in Devanagari ("Metformin 500 mg खाना पछि"); Speak played through the speaker with a Nepali voice — logcat shows "GoogleTTSServiceImpl: TTS dispatch: ne-np-x-nep-seanet-embedded". s14_printed_card_en/ne, s14_card_share_ne, s08_pdf_devanagari_en/ne, child_health_en/ne, child_growth_en/ne, s23_reminder_shade_en, s09_speak_en.',
      ],
    ],
  },

  section3: {
    intro:
      'Each of these was found on the handset — or, for the last one, by the '
      + 'test suite while verifying it — then fixed in code and re-verified on a '
      + 'rebuilt APK. flutter analyze and the full test suite were run after '
      + 'every change and stayed green.',
    items: [
      {
        id: 'D-1',
        what: 'Accented cards vanished in the release build',
        where: 'lib/shared/widgets/soft_card.dart',
        symptom:
          'Every card with a coloured left edge — the triaged timeline rows, the failed-op rows on Sync — was invisible on the phone. In a debug build the same screens threw an unbounded-height assertion.',
        cause:
          'The accent was a sibling of the content inside a Row with CrossAxisAlignment.stretch. In an unbounded-height context that has no height to stretch to; with assertions compiled out of the release build it laid out infinitely tall and drew nothing.',
        fix:
          'The accent is now a Border(left:) on the content itself, so it takes the content\'s height and cannot ask for an unbounded one.',
        proof:
          'Two regression tests pump an accented SoftCard inside a real ListView and assert no exception, a finite height, and the same height as a plain card. Re-verified on the device: enduser_s09_timeline_ne.png.',
      },
      {
        id: 'D-2',
        what: 'Home tile labels were clipped, then shrunk without a floor',
        where: 'lib/shared/widgets/soft_card.dart (SoftTile)',
        symptom:
          'First "Documents" wrapped and left an orphaned "s" on a second line. After forcing one line, the long Nepali label "मेरो रेकर्ड कसले हेर्‍यो" came out at roughly half the size of the tile beside it.',
        cause:
          'Four tiles across a 393 dp phone leave about 70 dp of text each. A single line with FittedBox(scaleDown) fixed the wrap but let the scale factor fall as far as it liked.',
        fix:
          'The label now wraps to two lines at the tile\'s own measured width (LayoutBuilder + ConstrainedBox), with the FittedBox kept only as a last resort. Labels that fit in two lines stay at full size.',
        proof:
          'enduser_s08_home_ram_ne.png and enduser_s08_home_gita_ne.png; the 360 dp and 412 dp layout tests still pass in both locales.',
      },
      {
        id: 'D-3',
        what: 'The family card showed no date for the last visit',
        where: 'lib/features/family/family_screen.dart',
        symptom: 'Every row read "Last visit" with nothing after it.',
        cause: 'The label was rendered without the value the spec asks for.',
        fix:
          'The row is now a pair of Flexible children — the label and a BsDateText with the AD tail suppressed — per spec §13, BS first.',
        proof: 'enduser_s06_family_en.png ("Last visit 2083 Bhadra 9"), enduser_s06_family_ne.png.',
      },
      {
        id: 'D-4',
        what: 'Brand blue and the PIN dots failed contrast in dark mode',
        where: 'lib/core/theme/app_colors.dart, lib/core/theme/app_theme.dart, lib/features/auth/pin_keypad.dart',
        symptom:
          'On a dark phone the brand blue sat at roughly 1.6:1 against the dark surface, and the empty PIN dots were invisible.',
        cause: 'The tokens were defined for a light surface only and used unconditionally.',
        fix:
          'Dark variants of the brand, triage and tint tokens, resolved through AppColors.brand/brandTint/onBrand(context); the empty PIN dot now has both a fill and a visible outline.',
        proof: 'Contrast computed from the tokens; the dark pairs clear 4.5:1 for body and 3:1 for large text.',
      },
      {
        id: 'D-5',
        what: 'Text fields were invisible until they were focused',
        where: 'lib/core/theme/app_theme.dart (inputDecorationTheme)',
        symptom:
          'On the add-member form and the birth plan the inputs read as flat background; people could not tell where to tap.',
        cause:
          'The restyle brief asks for whitespace instead of borders, which was applied to inputs as well.',
        fix:
          'A deliberate, documented exception: enabled and disabled inputs now carry a hairline at 20% and 12% of the secondary ink. Everything else still groups with whitespace and a soft shadow.',
        proof: 'enduser_s07_addmember_en.png, enduser_s12_birthplan_sheet_ne.png, enduser_s23_settings_en.png.',
      },
      {
        id: 'D-6',
        what: 'Two competing calls to action on an empty Documents screen',
        where: 'lib/features/documents/documents_screen.dart, lib/features/family/patient_form_screen.dart',
        symptom:
          'The empty state offered "Capture a paper" and a floating button that did the same thing; the add-member form opened under a section header that repeated its own title.',
        cause: 'The empty state and the form were built without looking at the screen as a whole.',
        fix:
          'The floating button is hidden while the grid is empty, and the first form section is headerless.',
        proof: 'enduser_s10_documents_en.png versus enduser_s10_documents_list_en.png; enduser_s07_addmember_en.png.',
      },
      {
        id: 'D-7',
        what: 'Nepali strings that were not Nepali',
        where:
          'lib/core/l10n/app_ne.arb, lib/features/timeline/timeline_screen.dart, '
          + 'lib/features/sync/sync_screen.dart, lib/features/maternal/pregnancy_dashboard_screen.dart',
        symptom:
          'Four separate leaks: the gestation line read "४० मध्ये 30 हप्ता" with two different digit systems in one sentence; the triage band in the timeline detail sheet read the raw wire word "GREEN"; the sync screen read "अन्तिम सिंक just now"; and the reminder previews on the pregnancy dashboard were in English while the same reminders on S15 were in Nepali.',
        cause:
          'A hard-coded Devanagari 40 next to a Latin-digit placeholder; a .wire.toUpperCase() where a localised headline belongs; four English literals in a private helper; and a call site reading messageEn unconditionally.',
        fix:
          'The 40 is now written in the same digits as the placeholder. The band uses the same ancTriageRed/Amber/Green sentences as the ANC banner. Four new keys — syncJustNow, syncMinutesAgo, syncHoursAgo, syncDaysAgo — were added to both ARB files and generated. The dashboard picks messageNp when the locale is Nepali.',
        proof:
          'enduser_s08_home_ne.png, enduser_s09_visit_detail_ne.png, enduser_s17_sync_ne.png, enduser_s12_birthplan_ne.png.',
      },
      {
        id: 'D-8',
        what: 'The server address was thrown away unless "Test connection" was pressed',
        where: 'lib/features/settings/settings_screen.dart',
        symptom:
          'Typing an address, leaving Settings and relaunching brought back the old one. Reproduced on the device: 192.168.1.50 was typed, the app was force-stopped, and 10.0.2.2 came back.',
        cause:
          'setBaseUrl was only ever called from _testConnection. The controller held the text and nothing wrote it to preferences.',
        fix:
          'The field persists as it is typed (onChanged → setBaseUrl). Test connection still saves first, so it still exercises the address it is about to use.',
        proof: 'enduser_s23_server_url_persisted_en.png — the typed address survives a force-stop with no button pressed.',
      },
      {
        id: 'D-9',
        what: 'The versions card went blank and then stayed stale',
        where: 'lib/features/settings/settings_screen.dart',
        symptom:
          'After one reach for a server that was not there, "Code list version" was an empty row rather than "Unknown", and switching demo-data mode back on left both versions showing the failed answer for the rest of the session.',
        cause:
          'AppConfigFlags defaults codelistVersion to an empty string, so the ?? fallback never fired; and configFlagsProvider is a cached FutureProvider that nobody invalidated when the transport changed.',
        fix:
          'The row treats empty as unknown, and the provider is invalidated when the transport is switched and after a successful list refresh.',
        proof:
          'enduser_s23_server_url_persisted_en.png (both rows read "Unknown" with no server) and enduser_s23_settings_ne.png (both rows repopulate the moment demo mode comes back).',
      },
      {
        id: 'D-10',
        what: 'Five widgets painted light-mode ink regardless of the theme',
        where:
          'lib/features/auth/otp_screen.dart, lib/features/maternal/anc_contact_screen.dart, '
          + 'lib/features/patient_home/share_sheet.dart, lib/features/shared/widgets/app_widgets.dart, '
          + 'lib/shared/widgets/soft_card.dart',
        symptom:
          'The OTP digits, the danger-sign labels, the share countdown, the stepper value and the selected segmented chip all used the light-mode token directly — near-black on a near-black surface on a dark phone, and white on pale blue for the selected chip.',
        cause: 'AppColors.textPrimary and AppColors.onBrand used without resolving the brightness.',
        fix: 'All five now read Theme.of(context).colorScheme.onSurface, or AppColors.onBrandOf(context) for the chip.',
        proof: 'Light mode is pixel-identical (the scheme resolves to the same token); the dark pairs now clear 4.5:1.',
      },
      {
        id: 'D-11',
        what: 'Queued operations could be pushed out of order',
        where: 'lib/data/local/outbox.dart',
        symptom:
          'The suite failed once in roughly a few hundred runs: "more than one batch is pushed in created_at order" reported v_44 where v_43 was expected.',
        cause:
          'created_at is a TEXT column that is both ordered and max()-ed as text, while DateTime.toIso8601String() prints three fractional digits when the microseconds are zero and six when they are not. "…12.123Z" sorts after "…12.123456Z", so two operations queued inside the same millisecond could come back swapped — and the comment on that method says ordering is the whole contract, because registering a pregnancy enqueues the pregnancy and its eight contacts together.',
        fix:
          'Timestamps are truncated to milliseconds before being written, so every stamp is the same width and text order matches time order. The existing "later than everything queued" guard is unchanged.',
        proof:
          'A new test queues forty operations and asserts every stored stamp has the same length, ends in "mmmZ", and that sorting the stamps as text leaves them in insertion order. Suite: 632 passing.',
      },
    ],
  },

  section4: {
    intro:
      'One open failure. It is a fault in the handset\'s camera stack, not in '
      + 'the app — Mero Swasthya does not appear anywhere in the stack trace — '
      + 'but it blocks the "photograph a paper record" demo on this phone.',
    items: [
      {
        id: 'F-1',
        what: 'The camera cannot be opened on this handset',
        severity:
          'Blocks functional check (f) on this phone. Everything downstream of the capture — grid, detail, zoom, upload state — works, and the seeded documents demonstrate it.',
        repro:
          '1. Open any patient → Documents → "Capture a paper". 2. The preview appears. 3. Tap the shutter, or leave the preview and come back after the system camera has been force-stopped. The preview freezes or the picker closes with no image. Reproduced repeatedly, including immediately after granting the camera permission with pm grant and after a reboot of the camera provider.',
        error:
          'java.lang.IllegalArgumentException: getCameraCharacteristics:791: Unable to retrieve camera characteristics for unknown device -1: No such file or directory (-2) — thrown from com.xiaomi.camera.imagecodec.impl.VirtualCameraReprocessor.openVTCamera(VirtualCameraReprocessor.java:539). Screenshot: enduser_s10_camera_crash.png.',
        cause:
          'MIUI\'s virtual-camera reprocessor asks the HAL for characteristics of camera id -1 — a device that does not exist. It is raised inside Xiaomi\'s own camera service before any frame reaches the app, and no Mero Swasthya frame is on the stack. The most likely trigger is the MIUI camera service being left in a bad state on this unit.',
        fix:
          'Not fixable from the app. For the demo: reboot the phone before going on stage and open the stock Camera app once to prove the hardware answers — that clears the state in most cases. If it does not, skip the live capture and show the two seeded documents (discharge sheet, fasting blood sugar) instead; the rest of the documents flow is unaffected. A permanent fix would be a MIUI update or a different handset.',
      },
    ],
  },

  section5: {
    intro:
      'English on the left, Nepali on the right, both captured on this handset '
      + 'from the final build. S01 is omitted: the splash resolves too quickly '
      + 'to photograph on this phone.',
    screens: [
      { label: 'S02 — Phone number', en: 'enduser_s02_phone_en.png', ne: 'enduser_s02_phone_ne.png', note: 'Demo-mode note gives the OTP; field hairline added this session.' },
      { label: 'S03 — One-time code', en: 'enduser_s03_otp_en.png', ne: 'enduser_s03_otp_ne.png', note: 'Tracked six-digit field with a resend countdown.' },
      { label: 'S04 — PIN unlock', en: 'enduser_s04_pin_en.png', ne: 'enduser_s04_pin_ne.png', note: 'Empty dots carry a visible outline; keys are 96 dp.' },
      { label: 'S05 — Create your PIN', en: 'enduser_s05_setpin_en.png', ne: 'enduser_s05_setpin_ne.png', note: 'Name and PIN on one screen.' },
      { label: 'S06 — Family list', en: 'enduser_s06_family_en.png', ne: 'enduser_s06_family_ne.png', note: 'Greeting, sync chip, BS last-visit date, pregnancy badge.' },
      { label: 'S06 — Overflow menu', en: 'enduser_s06_menu_en.png', ne: 'enduser_s06_menu_ne.png', note: 'Become a provider device, or open Settings.' },
      { label: 'S07 — Add family member', en: 'enduser_s07_addmember_en.png', ne: 'enduser_s07_addmember_ne.png', note: 'Headerless first section; every input has a hairline.' },
      { label: 'S07 — BS date picker', en: 'enduser_s07_bs_datepicker_en.png', ne: 'enduser_s07_bs_datepicker_ne.png', note: 'Devanagari numerals in Nepali; future days disabled.' },
      { label: 'S08 — Patient home (pregnant)', en: 'enduser_s08_home_en.png', ne: 'enduser_s08_home_ne.png', note: 'Allergy chip, QR, four tiles, pregnancy card.' },
      { label: 'S08 — Patient home (child)', en: 'enduser_s08_home_child_en.png', ne: 'enduser_s08_home_child_ne.png', note: 'Green "no known allergy" chip and the overdue badge.' },
      { label: 'S08 — Patient home (not pregnant)', en: 'enduser_s08_home_gita_en.png', ne: 'enduser_s08_home_gita_ne.png', note: 'Third tile becomes Register pregnancy; label wraps at full size.' },
      { label: 'S08 — Patient home (male)', en: 'enduser_s08_home_ram_en.png', ne: 'enduser_s08_home_ram_ne.png', note: 'No pregnancy tile; the audit tile takes its place.' },
      { label: 'S08 — Share record (QR)', en: 'enduser_s08_share_en.png', ne: 'enduser_s08_share_ne.png', note: 'Scope chips, countdown, regenerate and revoke.' },
      { label: 'S08 — More sheet', en: 'enduser_s08_more_en.png', ne: 'enduser_s08_more_ne.png', note: 'Audit log, printable card, export PDF.' },
      { label: 'S09 — Timeline (pregnancy)', en: 'enduser_s09_timeline_en.png', ne: 'enduser_s09_timeline_ne.png', note: 'Grouped by BS month; triage accents visible in release.' },
      { label: 'S09 — Timeline (visits and documents)', en: 'enduser_s09_timeline_ram_en.png', ne: 'enduser_s09_timeline_ram_ne.png', note: 'Ram\'s visit and two documents.' },
      { label: 'S09 — Contact detail sheet', en: 'enduser_s09_visit_detail_en.png', ne: 'enduser_s09_visit_detail_ne.png', note: 'Localised triage band over the findings table.' },
      { label: 'S10 — Documents (empty)', en: 'enduser_s10_documents_en.png', ne: 'enduser_s10_documents_ne.png', note: 'One call to action; the floating button is hidden.' },
      { label: 'S10 — Documents (grid)', en: 'enduser_s10_documents_list_en.png', ne: 'enduser_s10_documents_list_ne.png', note: 'Type chip, BS date, uploaded state.' },
      { label: 'S10 — Document detail', en: 'enduser_s10_detail_en.png', ne: 'enduser_s10_detail_ne.png', note: 'Viewer, type, upload state, AI draft summary.' },
      { label: 'S11 — Register pregnancy', en: 'enduser_s11_register_pregnancy_en.png', ne: 'enduser_s11_register_pregnancy_ne.png', note: 'LMP and EDD, gravida and para steppers.' },
      { label: 'S11 — Risk factors', en: 'enduser_s11_risk_factors_en.png', ne: 'enduser_s11_risk_factors_ne.png', note: 'Eight bilingual risk factors, 48 dp rows.' },
      { label: 'S12 — Pregnancy dashboard', en: 'enduser_s12_pregnancy_en.png', ne: 'enduser_s12_pregnancy_ne.png', note: 'Week, risk chip, EDD, eight contacts.' },
      { label: 'S12 — Birth plan and reminders', en: 'enduser_s12_birthplan_en.png', ne: 'enduser_s12_birthplan_ne.png', note: 'Reminder previews now follow the app language.' },
      { label: 'S12 — Birth plan sheet', en: 'enduser_s12_birthplan_sheet_en.png', ne: 'enduser_s12_birthplan_sheet_ne.png', note: 'Facility, transport, blood donor, escort, money set aside.' },
      { label: 'S14 — Printable card', en: 'enduser_s14_printed_card_en.png', ne: 'enduser_s14_printed_card_ne.png', note: 'QR plus the bilingual "ask for the PIN" note.' },
      { label: 'S15 — Reminders', en: 'enduser_s15_reminders_en.png', ne: 'enduser_s15_reminders_ne.png', note: 'Demo SMS banner and scheduled chips.' },
      { label: 'S16 — Who viewed my record', en: 'enduser_s16_audit_en.png', ne: 'enduser_s16_audit_ne.png', note: 'One row per share code generated.' },
      { label: 'S17 — Sync status', en: 'enduser_s17_sync_en.png', ne: 'enduser_s17_sync_ne.png', note: 'Relative last-sync time, now localised.' },
      { label: 'S23 — Settings', en: 'enduser_s23_settings_en.png', ne: 'enduser_s23_settings_ne.png', note: 'Language, demo mode, server address, versions.' },
      { label: 'S23 — Integrations and logout', en: 'enduser_s23_settings_logout_en.png', ne: 'enduser_s23_settings_logout_ne.png', note: 'Three honest "not connected" cards, then Log out.' },
      { label: 'S23 — Logout confirmation', en: 'enduser_s23_logout_confirm_en.png', ne: 'enduser_s23_logout_confirm_ne.png', note: 'Says plainly that local records are erased.' },
      { label: 'Child health', en: 'enduser_child_health_en.png', ne: 'enduser_child_health_ne.png', note: 'Vaccine list with given and overdue states.' },
      { label: 'Child growth', en: 'enduser_child_growth_en.png', ne: 'enduser_child_growth_ne.png', note: 'WHO weight-for-age band with a Devanagari axis.' },
      { label: 'PDF export — share sheet', en: 'enduser_s08_pdf_share_en.png', ne: 'enduser_s08_pdf_share_ne.png', note: 'Sita-Chaudhary-2026-09-20.pdf.' },
      { label: 'PDF export — rendered', en: 'enduser_s08_pdf_devanagari_en.png', ne: 'enduser_s08_pdf_devanagari_ne.png', note: 'Bilingual headings and the allergy band, in an external viewer.' },
    ],
  },

  section6: {
    verdict:
      'Yes, with one substitution. Thirty patient-side screens were checked on '
      + 'this handset in both languages on the final build; eleven defects were '
      + 'found and fixed, and every fix was re-verified on a rebuilt APK with '
      + 'flutter analyze clean and 632 tests passing. A full walk of the app '
      + 'with a cleared log buffer produced no RenderFlex overflow and no '
      + 'Flutter exception. The one thing that does not work is photographing a '
      + 'paper record: this phone\'s MIUI camera service throws before the app '
      + 'sees a frame, and the app is nowhere in the stack. Reboot the phone '
      + 'before the demo and open the stock Camera app once; if the capture '
      + 'still fails, open Documents for Ram Bahadur and show the two seeded '
      + 'records instead — the rest of that flow is unaffected. Everything else '
      + 'the patient does on stage — sign in, read the family, share the QR, '
      + 'read the timeline, follow the pregnancy, get a reminder, switch '
      + 'language — works on this device.',
    checklist: [
      'Charge to 100% and leave it on the cable. The phone is set to stay awake while plugged in, with the screen timeout and auto-rotation already pinned.',
      'Reinstall from build/MeroSwasthya-enduser-arm64-v8a.apk (adb install -r) for a clean seed, or log out from Settings, which has the same effect on the local records.',
      'Sign in as +977 9801000009, one-time code 123456, PIN 1234, name "Sita Chaudhary". The family comes back as Aarav, Ram Bahadur and Sita.',
      'Settings → language → नेपाली. The phone is already left in Nepali.',
      'Settings → Demo data mode ON. It needs no network and no server; leave the address at http://10.0.2.2:3000/api/v1.',
      'Allow notifications when asked, or grant it beforehand — the medicine reminder in section 2(k) needs it.',
      'Reboot once, then open the stock Camera app and close it, before you rely on the "capture a paper" step.',
      'Optional dry run: Settings → "Test a medicine reminder", then wait 30 seconds and check the shade.',
      'Turn off any battery saver, and leave airplane mode off unless you are deliberately demonstrating the offline queue.',
    ],
  },
};
