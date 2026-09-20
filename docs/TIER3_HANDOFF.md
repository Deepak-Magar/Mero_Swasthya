# Tier 3 — handoff

Flutter app **Mero Swasthya** (spec: "Swasthya Card"). Everything in spec §2.2's
Tier 3 roadmap row — child immunisation module, fine-grained consent, voice
notes, PDF export — plus honest integration placeholders, built on the Tier 2
build described in `docs/TIER2_HANDOFF.md`.

---

## 1. Status at a glance

| | |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **+533, all passing** (435 at the start of Tier 3) |
| Suite run 5× in a loop | 4 green, **1 unreproduced single-test failure** — see §7 |
| Release build | `--release --split-per-abi --dart-define=MOCK_API=true` — all three ABIs |
| Demo APK | `build/MeroSwasthya-demo-tier3-arm64-v8a.apk` — **32.2 MB** (33,751,747 bytes) — rebuilt after the fIPV correction, D2b and the WHO growth band |
| Device | **POCO X3 Pro**, serial `483a08e5`, Android 13, arm64-v8a |
| Contract | **Part A unchanged.** Every addition is additive and written up in `docs/CONTRACT_ADDENDUM.md` |

---

## 2. What was built, item by item

### T3-1 — Child health: immunisation and growth

Two new syncable tables, `immunisations` and `growth_measurements`, both
additive (full shapes in the addendum, §1–3). A drift migration takes the local
schema from 1 to 2 by **creating two tables and touching nothing else**, so a
phone that already held a demo record kept every row it had.

The schedule is a **pure function of the child's date of birth** with
deterministic uuid v5 ids in the same style as A.8.15's ANC contacts — the whole
point being that a child registered offline does not end up with two of every
vaccine when the server's own schedule arrives. It comes from
`assets/epi_schedule.json` — BCG at birth; OPV/PENTA 6-10-14 wk; PCV 6-10 wk +
9 mo; Rota 6-10 wk; **fIPV 14 wk + 9 mo**; MR 9 + 15 mo; JE 12 mo; TCV 15 mo.
Eighteen doses across exactly seven visits. **Cross-checked on 2026-09-19 —
see §7a, which found and fixed one real error.**

`/patient/:id/child` shows the card: one row per dose, green given / amber due /
**red with an outline** overdue / grey upcoming, in BS and AD, with bilingual
vaccine names. A dose opens a sheet with a date and a batch number, and a
"Not given after all" undo, because a dose recorded against the wrong child is a
thing that happens. Below it, a `fl_chart` weight-for-age chart plots the
child's measurements over the **WHO Child Growth Standards** median and ±2 SD
band, birth to five years, named on screen. It shipped with a hand-fitted
illustrative curve; §7b is what happened when that was checked.

S08 gains a **Child health** card for under-fives showing the overdue count in
red — a count, not a chevron, because "Overdue: 2" is a reason to open it.

Timeline gained the kinds `immunisation` and `growth`; only doses **actually
given** appear, because a schedule is a plan and the timeline is history.

Screens: `tier3_01`–`tier3_04`.

### T3-2 — Fine-grained consent on QR grants

`POST /grants` takes an optional `sections` array from `summary, visits,
documents, pregnancy, child, audit`. Omitted or empty means the whole record —
what every grant meant before this existed — and the app omits the key entirely
in that case, so a backend that has not implemented it never sees it.

S08's share sheet gained a **"What to share"** chip row with an "Everything"
reset. Changing it regenerates the QR, because the token carries the consent and
the code on screen must always be the one that will be read. The last choice is
remembered per patient in shared preferences.

**The mock filters the bundle server-side**, and that is the point: consent a
client enforces is not consent. Two rules the addendum spells out and the tests
pin — the **patient row always travels** (so `allergies` is never hidden by a
consent choice), and a withheld summary is sent **empty, not null**, so the
required shape of A.4's envelope never changes.

S21 hides the sections it was not granted and prints **"Patient shared:
Pregnancy"** so a provider looking at a short screen knows they are seeing a
choice rather than an empty record.

Screens: `tier3_05`–`tier3_07`.

### T3-3 — Voice notes in Nepali

