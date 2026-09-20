# Tier 2 — handoff

Flutter app **Mero Swasthya** (spec: "Swasthya Card"). Everything in spec §2.2's
Tier 2 list, built on top of the Tier 1 build described in
`docs/SESSION_2_HANDOFF.md`.

---

## 1. Status at a glance

| | |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **+435, all passing** (343 at the start of Tier 2) |
| Test suite run 5× in a row | **5 × 435, no flakes** |
| Release build | `flutter build apk --release --split-per-abi --dart-define=MOCK_API=true` — all three ABIs build |
| Demo APK | `build/MeroSwasthya-demo-tier2-arm64-v8a.apk` — **30.1 MB** (31,566,573 bytes) |
| Device | **POCO X3 Pro**, serial `483a08e5`, Android 13 (API 33), arm64-v8a |
| Contract | **unchanged** — no Part A field name, enum value, endpoint path or response shape was altered |

### A note on the device

`adb devices` listed exactly one phone for the whole of this work: the **POCO
X3 Pro**. The Nothing Phone from session 1 never appeared. The POCO's USB
connection dropped out three times mid-session and came back on its own each
time; if a run of `adb` reports no device, wait a minute and retry before
assuming anything is broken.

---

## 2. What was built, item by item

### T2-1 — Printed QR card with PIN (spec A.7)

S08 gains **"Printable card"** beneath "Share record (QR)". It creates a grant
with `{scope: "read", ttlMinutes: 525600}` and renders a card carrying the app
name, patient name, date of birth in **both** calendars, blood group, the QR of
the `SWC1:` payload, and — in Nepali *and* English on every copy — *"Ask the
patient for their 4-digit PIN"*. **Share / save image** rasterises a
`RepaintBoundary` at 3× and hands the PNG to `share_plus`.

Redeeming it is a challenge/response, which is the only shape that works against
a server that signs its own tokens: the app posts the payload, the server
answers `403 FORBIDDEN` with `details.pin = "required"`, the app asks for the
four digits on the same keypad S04 uses, and reposts with `pin`. A wrong PIN
comes back `details.pin = "invalid"` and the dialog says *"That PIN was not
accepted. Ask the patient again."*

A redeemed `read` grant sets a device-local flag, so **S21 opens under a
"Read-only access" banner with Add visit, Capture paper and Register pregnancy
removed** — removed rather than greyed, because a disabled button invites
tapping.

Screens: `tier2_03_printed_card`, `tier2_05_pin_challenge`, `tier2_06_pin_wrong`,
`tier2_07_readonly_s21`.

### T2-2 — Delivery record (S14, spec §11)

`/pregnancy/:id/delivery` already existed in skeleton. Added: a **time** picker
beside the BS date, and **complications chips** (eight codes, bilingual labels).
Save writes the `deliveries` row and the closed pregnancy in one transaction
with two outbox ops, delivery first.

S12 now replaces "Record delivery" with a **Delivered card** — date, place,
mode, outcome, baby weight and sex, complications as words. S06's badge changes
from *Pregnant · week 30* to **Delivered**. S08 keeps a link into the closed
pregnancy and re-offers "Register pregnancy".

Screens: `tier2_11_delivery_form`, `tier2_12_delivered_s12`,
`tier2_13_delivered_badge_s06`.

### T2-3 — AI draft summary (S10)

With `config.aiSummaryEnabled` true, the document detail shows **"Draft summary
(AI)"**. It POSTs `/documents/:id/summarize`, then polls `GET /documents/:id`
every 3 s until `aiSummaryStatus` is `done` or `failed`, giving up after 60 s
(twenty polls). The draft renders under a prominent amber **"AI-generated,
unverified — confirm with a health worker"** label carried in both languages
regardless of the app's locale. `failed` and `timedOut` both offer a retry. Every
document the run sees is cached locally, so a summary survives losing signal.

Screens: `tier2_08_ai_queued`, `tier2_09_ai_done`, `tier2_10_ai_medicines`.

### T2-4 — Nearest facility map

`/facilities` renders `flutter_map` over OpenStreetMap tiles when online, with
markers from the **local database** (seeded from `assets/facilities.json`) that
are drawn whether or not there is a network. The camera fits all markers. Below
the map is a **distance-sorted list** — name, type, distance, **Call**.

Offline the tile layer is dropped and an amber note says *"Map tiles need
internet — the facilities are still shown"*. **The screen is never blank.**

S13's red/amber referral card and S12's birth plan both now rank facilities
nearest-first with the distance in the label, and both gained a **Show on
map** / **Choose on map** entry point that returns the chosen facility. S13's
existing Call button is untouched (§17 item 5 depends on it).

