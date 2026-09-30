# Provider Home dashboard and navigation rework

**Date.** 2026-09-30.
**Scope.** The health-worker role no longer opens on the camera. It opens on a
Home dashboard, the bottom bar is *Home · Patients · [Scan] · Reminders ·
More* with a raised brand-blue Scan button in the middle, and the dashboard
carries a large "Scan patient QR" card. The scanner screen, the `SWC1`/`SWC2`
decoding and "Enter code instead" are unchanged apart from the route that
opens them. Patient-side navigation is untouched.

Read after `docs/UX_AUDIT.md`: that pass turned the provider side into a
three-tab shell with Scan as the landing tab; this one replaces that shell.
`docs/PROVIDER_DEVICE_REPORT.md` did not exist when this pass ran.

---

## What changed

### Navigation

| Before (UX pass) | After |
|---|---|
| `ShellScaffold` with three tabs, Scan first, one tab built at a time | `StatefulShellRoute.indexedStack` with four branches — `/provider` (Home), `/provider/patients`, `/provider/reminders`, `/provider/more` |
| Scan is a tab; the camera is up on launch | Scan is a pushed route (`/provider/scan`) opened from a docked circular button in the centre of the bar, on every tab, and from the Home scan card |
| Back from Patients/More → Scan | Back from any tab → Home; back from Home leaves the shell to the platform (exits) |
| Two coach cards over the Scan tab | Two coach cards over Home, each cutting a window in the scrim around its target: the centre Scan button, then the Needs-attention list |