A microphone on S22's notes field and on a **new optional notes field on S13**,
stored as `findings.notesText` — inside `findings` on purpose, because
`AncContact` is pinned by Part A and `findings` is already free-form JSON.

`speech_to_text` at `ne_NP`, falling back to `en_IN` with a one-line note, and
**hiding the button entirely** when the device has no recogniser at all. The
locale decision is a pure function (`speech_locale.dart`) and is the only part
worth testing; it matches the device's own spelling of the locale id, because
some engines reject an id they did not advertise.

The transcript is **appended and left editable**. Nothing is saved that the
person dictating has not had a chance to read — a recogniser mishearing a drug
name is a certainty.

Screens: `tier3_11`.

### T3-4 — PDF export

S08 gains **Export PDF**. The document carries the app name, the patient's
identity with dates in both calendars, **allergies boxed in red at the top**,
active problems, current medicines with their Nepali instructions, the active
pregnancy with all eight contacts and their triage, the child's immunisation
status if there is one, the last 20 timeline entries, and a footer
*"Generated by Mero Swasthya on &lt;BS date&gt;"*.

Built **entirely from the local database** — a record the patient can print has
to be printable in a room with no signal. Handed to `printing`'s share sheet,
which on Android reaches a Bluetooth printer, Drive, WhatsApp or a viewer.

Screens: `tier3_09`, `tier3_final_03`.

### T3-5 — Integration placeholders

A Settings **Integrations** section with three rows — National ID verification,
HMIS/DHIS2 export, Provider council verification. Each shows **"Not connected —
requires government API access"**, a paragraph in Nepali *and* English saying
what it would do, what it needs, and **what the app does instead in the
meantime**, and a disabled Connect button.

**No mock success states anywhere.** A green tick for "National ID verified"
would be a lie told to the one audience — a ministry evaluator — most likely to
check it. Three new `GET /config` flags (`nidEnabled`, `hmisExportEnabled`,
`councilVerifyEnabled`, all false) exist so the rows can light up later with no
app change.

Screens: `tier3_08`.

### T3-6 / T3-7 — Regression, packaging, docs

See §6 and §9.

---

## 3. Packages and fonts added

| Package | Version | Why |
|---|---|---|
| `speech_to_text` | 7.4.0 | T3-3 dictation |
| `pdf` | 3.12.0 | T3-4 document builder |
| `printing` | 5.14.3 | T3-4 share/print sheet |
| `fl_chart` | 1.2.0 | T3-1 growth chart |
| `path_provider` | 2.1.6 | already present from Tier 2 |

All four new packages resolved first time. `drift` stays pinned at
`">=2.20.0 <2.35.0"`; Riverpod 2 syntax throughout.

### Fonts

`assets/fonts/NotoSansDevanagari-{Regular,Bold}.ttf` (243 kB and 250 kB),
registered under `fonts:` in `pubspec.yaml`.

**They are not in `google/fonts`.** That repository now ships only the variable
`NotoSansDevanagari[wdth,wght].ttf`, which has no static Bold instance. The
static faces came from
`notofonts/notofonts.github.io/fonts/NotoSansDevanagari/hinted/ttf/`.

**And they are a fallback, not the base font** — see D3 in §7. They are the
*script-only* Noto build: 128 Devanagari codepoints, all ten digits, and
**zero Latin letters**, verified by reading the format-12 cmap directly.

---

## 4. Permissions and manifest changes

| Added | Why |
|---|---|
| `RECORD_AUDIO` | T3-3 dictation; asked for at runtime on first tap |
| `<queries><intent android:name="android.speech.RecognitionService">` | so `speech_to_text` can resolve the on-device recogniser |

Nothing else. No new Gradle changes beyond Tier 2's core-library desugaring.

**Still no location permission** — the facility map continues to centre on the
patient's municipality rather than asking the device where it is.

---

## 5. Local schema migration

`schemaVersion` 1 → 2. `onUpgrade` creates `immunisations` and
`growth_measurements` and does nothing else. **Verified on the phone**: the
existing install kept Sita's pregnancy, Ram's visit and every Tier 2 row through
the upgrade, and Aarav arrived on the next sync pull.