Screens: `tier2_14_map_online`, `tier2_15_map_offline`, `tier2_final_03_anc_red`.

### T2-5 — Medicine reminders with Nepali audio

**"Set reminders"** sits under a visit's prescriptions, in the patient's own
timeline *and* on S21. It requests `POST_NOTIFICATIONS`, then schedules the next
seven days: OD 08:00; BD 08:00/20:00; TDS 08:00/14:00/20:00; QID
06:00/12:00/18:00/22:00; HS 21:00; **SOS nothing**. The drug name is the title
and the Nepali instruction is the body. Tapping a notification opens that
patient's timeline, including when the notification launched the app from cold.

Each prescription row has a **speaker** button that reads the drug name and
`instructionsNp` aloud through `flutter_tts` at `ne-NP`. With no Nepali voice it
falls back to `en-IN` and says so in one line; with no engine at all it says that
instead. It does not crash either way.

Verified for real: Settings → **Test a medicine reminder** schedules one 30 s
ahead, and it fired — *"Metformin 500 mg / खाना पछि"*
(`tier2_16_notification`). `dumpsys alarm` showed 13 alarms for a BD
prescription started mid-afternoon, matching the schedule generator exactly.

Screens: `tier2_16_notification`, `tier2_17_speak_reminders`,
`tier2_18_reminders_set`.

### T2-6 — Health-post dashboard

`/provider/dashboard`, reached from the chart icon on S19. Six tiles over
everything cached on this device: pregnancies by trimester (WHO boundaries: <14,
14–27, ≥28), **contacts overdue**, **red or amber in the last 7 days**,
**deliveries this month** (bounded by the *Bikram Sambat* month, because that is
what a health post reports on). Every tile opens the list of women behind it, and
every row opens the record.

Screens: `tier2_19_dashboard`, `tier2_20_dashboard_overdue`.

### T2-7 — Regression and packaging

See §6.

### T2-8 — Docs

`docs/DEMO_SCRIPT.md` gained an optional 60-second Tier 2 segment and three
pre-demo checklist items. This file is the rest.

---

## 3. Packages added

| Package | Version | Why |
|---|---|---|
| `flutter_local_notifications` | 22.3.1 | T2-5 medicine reminders |
| `flutter_tts` | 4.2.5 | T2-5 Nepali audio |
| `flutter_map` | 8.3.2 | T2-4 map |
| `latlong2` | 0.10.1 | T2-4 coordinates |
| `share_plus` | 13.3.0 | T2-1 card PNG |
| `timezone` | 0.11.1 | **Not a sixth feature package.** `zonedSchedule` takes a `TZDateTime`, so it is part of `flutter_local_notifications`' API surface. It was already in the lockfile transitively; it is now a direct dependency because the analyzer is right to insist. |

All five requested packages resolved on the first attempt. `drift` stays pinned
at `">=2.20.0 <2.35.0"` and Riverpod 2 syntax is unchanged throughout.

---

## 4. Manifest, Gradle and permission changes

**`android/app/build.gradle.kts`**

```kotlin
compileOptions { isCoreLibraryDesugaringEnabled = true }
dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5") }
```

Required by `flutter_local_notifications`, which uses `java.time`; `minSdk` is
24 and `java.time` arrived in 26. Without it the release build fails outright
with `Dependency ':flutter_local_notifications' requires core library
desugaring`.

**`AndroidManifest.xml`** — four permissions and two receivers:

| Added | Why |
|---|---|
| `POST_NOTIFICATIONS` | Android 13+ runtime permission; without it reminders are silently dropped |
| `SCHEDULE_EXACT_ALARM` | "take it at eight" is the instruction. The code falls back to an inexact alarm if the phone refuses |
| `RECEIVE_BOOT_COMPLETED` | a reminder should survive a restart |
| `VIBRATE` | so a reminder is noticed |
| `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` | the plugin's own receivers |

**No location permission was added.** `ACCESS_COARSE_LOCATION` is deliberately
*not* in the manifest: the map centres on the patient's municipality from
`assets/facilities.json` instead of asking the device where it is. Adding a
location prompt to show four health posts in one district would have been a poor
trade, and the instruction was to add it *only if* device location was used.
**If a future build wants a real "you are here" marker, that permission and a
location package both have to be added.**

---

## 5. New mock behaviour the real backend must match

Everything below is in `lib/core/net/mock_api.dart`. The first three are
contract behaviour the backend has to implement; the last two are demo data that
is **mock-only** and needs no server equivalent.