The bar is a `BottomAppBar` with a `CircularNotchedRectangle` and a
`FloatingActionButton` docked `centerDocked`. It is hand-built rather than a
`NavigationBar` (Material's bar has no notch) but keeps the theme's metrics:
68 dp, tinted pill behind the selected icon, 12 px labels, and a "Scan" label
under the button so the centre control is a word as well as a glyph. Labels
are clamped at 1.3× text scale and shrink rather than ellipse.

Because the camera is no longer a tab, the branches can live in an
`IndexedStack`: switching tabs keeps scroll positions, and the scanner's
`MobileScannerController` is created when the route is pushed and disposed
when it is popped — which is the lifecycle it wants. Coming back to Home or
Reminders re-asks Drift with the current time (`ref.invalidate`), and coming
back to Patients does the same for the grant window, so a phone left open
overnight does not call yesterday "today".

Every `context.go('/provider')` — the auth redirect, activation, "Health
worker mode" — lands on Home without knowing the shell exists. All other
`/provider/...` screens (summary, visit form, dashboard, scan, today's visits)
are top-level routes pushed over the shell, so the bar belongs to the tabs
alone.

### Home tab (`ProviderHomeTab`), top to bottom

| Block | Content | Source | Tap |
|---|---|---|---|
| Header | Greeting by time of day (*Good morning* < 12:00, *Namaste* < 17:00, *Good evening*), first name, facility, today in BS with AD small underneath, compact `SyncPill` on the right | `authProvider`, `clockProvider` | pill → `/sync` |
| Scan card | Full-width brand-blue `SoftCard`, QR icon, "Scan patient QR", one-line subtitle, "Enter code instead" text link | — | card → `/provider/scan`; link → `/provider/scan?manual=1` |
| Today strip | Four equal-height stat tiles: Patients seen · Visits recorded · ANC due today · Pending sync. Zero renders as "0" | `providerHomeProvider` | Patients tab filtered `?seen=today` · `/provider/visits/today` · Reminders tab · `/sync` |
| Needs attention | Up to 5 patients: name, age/sex, coloured chip (Danger / Caution / Overdue — icon + word, never colour alone), reason line, chevron; amber/red accent bar. Empty: calm green card "No danger signs flagged" with one line | `providerHomeProvider` | row → `/provider/patient/:id` |
| Due this week | Up to 5 undone ANC contacts due today through +7 days: name, "4th contact · BS date"; "See all" | `providerHomeProvider` | row → summary; See all → Reminders tab |
| Recent patients | Up to 5 chips (initial + name, wrapping): the last records opened on this phone, topped up from the cache by last change. In mock mode this is where Sita, Ram and Aarav appear before anyone has been opened | `sync_meta` `provider_recent_patients` + cached patients | chip → summary |
| Quick actions | Register pregnancy · New visit · Patients · Reminders. Four across; two-by-two once the font scale would force a mid-word break | — | the first two open a patient picker sheet (only patients this device may write to, and only women with no open pregnancy for the first); the other two switch tab |
| Footer | "Protocol v2026-09-18.1" in `textSecondary` | `rulesProvider` (the shipped `assets/rules.json`, or the server's if newer — already loaded at bootstrap, no new call) | — |

Pull-to-refresh invalidates `providerHomeProvider`, which re-subscribes every
Drift stream with the current time. It does **not** start a sync; the pill
does.

**Definitions.**

- *Patients seen today* — distinct patients with a visit or an ANC contact
  recorded today (local calendar day). Opening a record does not count.
- *Visits recorded today* — non-deleted visits whose `visit_at` falls on the
  local day.
- *ANC contacts due today / overdue / next 7 days* — undone contacts of
  **active** pregnancies, by `due_at`. A delivered pregnancy owes nothing, as
  on the health-post dashboard.
- *Needs attention* — one row per patient, most urgent first: red triage in
  the last 30 days, then amber, then an overdue contact. A woman who is both
  amber and overdue is one row (amber).
- *Pending sync* — every outbox row, rejected ones included, so the tile
  cannot read 0 beside a pill reading "Not synced".
- The reason line uses the rule table's English sentence, translated through
  `Rules.translateReason` under Nepali. The mock's pre-rules stand-ins
  (`bp_high`, `severe_anaemia`) are mapped to the real sentences; a bare code
  with no sentence falls back to the level headline.

### Reminders tab (`ProviderRemindersTab`)

New. Three sections from the same provider — *Due today*, *Contacts overdue*
(amber edge, "Overdue" chip), *Next 7 days* — each with its count, empty
sections omitted, an empty state with a Scan button when there is nothing.
Rows open the summary. Pull-to-refresh re-queries Drift.

### Patients tab (`ProviderHomeScreen`)

Unchanged list of open grants, plus a `seenTodayOnly` mode reached from the
Home tile: the list becomes everyone seen today (owned records included, since
"seen" is about the record, not the grant), under an `InputChip` whose cross
returns to the full list. Tapping the Patients tab in the bar always returns
to the unfiltered root. The empty state's button now pushes `/provider/scan`
(it used to switch to the Scan tab).

### Today's visits (`ProviderVisitsTodayScreen`, `/provider/visits/today`)

New. The list behind the "Visits recorded" tile: patient, time, complaint
label from the codelist, pending-sync dot, chevron to the summary.

### Coach marks

`CoachMark` gained an optional `target` (`GlobalKey`). When the target is
mounted and on screen the scrim is cut away around it (a circle for a round
target, a card shape otherwise) and the card sits directly above a target in
the lower half of the screen, or at the bottom otherwise, with the window
clipped so a tall list is not lit under the card. The overlay re-measures
after every frame while a targeted card is up, at no cost while the screen is
still. Marks without a target render exactly as before, so the patient tour
is unchanged. The provider tour keeps its flag (`coach_seen:provider`), so it
is still shown once — and a phone that saw the previous tour will not see this
one.

### Scanner

`ScanScreen` gained `openManualEntry` (route `/provider/scan?manual=1`): after
the first frame, if the scanner is online, it opens the same "Enter code
instead" dialog the button under the viewfinder opens, feeding the same
`_redeem`. Nothing else in the file changed.

## Files

**New**

| File | What |
|---|---|
| `lib/domain/rules/provider_home.dart` | `buildProviderHome` — one pure function over patients, pregnancies, contacts, visits: today's counts, owed contacts by bucket, needs-attention rows, recent patients; `firstReadableReason` |
| `lib/features/shell/provider_home_tab.dart` | The Home dashboard |
| `lib/features/shell/provider_reminders_tab.dart` | The Reminders tab |
| `lib/features/provider/provider_visits_today_screen.dart` | Visits recorded today |
| `lib/features/provider/patient_picker.dart` | The bottom-sheet patient picker for New visit / Register pregnancy |
| `lib/features/provider/provider_widgets.dart` | `ageSexLine`, `bsDateLabel`, `PatientAvatar`, `DueContactTile`, `RecentPatientRecorder` |
| `test/features/provider_home_test.dart` | 7 tests: empty state, footer, populated counts/rows/order, tile and card navigation, Nepali, no overflow at 1.3× on 360×780 in en and ne |
| `test/rules/provider_home_test.dart` | 12 tests for the pure function |

**Edited**

| File | Change |
|---|---|
| `lib/router.dart` | `providerShellRoute()` (a `StatefulShellRoute` with four branches, exported for the tests); `/provider/scan?manual=1`; `/provider/visits/today`; `/provider/patient/:id` wrapped in `RecentPatientRecorder` |
| `lib/features/shell/provider_shell.dart` | Rewritten: `ProviderShell(navigationShell)`, `ProviderTabs` path constants, `ProviderCoachTargets`, the notched bar and the docked button, `PopScope` back-to-Home, the targeted tour |
| `lib/features/shell/coach_marks.dart` | `CoachMark.target`; scrim painter with a window; card placement; frame-by-frame target tracking |
| `lib/features/provider/provider_home_screen.dart` | `seenTodayOnly`; empty-state button pushes the scanner; `ShellScope` no longer used |
| `lib/features/provider/scan_screen.dart` | `openManualEntry` constructor flag and its post-frame hook — the route in, nothing else |
| `lib/core/providers.dart` | `clockProvider`; `providerHomeProvider` (six Drift streams, `autoDispose`) |
| `lib/data/local/daos/visits_dao.dart` | `watchSince` |
| `lib/data/local/daos/sync_meta_dao.dart` | `recordPatientOpened`, `watchRecentPatientIds` (key `provider_recent_patients`, capped at 10; no schema change) |
| `lib/data/local/outbox.dart` | `watchUnsettledCount` |
| `lib/features/shell/shell_scaffold.dart`, `provider_more_tab.dart` | Doc comments only |
| `lib/core/l10n/app_en.arb`, `app_ne.arb` | 41 new keys in each (`navReminders`, `home*`, `providerSeenToday*`, `providerVisitsToday*`, `providerReminders*`, `coachScanButton*`, `coachAttention*`). No existing key removed or changed; `coachScanTitle/Body` and `coachPatientsTitle/Body` are now unused |
| `test/features/harness.dart` | `routerAppForTest`, `providerRouterForTest` (the real shell with every pushed screen — the camera above all — replaced by a self-naming stub) |
| `test/features/navigation_test.dart` | Provider group rewritten: five labelled destinations and the docked button; each tab's screen and Scan from every tab; back-to-Home and back-exits; the two-card targeted tour shown once |
| `test/features/layout_test.dart` | + Home tab, Reminders tab, Patients tab (seen today), Visits today — both sizes, both locales |

**Not touched:** anything under `lib/**/qr*`, the share sheet, `SWC1`/`SWC2`
encode/decode, the redeem and PIN-challenge paths, the mock, the sync engine,
`D:\mero_swasthya_api`, the patient shell and its tabs.

## Verification

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **708 passed**, up from 670. (As found, the working tree ran 532 + 5 files failing to compile, because `lib/core/l10n/gen` was stale against the uncommitted ARB edits; `flutter gen-l10n` alone brought it to 670 before any of this work.) |
| Layout at 360×780 and 412×915, `en` and `ne` | Home, Reminders, Patients (both modes), Visits today: no `RenderFlex overflowed` |
| Font scale 1.3 at 360×780, `en` and `ne`, whole page scrolled | No overflow (`provider_home_test.dart`) |
| Nepali strings | Greeting, section titles, chips, ordinal contact numbers, translated triage reason, BS digits asserted in `ne` |
| Release build `--split-per-abi --dart-define=MOCK_API=true` | Built: `app-arm64-v8a-release.apk` 34.0 MB, `app-armeabi-v7a-release.apk` 30.9 MB, `app-x86_64-release.apk` 36.3 MB. **Not installed** — no device attached |

### Device

`adb devices` listed **no device** at any point during this session — polled
at the start, mid-way and before finishing; `P21297002263` was not attached.
Per the brief the device leg was skipped: no install, no screenshots, no
logcat sweep. `docs/screens/provider_dashboard/` was not created.

When the phone is next attached:

```
adb -s P21297002263 install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

then: sign in as a health worker, screenshot Home in `en` and `ne`, tap the
centre button and screenshot the scanner, tap "Enter code instead" on the
Home card and confirm the dialog opens over a live camera, and watch
`adb logcat | grep -i overflow` while walking Home → Patients → Reminders →
More → back → back.

## Left

- **Device verification** (above).
- **Coach flag.** The provider tour reuses `coach_seen:provider`, so an
  install that dismissed the old two-card tour will not see the new one. A
  reinstall shows it.
- **Manual entry offline.** `/provider/scan?manual=1` only opens the dialog
  when the scanner is online, because the scanner screen itself shows a
  "needs internet" state offline and offers no manual path there. Offline
  `SWC2` entry by typing is therefore still not reachable — the same
  limitation the scanner has always had, deliberately left alone.
- **"Today" at midnight.** The dashboard binds "today" when its streams are
  subscribed; it is re-asked on pull-to-refresh and on returning to the Home
  or Reminders tab, not on the clock rolling over while the tab is open.
- **Follow-up visits** (`Visit.followUpAt`) are not on the Reminders tab; it
  is ANC contacts only, as specified.
- `coachScanTitle/Body`, `coachPatientsTitle/Body` remain in both ARBs unused.