---

## 6. Regression — spec §17 and the Tier 2 checks

Re-run on the shipped Tier 3 APK, on the existing install (i.e. across the
schema migration, which is the harder case).

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Rules unit tests: all 16 A.6 cases | **PASS** | `flutter test`, ×5 |
| 2 | Install → PIN unlock → family visible | **PASS** | `tier3_final_01`, `tier3_final_02` |
| 3 | Airplane mode → pending → synced | **PASS** (Tier 2 run; sync engine unchanged except two additive tables, covered by tests) | — |
| 4 | QR generate → redeem → allergies and pregnancy | **PASS** | `tier3_07` |
| 5 | ANC red + referral + call | **PASS** | S13 renders, triage banner and referral card intact; `tier3_11` shows the screen with the new Notes block in place |
| 6 | Document capture | **BLOCKED** — MIUI system camera still crashes on this phone. Unchanged since session 2 | — |
| 7 | Timeline in BS-month groups | **PASS** | visible in the exported PDF's history table |
| 8 | Audit shows the provider's redeem | **PASS (redeem)**; a pushed visit still writes no audit entry — backend gap, unchanged | — |
| 9 | Language toggle switches every visible string | **PASS**, including all 60 new Tier 3 strings | `tier3_final_04` |
| 10 | Release APK installs; opens to PIN unlock, data intact | **PASS** | `tier3_final_01`, `tier3_final_02` |
| 11 | The **repackaged** APK carries the fIPV correction and D2b | **PASS** — reinstalled over the existing data, fIPV 1 at 2080 Kartik 5 with OPV3/Penta3, fIPV 2 at 2081 Baishakh 4 with MR1/PCV3, growth axis reading 0/4/8/12/16/20 | `tier3_final_05` |
| 12 | The WHO band draws across the whole axis, in both languages | **PASS** — band runs the full 0–42 months rather than stopping at 24, axes read 0/4/…/24 and 0/6/…/42, caption names the standard; the Nepali caption wraps to two lines without clipping | `tier3_14`, `tier3_15` |

**Tier 2 checks re-run:** printed card + PIN (`tier3_05` uses the same share
sheet), health-post dashboard, facility map, medicine reminders — all reachable
and unchanged. The consent work touched S21, which is the screen Tier 2's
read-only banner lives on; both now render together correctly.

**Devanagari in the release build's PDF — verified end to end.** The PDF the
**release APK itself** generated was copied to Downloads via the share sheet,
pulled off the phone with `adb pull`, and rasterised locally with `pypdfium2`:
`tier3_final_03_pdf_release.png` is that render. Bold Latin headings, Devanagari
labels, BS dates and the timeline table all correct.

**Nothing regressed.** Items 6 and 8 carry forward from earlier sessions.

---

## 7b. The growth band was illustrative, and it was badly wrong

The chart shipped with a hand-fitted curve and a label saying it was not the WHO
standards. It has now been **replaced by the WHO Child Growth Standards
themselves** — weight-for-age z-scores, birth to five years, both sexes, parsed
by machine out of WHO's own simplified field tables. The tables and the parser
are kept in `docs/reference/` so anyone can repeat the transcription.

The label was doing more work than anybody realised. Against the real standard
the illustrative curve was out by up to **1.7 kg**:

| | Illustrative | WHO |
|---|---|---|
| Boys, 12 months, median | 11.00 kg | **9.6 kg** |
| Boys, 12 months, −2 SD | 8.92 kg | **7.7 kg** |
| Girls, 12 months, median | 10.58 kg | **8.9 kg** |
| Girls, 12 months, −2 SD | 8.50 kg | **7.0 kg** |

**Both kinds of wrong, in the same curve.** From 1 to about 21 months the fake
−2 SD line sat *above* the real one, so a perfectly healthy one-year-old boy of
8.0 kg — comfortably above WHO's 7.7 kg − 2 SD — would have been drawn below the
line and looked severely underweight. From 22 months on it sat *below*, so a
genuinely underweight two-year-old could have looked fine. A curve that is
simply shifted is one thing; this one crossed over, which is why eyeballing it
never caught anything.