1. **Long-lived grants and the PIN gate (A.7).** `POST /grants` with
   `ttlMinutes >= 1440` marks the grant `longLived: true`. Redeeming such a
   grant without `pin` must answer **403 `FORBIDDEN` with
   `details.pin = "required"`**; with a wrong `pin`, **403 `FORBIDDEN` with
   `details.pin = "invalid"`**. No new error code was added to the A.3 table —
   `details` is the documented place for this.
   `AccessGrant` gained one additive optional field, **`longLived`** (default
   `false`). A server that never sends it behaves exactly as before.
2. **Summarize status flow.** `POST /documents/:id/summarize` answers
   `aiSummaryStatus: "queued"` immediately and bumps `version`. A later
   `GET /documents/:id` flips it to `done` with the text in `aiSummary`. The app
   polls every 3 s and gives up after 60 s, so the backend must reach a terminal
   state (`done` or `failed`) inside that window or the app shows a retry.
3. **`GET /patients` is the family list, not the visible set.** The mock now
   filters to `ownerUserId == me`. Before Tier 2 both seeded patients happened to
   be owned by the demo account so the bug was invisible; with granted patients
   in the seed it put other people's households on S06. Granted patients must
   reach the device through `/sync/pull` only.
4. *(Mock-only)* **Three extra seeded women** — Gita Tharu (week 10), Maya B.K.
   (week 37, six contacts already done), Parbati Chaudhary (week 22, contact 2
   overdue, contact 1 amber) — each reachable through an already-redeemed grant,
   so the dashboard tiles are non-zero. A real backend needs none of this: the
   tiles fill up as the health post scans people.
5. *(Mock-only)* **A seeded discharge document** for Ram, "Bharatpur Hospital
   discharge sheet", which is what the AI-summary demo runs against.

**One trap worth naming.** Seeded rows carry `updatedAt: _touch()` — i.e. *now* —
not a date in the past. `updatedAt` is the pull cursor, and a phone that has
synced before is already past any past timestamp, so a row seeded backwards never
arrives on an existing install. This cost real debugging time when the discharge
sheet refused to appear; the same applies to anything else added to the seed
later.

---

## 6. Regression — spec §17, re-run on the phone

Re-run end to end after a `pm clear`, on the shipped Tier 2 APK.

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Rules unit tests: all 16 cases in A.6 | **PASS** | `flutter test`, 5× |
| 2 | Fresh install → OTP → PIN → family member visible | **PASS** | `tier2_final_01_fresh`, `tier2_final_02_family_fresh` |
| 3 | Airplane mode → record → pending icon → online → synced | **PASS** | `tier2_final_04_offline`, `..._05_pending`, `..._06_synced` |
| 4 | QR generate → redeem → allergies and pregnancy; no PIN on an ordinary grant | **PASS** | `tier2_final_07_qr_redeem` |
| 5 | ANC BP 150/95 + severe headache → red + referral + call | **PASS** | `tier2_final_03_anc_red` |
| 6 | Document capture → thumbnail → uploaded | **BLOCKED** — MIUI system camera crashes on this phone. Unchanged from session 2; passed on the Nothing Phone then | — |
| 7 | Timeline in correct BS-month groups | **PASS** | Bhadra / Shrawan groups on Ram's timeline |
| 8 | Audit shows the provider's redeem | **PASS (redeem)** — a visit arriving via `/sync/push` still writes no audit entry in the mock. Unchanged from session 2; **the backend should audit pushed writes** | — |
| 9 | Language toggle switches every visible string | **PASS**, including all 60 new Tier 2 strings | `tier2_final_08_nepali` |
| 10 | Release APK installs; scanner works in release | **PASS** | `tier2_final_09_apk_unlock`, `tier2_final_10_apk_data_intact` |

**No item regressed.** Items 6 and 8 carry forward from session 2 unchanged.

The two highest-risk regressions were checked explicitly:

- **The read-only gating does not leak.** An ordinary ten-minute `append` grant
  redeems with **no PIN prompt** and S21 shows Add visit and Capture paper
  (`tier2_final_07_qr_redeem`). There is also a test for it.
- **The S13 referral card still works.** Red banner, both A.6 case-3 reasons,
  referral card, red Call — plus the new distance and map link.

---

## 7. Defects found and fixed during Tier 2

**D9 — the S12 "Delivered" card was unreadable in dark mode.** The card set an
explicit light-green background and let the body text inherit the theme's
foreground, so it came out light-on-light. Found on the phone. It now uses the
ordinary card surface and lets the green tick and heading carry the meaning.

**D10 — baby weight was stored as `3.4000000000000004`.** The stepper adds 0.1 at
a time and binary floating point does the rest; the delivery card rendered the
raw double. Rounded at the write and formatted at the read, with a test for both.