**It now runs to five years, not two.** The old band stopped at 24 months, which
is why Aarav — three years old, the demo child — had three measurements plotted
over nothing at all. WHO's tables run to 60 months and so does the asset.

**Two axis changes came with it**, and both are about the chart staying
readable rather than about the data:

- `growthXMax` now follows the **child** instead of the reference. An axis that
  always ran to 60 months would squeeze an infant's first year into a fifth of
  the card, so it ends a tick past the last measurement with a two-year floor.
  It no longer takes the reference at all.
- `growthYRange` takes `upToMonths` and ignores band rows past the right-hand
  edge. Without it, a six-month-old's chart would be scaled to the 24.9 kg a
  five-year-old can reach — a correct table producing a useless chart.

**What pins it.** Four anchor months per sex (birth, 12, 24 and 60 months) are
asserted against the values printed on WHO's own charts, so a transcription that
grabbed the wrong column fails rather than merely looking plausible — which is
exactly what the curve it replaced did. Alongside them: 61 rows per sex with no
gaps, z-score columns in order, weight monotonic in age, and boys heavier than
girls at every month after birth, which is the check that catches the same table
being shipped twice under two names.

**What this is still not.** It is weight-for-age, which cannot separate a short
child from a wasted one; height-for-age and weight-for-height are not in the
app. The screen says so in both languages instead of claiming more than a single
curve can carry. The `−3 SD` column — the severely-underweight line — is carried
in the asset but not drawn.

Screens: `tier3_14_who_growth_band.png`, `tier3_15_who_growth_nepali.png`.

---

## 7a. The EPI schedule was cross-checked, and was wrong

The schedule shipped with a warning saying it had never been checked. It has now
been checked — against three independent published summaries of Nepal's national
immunisation schedule, compared row by row on **2026-09-19**. All three agreed
with each other.

**It found one real error.**

| | Was | Now |
|---|---|---|
| fIPV dose 1 | 6 weeks | **14 weeks** |
| fIPV dose 2 | 14 weeks | **9 months** |

Nepal introduced a single full IPV dose at 14 weeks in 2014 and later replaced
it with **two fractional intradermal doses at 14 weeks and 9 months**. The app
was recalling children for their first fIPV eight weeks early, and had no second
dose at the 9-month visit at all.

Everything else was confirmed unchanged: BCG at birth; OPV and Pentavalent at
6/10/14 weeks; PCV at 6/10 weeks + 9 months; Rotavirus at 6/10 weeks; MR at
9 + 15 months; JE at 12 months; TCV at 15 months. JE was separately confirmed as
**nationwide in routine immunisation since July 2016** — not endemic-districts-only
as when it was introduced in 2009 — so a single universal dose is right.

**The structural check that should have caught it sooner.** The sources state
that a fully immunised child needs seven contacts: birth, 6, 10, 14 weeks, 9, 12
and 15 months. The corrected schedule produces exactly those seven and no
others, and the 9-month visit now carries three antigens (PCV3, MR1, fIPV2)
rather than two. Both are now tests.

**Why it survived this long.** The mock kept a second hand-typed copy of the
rows so a unit test could run without an asset bundle — and both copies were
wrong in the same way, so nothing ever disagreed. There is now a test that
generates the schedule from the shipped asset and compares it against what the
mock actually seeds. It was **confirmed to fail** when the two are made to
differ, not merely assumed to.

**What this is not.** It is not a check against the official Ministry of Health
and Population / Family Welfare Division publication, and it is not a clinical
sign-off. The asset's `verification` block records the date, the method, the
sources, the correction and the remaining gaps; the screen now reads *"Schedule
checked against published sources on 19 Sep 2026, not against the official
Ministry list"*, and the PDF says the same. **Somebody with the official
schedule still has to confirm every row.**

Three gaps the check surfaced and did not close:

- **HPV** for adolescent girls (school grades 6-10, and out-of-school girls aged
  10) is part of the national programme but sits outside this module, which
  stops at five years.
- **Td for pregnant women** is part of EPI and is handled separately in the ANC
  contact form.