**D11 — a delivered pregnancy became unreachable.** S08 showed the pregnancy card
only while the pregnancy was `active`, so recording a delivery made the delivery
record reachable from nowhere at all. S08 now watches the *latest* pregnancy and
shows a "Delivered" tile that opens the closed dashboard. Test added.

**D12 — "13 reminders set" was invisible.** `PrescriptionActions` also lives
inside the visit sheet on the timeline, and a `SnackBar` raised from inside a
modal bottom sheet is painted by the *page's* `Scaffold` — underneath the sheet.
The confirmation is now inline, which is better anyway: it is still on screen a
minute later, which is when somebody thinks to check.

**D13 — the red triage banner's reasons were grey on pale red.** Pre-existing
Tier 1 defect, not introduced here, but it is the app's most important banner and
it names the rule that sends somebody to hospital. The reason lines now carry the
banner's own colour. Pinned by a test.

**D14 — `GET /patients` returned every visible patient.** See §5.3.

---

## 8. Known issues

Carried forward from session 2 and still true:

1. **No QR has ever been read optically.** Every redeem in Tier 2 went through
   the manual-code fallback. Rehearse once before the demo.
2. **MIUI's system camera crashes on the POCO X3 Pro**, so document capture
   cannot be exercised there.
3. **A revoked grant is reported as expired** (`GRANT_EXPIRED` for both).
4. **A visit arriving via `/sync/push` writes no audit entry.**
5. **"Last vitals" on S21 reads only the latest `Visit`**, never an ANC contact.
6. **The local database is unencrypted** — the §6.1 fallback.
7. **Rotation is not pinned in the manifest.**

New with Tier 2:

8. **The Nepali TTS voice was never confirmed audible.** `isLanguageAvailable('ne-NP')`
   returned true on this phone and `speak` did not throw or show the fallback
   note, so the code path is right — but **nobody has listened to it**. This
   needs one human with working ears before the demo.
9. **Map tiles are not cached.** Offline shows markers over a plain background by
   design; there is no stale basemap. A tile cache is a lot of somebody's phone
   storage to spend without asking.
10. **The map has no "you are here" marker** — it centres on the patient's
    municipality. See §4 for why.
11. **The dashboard counts only what is on this phone.** Stated on the screen
    ("Counted from the records on this phone only"). That is the honest scope for
    a local aggregate, but it is not a district report.
12. **`Asia/Kathmandu` is hard-coded** as the notification time zone. Correct for
    every phone this will run on, wrong for a test device set elsewhere.
13. **Complication codes are app-local constants**, not a `CodeListKind`. A.2
    types `complications` as free-text `string[]`, and adding a codelist kind
    would have changed a Part A enum. If the backend grows a `complication`
    codelist it can adopt these eight codes unchanged.
14. **Three screen tests skip `db.close()` in their tear-down.** S12's bundle is a
    `combineLatest4` over four Drift streams, and closing the database while
    their cancellation is still in flight wedges the fake-async zone the test
    runs in. The databases are in memory and die with the test; the comment in
    the test says so.

---

## 9. Files changed

### New application code

| File | What |
|---|---|
| `lib/domain/rules/geo.dart` | Haversine, distance sorting, map centre, distance formatting |
| `lib/domain/rules/medicine_schedule.dart` | dose times per frequency, 7-day horizon, notification ids |
| `lib/domain/rules/provider_dashboard.dart` | the dashboard aggregation |
| `lib/domain/rules/delivery_complications.dart` | the eight complication codes |
| `lib/features/patient_home/printed_card_screen.dart` | A.7 printed card + share |
| `lib/features/provider/pin_challenge_dialog.dart` | the four-digit challenge |
| `lib/features/provider/provider_dashboard_screen.dart` | tiles and the filtered lists |
| `lib/features/facilities/facility_map_screen.dart` | the map |
| `lib/features/documents/ai_summary.dart` | the polling state machine |
| `lib/features/documents/ai_summary_widgets.dart` | the section and the unverified label |
| `lib/features/reminders/medicine_notifications.dart` | the plugin wrapper |
| `lib/features/reminders/medicine_speech.dart` | `flutter_tts` with the en-IN fallback |
| `lib/features/reminders/prescription_actions.dart` | "Set reminders" and "Speak" |

### Modified application code

`lib/core/net/mock_api.dart` (long-lived grants + PIN, summarize flow, seeded
discharge doc, three seeded women, `GET /patients` scoping),
`lib/core/providers.dart` (read-only access, latest pregnancy, dashboard,
notifications, speech), `lib/core/dates/bs_date.dart` (`currentBsMonth`),
`lib/core/l10n/app_en.arb` + `app_ne.arb` (60 new keys) and the regenerated
`gen/`, `lib/domain/models/models.dart` (`AccessGrant.longLived`),
`lib/data/remote/api/grants_api.dart` (`pin`, `isPinChallenge`,
`isPinRejected`), `lib/data/local/daos/sync_meta_dao.dart` (read-only access),
`lib/data/local/daos/patients_dao.dart` (`watchCachedForProvider`),
`lib/data/local/daos/pregnancies_dao.dart` (`watchLatestForPatient`,
whole-device reads), `lib/data/repositories/pregnancy_repo.dart`,
`lib/router.dart` (four new routes), `lib/features/splash/splash_screen.dart`
(notification init and cold-start routing),
`lib/features/patient_home/patient_home_screen.dart` (printable card, delivered
tile), `lib/features/provider/scan_screen.dart` (PIN challenge),
`lib/features/provider/provider_patient_screen.dart` (read-only gating,
prescription actions), `lib/features/provider/provider_home_screen.dart`
(dashboard entry), `lib/features/maternal/delivery_screen.dart` (time,
complications), `lib/features/maternal/pregnancy_dashboard_screen.dart`
(delivered card, map link), `lib/features/maternal/anc_contact_screen.dart`
(distance ranking, map link), `lib/features/family/family_screen.dart`
(delivered badge), `lib/features/timeline/timeline_screen.dart` (prescription
actions, sheet `Scaffold`), `lib/features/documents/document_detail_screen.dart`
(AI section), `lib/features/shared/widgets/app_widgets.dart` (`ReadOnlyBanner`,
triage reason colour).

### Build

`pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`,
`android/app/src/main/AndroidManifest.xml`.

### Tests (343 → 435)

New: `test/rules/geo_test.dart` (18), `test/rules/medicine_schedule_test.dart`
(19), `test/rules/provider_dashboard_test.dart` (15),
`test/features/printed_card_test.dart` (11), `test/features/delivery_test.dart`
(12), `test/features/ai_summary_test.dart` (17),
`test/net/dashboard_seed_test.dart` (1), `test/features/harness.dart` (shared
helpers).
Modified: `test/net/mock_api_test.dart`, `test/sync/first_pull_test.dart`,
`test/features/widgets_test.dart`.

### Docs and artefacts

`docs/DEMO_SCRIPT.md`, `docs/TIER2_HANDOFF.md` (this file),
`docs/screens/tier2_*.png` (20), `docs/screens/tier2_final_*.png` (10),
`build/MeroSwasthya-demo-tier2-arm64-v8a.apk`.

---

## 10. Summary

**What passed.** All seven build items are done and were verified on the phone,
not only in tests: the printed card produces a real PNG and its PIN gate refuses
a wrong PIN and opens a genuinely read-only S21; the delivery record closes a
pregnancy and changes both S12 and S06; the AI summary polls and renders a
bilingual draft under a bilingual warning; the map draws OpenStreetMap tiles
online and keeps its markers, distances and Call buttons offline; a real medicine
reminder fired on the lock screen with the Nepali instruction in its body, with
`dumpsys alarm` confirming the schedule; and the health-post dashboard counts a
seeded caseload correctly and opens the women behind every tile. The analyzer is
clean, the suite is 435 green and survived five consecutive runs, the release
build produces all three ABIs, and the shipped 30.1 MB arm64 APK installs and
opens to PIN unlock with data intact. Every spec §17 acceptance item was re-run
after a wipe and none regressed. No Part A field name, enum value, endpoint path
or response shape changed; the one model addition, `AccessGrant.longLived`, is
optional and additive.

**What failed.** Nothing was abandoned, but two §17 items remain in the state
session 2 left them: document capture is still blocked by MIUI's own camera
crash on the only phone available, and a visit arriving through `/sync/push`
still writes no audit entry, which is a backend gap rather than an app one. Six
defects were found and fixed along the way (§7), four of them only visible on a
real screen in dark mode — which is the argument for having run this on hardware
rather than in a simulator.

**What needs a human.** Three things, all short. Somebody has to **listen** to
the Nepali text-to-speech: the code path is right and the fallback works, but no
ear has confirmed the voice. Somebody has to **read one QR through the lens**,
still the only step never exercised optically. And somebody has to decide the
open questions from session 2 that Tier 2 did not touch — whether "Last vitals"
should fall back to an ANC contact, whether a revoked grant deserves its own
error code, and whether the backend audits pushed writes.