- A **JE vaccine supply shortage** was reported in Nepal during 2025. That is a
  supply problem rather than a schedule change, but it means a due date this app
  shows may not be a dose a health post can actually give.

Screens: `tier3_12_schedule_corrected.png` — fIPV dose 1 now sits with OPV3 and
Pentavalent 3 at the 14-week visit, and fIPV dose 2 with MR1 and PCV3 at the
9-month visit.

---

## 7. Defects found and fixed during Tier 3

**D1 — the growth chart's y axis printed "16" twice.** `growthYRange` returned a
fractional bound, and `fl_chart` then labelled both the axis end and the nearest
interval tick. Found on the phone. Bounds are snapped to whole kilograms, pinned
by a test.

**D2 — the growth chart's x axis read "367".** With a measurement past the end
of the 24-month band the axis ended at 36.7, whose label was drawn on top of the
36 tick and ran together. `growthXMax` now rounds up to a whole tick.

**D2b — and then the y axis read "17" against "16".** D1's fix snapped the
bounds to whole kilograms, which was not enough: `fl_chart` labels the axis
bound *as well as* every interval tick, so any bound that is not itself a tick
prints two numbers on top of each other. Found on the phone a second time.
`growthYRange` now snaps to the tick interval, and the test asserts
`range.min % 4 == 0` rather than merely that it is an integer. The lesson is the
same one D3 taught: a rendering bug is fixed when you look at the render again,
not when the arithmetic starts to look right.

**D3 — every English word in the PDF was a black box.** The shipped Noto Sans
Devanagari is the *script-only* build: verified by reading its format-12 cmap,
it contains 128 Devanagari codepoints, all ten digits and **zero Latin
letters**. Used as the base font it rendered "Mero Swasthya", every table header
and every name as tofu. The base is now the `pdf` package's built-in Helvetica —
which costs no bytes and has real Latin bold — with the Noto faces as
`fontFallback`. Pinned by a test that asserts both fonts are referenced in the
output.

*How it was found is worth recording*: the Android print **preview** shows a
~370 px thumbnail and draws small text as solid blocks, so it looked like the
same failure before and after the fix. The only way to tell was to render the
actual bytes — `pypdfium2` locally, then the same on the file the release build
produced.

**D4 — `GET /patients` and the seed count.** Aarav joining the family broke two
tests that pinned "the seed holds Sita and Ram". Updated with a note explaining
why the three dashboard women are *not* in that list (they arrive on the sync
pull, not on S06).

**D5 — a name collision on `scheduleProgress`.** `anc_schedule.dart` already
owned the name; the EPI one is now `immunisationProgress`, so a screen importing
both cannot silently get the wrong one.

---

## 8. What is mock-only until the backend implements the addendum

Everything in `docs/CONTRACT_ADDENDUM.md` is implemented **in the app and in the
mock only**. Against a real backend today:

- Immunisation and growth rows would be written locally and **rejected by
  `/sync/push`** as unknown tables, and would never come down on a pull. The
  child-health screen would still work offline on this device and would never
  reach a second one.
- `sections` on `POST /grants` would be ignored, so a grant the patient narrowed
  would redeem as the **whole record**. The app would show no "Patient shared"
  line, because the server would echo no sections — so it fails to the *old*
  behaviour rather than to a wrong one, but the patient's choice would not be
  honoured.
- `findings.notesText` would round-trip or be silently dropped depending on how
  `findings` is stored.
- The three config flags would read false from the client's own defaults, which
  is what they should be anyway.

**Nothing fails loudly, and nothing corrupts.** That is the property the
additive-only rule was for. But the consent case is the one to implement first:
it is the only one where the app implies a promise the server would not keep.

---

## 9. Known issues

Carried forward and still true: no QR has ever been read optically; MIUI's
camera crashes on this phone; a revoked grant reports as expired; a pushed visit
writes no audit entry; "Last vitals" reads only the latest Visit; the local
database is unencrypted; rotation is not pinned; the Nepali **TTS** voice has
never been confirmed audible; map tiles are not cached; the dashboard counts
only this phone; `Asia/Kathmandu` is hard-coded for reminders.

New with Tier 3:

1. **The EPI schedule is cross-checked but not officially confirmed.** It was
   compared row by row against three published summaries on 2026-09-19, which
   corrected the fIPV error (§7a) — but that is not the Ministry's own
   publication. The asset, the screen and the PDF all say exactly that.
   **Somebody with the official schedule must still confirm every row before a
   health worker acts on it.** Schedules also move; the `verification` block
   records when this one was last looked at.
2. **The growth chart is weight-for-age only.** The band itself is now the
   real thing — `assets/who_wfa.json` is the WHO Child Growth Standards,
   machine-parsed from WHO's published tables (§7b) — but weight-for-age alone
   cannot tell a short child from a wasted one. Height-for-age and
   weight-for-height are not in the app, and the screen says as much in both
   languages rather than implying the chart answers more than it does.
3. **Nepali dictation has never actually been spoken at.** The microphone
   appears, the recogniser initialises and `RECORD_AUDIO` is granted, but nobody
   has said a Nepali sentence and read the transcript back. The locale decision
   is tested; the transcription is not.
4. **The Android print preview misrepresents the PDF.** Its thumbnail rasteriser
   draws small text as black blocks. The document is fine — see D3. Noted in the
   demo script so nobody panics on stage.
5. **A dose given is pushed; the schedule is not.** By design (addendum §1), but
   it means a child's schedule exists on the device that generated it and on the
   server, and *only* reaches a second device if the server generates it too. If
   the backend does not implement schedule generation, a provider who scans that
   child sees an empty card.
6. **`sections: ["audit"]` does nothing yet.** The audit list is a separate
   endpoint and is not part of the redeem bundle, so the chip is reserved rather
   than functional. It is in the enum because the contract should name the whole
   set once.
7. **The consent choice is remembered per patient on this device only.** It is a
   convenience, not a record; the grant is the authority.
8. **One unreproduced test failure.** A single `+520 -1` in one of five runs,
   name not captured; fourteen consecutive green runs afterwards. This is the
   third sighting of the same symptom across three sessions and roughly
   forty-five full-suite runs — it predates Tier 3 by two sessions. Written up
   in `docs/FLAKY_TEST.md`, including the loop that will capture the name next
   time.

---

## 10. Files changed

### New application code

`lib/domain/rules/epi_schedule.dart`, `lib/domain/rules/growth_reference.dart`,
`lib/data/local/daos/child_health_dao.dart`,
`lib/data/repositories/child_health_repo.dart`,
`lib/features/child/child_health_screen.dart`,
`lib/features/child/growth_chart.dart`,
`lib/features/shared/voice/speech_locale.dart`,
`lib/features/shared/voice/voice_note_button.dart`,
`lib/features/export/patient_pdf.dart`,
`lib/features/export/patient_pdf_service.dart`,
`lib/features/export/export_pdf_button.dart`.

### Modified application code

`lib/domain/models/models.dart` (Immunisation, GrowthMeasurement,
`AccessGrant.sections`, `Findings.notesText`, three config flags),
`lib/domain/models/enums.dart` (`GrantSection`, two TimelineKinds),
`lib/core/ids/ids.dart` (`immunisationId`),
`lib/core/net/mock_api.dart` (both tables in push/pull, timeline kinds, bundle
filtering, Aarav, config flags, `GET /patients` scoping),
`lib/core/providers.dart`, `lib/core/config/app_config.dart` (remembered
consent), `lib/core/streams/combine_latest.dart` (`combineLatest2`),
`lib/data/local/app_database.dart` (two tables, schema v2 migration, sync
whitelist), `lib/data/local/mappers.dart`,
`lib/data/local/daos/sync_meta_dao.dart` (granted sections),
`lib/data/sync/sync_engine.dart`, `lib/data/sync/sync_payload.dart`,
`lib/router.dart`, `lib/features/patient_home/patient_home_screen.dart`,
`lib/features/patient_home/share_sheet.dart`,
`lib/features/provider/provider_patient_screen.dart`,
`lib/features/provider/scan_screen.dart`,
`lib/features/provider/visit_form_screen.dart`,
`lib/features/maternal/anc_contact_screen.dart`,
`lib/features/timeline/timeline_screen.dart`,
`lib/features/timeline/local_timeline.dart`,
`lib/features/settings/settings_screen.dart`,
`lib/core/l10n/app_en.arb` + `app_ne.arb` (60 new keys, 422 each, parity
checked) and the regenerated `gen/`.

### Assets and build

`assets/epi_schedule.json`, `assets/who_wfa.json` (replacing
`assets/who_wfa_illustrative.json`, deleted), `docs/reference/` (WHO's two
source PDFs and the parser that turned them into the asset),
`assets/fonts/NotoSansDevanagari-Regular.ttf`,
`assets/fonts/NotoSansDevanagari-Bold.ttf`, `pubspec.yaml`, `pubspec.lock`,
`android/app/src/main/AndroidManifest.xml`.

### Tests (435 → 533)

New: `test/rules/epi_schedule_test.dart` (30 — including six that pin the
cross-checked rows, the seven-visit structure and the 9-month antigens),
`test/rules/growth_reference_test.dart` (23 — including the four anchor months
per sex checked against WHO's published values),
`test/features/child_health_test.dart` (13 — including the asset-vs-mock drift
check),
`test/features/grant_sections_test.dart` (13),
`test/features/speech_locale_test.dart` (10),
`test/features/patient_pdf_test.dart` (9).
Modified: `test/local/app_database_test.dart`, `test/net/mock_api_test.dart`.

### Docs and artefacts

`docs/CONTRACT_ADDENDUM.md` (new), `docs/TIER3_HANDOFF.md` (this file),
`docs/DEMO_SCRIPT.md`, `docs/FLAKY_TEST.md` (round 3),
`docs/screens/tier3_*.png` (15), and
`build/MeroSwasthya-demo-tier3-arm64-v8a.apk`.

---

## 11. Summary

**What passed.** All seven items are built and were verified on the phone, not
only in tests. Aarav's immunisation card reads 16 of 18 with two genuinely
overdue doses outlined in red and his three weights plotted over a reference
band; a QR narrowed to "Pregnancy" redeems into an S21 that says *"Patient
shared: Pregnancy"* and withholds the medicines, vitals and documents while
still showing the allergy; the microphone appears on the ANC notes field and
asks for the microphone permission; and the release APK's **own** PDF — pulled
off the phone and rasterised — renders bold Latin, Devanagari and Bikram Sambat
dates correctly. The Settings integrations say plainly that they are not
connected and why. The analyzer is clean, the suite is 533 green, the schema
migration preserved an existing install's data, and the 32.2 MB arm64 APK opens
to PIN unlock with everything intact. **Part A is untouched**: every addition is
optional or new, and `docs/CONTRACT_ADDENDUM.md` gives the backend developer the
exact shapes, the mock's behaviour and a task checklist.

**What failed.** Nothing was abandoned. Two §17 items remain where earlier
sessions left them — document capture is still blocked by MIUI's own camera
crash, and a visit arriving via `/sync/push` still writes no audit entry, which
is a backend gap. One test failed once in five runs and never again in fourteen;
its name was not captured, it is the third sighting of a symptom that predates
Tier 3 by two sessions, and `docs/FLAKY_TEST.md` now carries the loop that will
catch the name next time. Five defects were found and fixed along the way (§7),
three of them only visible by rendering real output rather than trusting a
preview.

**What needs a human.** Three things. The two reference tables have both been
dealt with since this was first written: the EPI schedule was cross-checked
against three published sources, which caught a real error — fIPV was at 6 and
14 weeks and belongs at 14 weeks and 9 months (§7a) — and the illustrative
growth band was **replaced by the WHO Child Growth Standards themselves**, which
turned out to have been wrong by up to 1.7 kg in both directions (§7b). What is
left of that pair is one job: somebody still has to **confirm the immunisation
schedule against the Ministry's own publication**, because three secondary
sources agreeing is not the same as the primary one. Somebody
has to **speak Nepali at the microphone** and read the transcript back, which is
the one part of dictation no test can cover. And the backend developer has to
work through `docs/CONTRACT_ADDENDUM.md` — starting with grant `sections`, the
only addition where the app currently implies a promise a real server would not
keep.
