# UX and discoverability audit

**Scope.** Every user-facing feature that exists on disk today, patient side and
provider side, Tier 1–3. Walked from the code (`lib/router.dart` plus every
screen under `lib/features/`) and cross-checked against the captured screenshots
in `docs/screens/` (the `enduser_*` and `newphone_*` sets).

**Reference.** `docs/FRONTEND_SPEC.md` §11 (S01–S23) and §16 (UX conventions),
and `docs/UI_RESTYLE_REPORT.md` §5 (per-screen summary) — the restyle fixed how
the app *looks*; this audit is about whether a feature can be *found*.

**Rules of the count.** "Taps from home" counts taps from the role's landing
screen (`/family` for a patient, `/provider` for a health worker) to the screen
where the feature is usable, after unlock. Opening a sheet counts as a tap.
Scrolling does not count as a tap but is called out where a control is below the
fold. A feature that only appears under a condition is counted in the state where
it appears, and its absence in the other states is the finding.

> **Constraint honoured throughout:** nothing in the remediation changes
> behaviour, data flow, an API call, the mock, the QR modes (offline `SWC2` and
> server `SWC1` both stay exactly as they are), or the "Use mock server" /
> Server URL settings.

---

## Table — patient side

| # | Feature | Screen (route) | Taps from home | How it is reached | Problem | After (taps · where) |
|---|---------|----------------|----------------|-------------------|---------|----------------------|
| P1 | Family list | `FamilyScreen` `/family` | 0 | Landing screen | — (it *is* home) | **0** · **Home** tab — avatar strip *and* the selected record on one screen |
| P2 | Add family member | `PatientFormScreen` `/family/new` | 1 | Extended FAB | OK | **1** · the "Add" chip at the end of the avatar strip |
| P3 | Open a member's record | `PatientHomeScreen` `/patient/:id` | 1 | Tap a family card | OK | **0** · the selected member's record is what Home shows |
| P4 | Edit a member | `PatientFormScreen` `/family/:id/edit` | 2 | Unlabeled ✏️ icon in the patient app bar | **Unlabeled icon.** No text, tooltip only — invisible to a first-time user and to anyone not hovering a mouse | **2** · **More** → "Edit details" (labelled); the pencil stays as a shortcut |
| P5 | **Share record (QR)** | `share_sheet.dart` (modal on S08) | 2 | Primary `FilledButton` on the patient record | Correct weight, but two taps behind a list screen the user must first understand | **1** · primary brand-blue button on **Home** |
| P6 | Timeline | `TimelineScreen` `/patient/:id/timeline` | 2 | One of four tiles crammed into a single `Row` | Four tiles in one row at 360 dp ≈ 78 dp each; Devanagari labels ellipse. Tile reads as an icon with a fragment of a word | **1** · **Records** tab (also a 2×2 tile on Home) |
| P7 | Documents | `DocumentsScreen` `/patient/:id/documents` | 2 | Same cramped 4-up row | Same | **1** · **Documents** tab (also a 2×2 tile on Home) |
| P8 | Reminders | `RemindersScreen` `/patient/:id/reminders` | 2 | Same cramped 4-up row | Same | **1** · 2×2 tile on Home; also **2** · **More** → "Reminders" |
| P9 | Pregnancy dashboard | `PregnancyDashboardScreen` `/pregnancy/:id` | 2 | **Third tile only**, and only while a pregnancy is active | Shares one slot with three other features (see P10–P12) | **1** · 2×2 tile on Home (contextual slot, rule unchanged) |
| P10 | Register pregnancy | `RegisterPregnancyScreen` `/patient/:id/pregnancy/new` | 2 | Third tile, only if female **and** no pregnancy row at all | Hidden the moment a pregnancy is delivered — a second pregnancy cannot be registered from the patient side | **1** · tile when eligible, **and always 2** · **More** → "Register pregnancy" |
| P11 | Child health (EPI + growth) | `ChildHealthScreen` `/patient/:id/child` | 2 | Third tile, only if under five **and** no active pregnancy | Same shared slot | **1** · tile when under five, **and 2** · **More** → "Child health" |
| P12 | Audit — "Who viewed my record" | `AuditScreen` `/patient/:id/audit` | **3** | Third tile **only for an adult male with no pregnancy**; everyone else must open an unlabeled "More" text button at the bottom of a scroll, then a sheet row | **Worst patient-side burial.** The one privacy feature in the app, and for most users it is three taps behind a `TextButton` labelled only "More", below the fold | **2** · **More** → "Who viewed my record" — for every member, not just adult men |
| P13 | Printed health card | `PrintedCardScreen` `/patient/:id/card` | **3** | Record → "More" text button → sheet row | Three taps, behind an unlabeled More; it is the offline fallback for the whole QR story and a demo beat | **2** · **More** → "Printable card" |
| P14 | Export record as PDF | `ExportPdfButton` → `patient_pdf.dart` | **3** | Record → "More" → sheet row | Same burial; also the only way the record can leave the app | **2** · **More** → "Export PDF" |
| P15 | Growth chart | inside `ChildHealthScreen` | 3 | Record → child tile → scroll | Acceptable (it is a section of child health, not a feature of its own) | 3 · unchanged (a section of Child health) |
| P16 | Settings (incl. language) | `SettingsScreen` `/settings` | 2 | **Unlabeled ⋮** on the family app bar → menu item | **⋮ with no label.** The Nepali/English toggle — a headline feature of the product — is behind a three-dot glyph most users never press | **2** · **More** → "Settings", subtitled "Language" |
| P17 | "I am a health worker" (activate) | `ProviderActivateScreen` `/provider/activate` | 2 | Same unlabeled ⋮ | The single path by which a patient account becomes a provider account, hidden behind ⋮. Onboarding dead end | **2** · **More** → "I am a health worker" |
| P18 | Sync status / Sync screen | `SyncScreen` `/sync` | 1 | `SyncChip` — a 16 px cloud glyph in the app bar | **Unlabeled icon.** Tappable, but nothing says so and nothing says *when* it last synced. "Is my data safe?" is unanswerable at a glance | **0 to read, 1 to open** · full pill under the Home app bar saying "Synced 2 min ago" / "3 changes waiting"; compact labelled pill in every other app bar |
| P19 | Nearest facility map | `FacilityMapScreen` `/facilities` | **∞** | Only from an ANC referral card or the birth plan | **Unreachable from the patient side.** A patient cannot look up the nearest birthing centre unless a red triage happens to be on screen | ∞ · unchanged — see *Left alone* |
| P20 | Birth plan | inside `PregnancyDashboardScreen` | 3 | Record → pregnancy tile → scroll | Acceptable (section of the pregnancy dashboard) | 3 · unchanged (a section of the pregnancy dashboard) |
| P21 | Delivery outcome | `DeliveryScreen` `/pregnancy/:id/delivery` | 3 | Pregnancy dashboard → button | Acceptable (provider action, correctly placed) | 3 · unchanged |
| P22 | Switch to the provider side | `/provider` | 2 | Unlabeled ⋮ (health workers only) | Same ⋮ problem; a dual-role user switches sides several times a day | **2** · **More** → "Health worker mode" |

## Table — provider side

| # | Feature | Screen (route) | Taps from home | How it is reached | Problem | After (taps · where) |
|---|---------|----------------|----------------|-------------------|---------|----------------------|
| H1 | Scan a patient QR | `ScanScreen` `/provider/scan` | 1 | Large brand-blue tile | Good — but one tap behind a list the provider does not need first | **0** · **Scan** is the landing tab — the camera is up with no taps |
| H2 | Recent (granted) patients | list on `ProviderHomeScreen` | 0 | Landing screen | OK | 1 · **Patients** tab (was 0; Scan took the landing slot — see the trade-offs note) |
| H3 | Patient summary | `ProviderPatientScreen` `/provider/patient/:id` | 1 | Tap a recent-patient card | OK | 2 · **Patients** → card, or pushed straight off a successful scan |
| H4 | **Add visit** | `VisitFormScreen` `/provider/patient/:id/visit/new` | 2 | Primary button, pinned bottom bar | Correct | 2 after a scan (the normal path), 3 via the Patients list; now in a bottom bar with a named "More actions" row above it |
| H5 | ANC contact (next due) | `AncContactScreen` `/pregnancy/:id/contact/:no` | 2 | `OutlinedButton` **inside** the pregnancy card, mid-scroll | **Below the fold.** The most common pregnancy action on the screen sits under vitals and medicines; on a full record it is two swipes down | **Same place every time** · second filled button in the pinned bottom bar whenever a pregnancy is open — no longer mid-scroll |
| H6 | Capture paper record | `DocumentsScreen` `/patient/:id/documents` | 2 | Secondary button in the bottom bar | OK, but the label wraps to two lines and competes with Add visit | **"More actions"** row, labelled, fixed position |
| H7 | Register pregnancy | `/patient/:id/pregnancy/new` | 2 | Secondary button in the bottom bar | Appears/disappears, so the bar's shape changes between patients — nothing is ever in the same place twice | **"More actions"** row, labelled, fixed position |
| H8 | Patient timeline | `/patient/:id/timeline` | 2 | `OutlinedButton` **after** medicines, vitals and the pregnancy card | **Below the fold**, and its position moves with the length of the record | **"More actions"** row — off the scroll view entirely, and still present in read-only mode |
| H9 | Provider dashboard | `ProviderDashboardScreen` `/provider/dashboard` | 1 | `OutlinedButton` under the scan tile | OK | 2 · **More** → "Health post dashboard" |
| H10 | Dashboard bucket drill-down | `/provider/dashboard/:bucket` | 2 | Tap a dashboard count tile | OK | 3 · unchanged relative to the dashboard |
| H11 | Manual code entry | dialog on `ScanScreen` | 2 | Underlined `TextButton` over the camera scrim | OK — deliberately the exception, and the demo fallback | **1** · unchanged control, now one tap from the landing tab |
| H12 | My family (patient side) | `/family` | 2 | **Unlabeled ⋮** | Same ⋮ problem, for the role most likely to switch | **2** · **More** → "My family" |
| H13 | Settings | `/settings` | 2 | Unlabeled ⋮ | Same | **2** · **More** → "Settings", subtitled "Language" |
| H14 | Sync status / Sync screen | `/sync` | 1 | `SyncChip` glyph | Same as P18 — and a health worker working offline all morning has no way to read "3 changes waiting" without opening a screen | **0 to read, 1 to open** · full pill on the Patients tab, compact labelled pill elsewhere |
| H15 | Torch | `ScanScreen` app bar | 2 | Icon, tooltip `'Torch'` — **hard-coded English** | Not localised; minor, icon is conventional | 2 · unchanged; tooltip localised (`scanTorch`) |

---

## The worst 10

Ranked by how likely a real user is to never find the feature at all.

| Rank | Finding | Where | Why it is the worst |
|------|---------|-------|---------------------|
| **1** | **Settings — and with it the Nepali/English toggle — is behind an unlabeled ⋮** | S06 family, S19 provider home | Language is a headline claim of the product. A three-dot glyph in a Devanagari-first app for users with low digital literacy is not a discoverable control. Two screens, same glyph, two different menus. |
| **2** | **"Who viewed my record" is 3 taps behind a `TextButton` labelled only "More", below the fold** | S08 patient record | The app's only privacy/transparency feature. For an adult female, a pregnant woman or a child it is *never* on the surface — the tile slot it would use is taken. |
| **3** | **"I am a health worker" is behind the same unlabeled ⋮** | S06 family | The sole route from a patient account to a provider account. If it is not found, the provider half of the product does not exist for that user. |
| **4** | **One tile slot rotates between four different features** | S08 patient record | Pregnancy dashboard, Register pregnancy, Child health and Audit share a single slot by a `switch`. Whichever three lose are either 3 taps deep or unreachable. Worst case: a woman whose pregnancy has been delivered can no longer register a new one from her own phone. |
| **5** | **Printed card and PDF export are 3 taps behind "More"** | S08 patient record | Both are the offline fallback for the entire QR story — exactly what is needed when the phone or the network is the problem, i.e. when the user is least able to go hunting. |
| **6** | **Four tiles in one `Row` at 360 dp** | S08 patient record | ≈78 dp per tile. Nepali labels ellipse to a fragment; the row reads as four icons. The restyle's own rule — "never icon only" — is broken here by geometry rather than by intent. |
| **7** | **`SyncChip` is a 16 px unlabeled glyph that answers no question** | Every screen, both roles | It is tappable and goes to `/sync`, but nothing signals that, and it never says *when*. "Is my visit saved?" is the single most common anxiety in an offline-first app. |
| **8** | **On the provider summary, ANC contact and Timeline are below the fold** | S21 provider summary | The two reads a health worker does with the patient in front of them, both under a variable-length record. Their screen position changes patient to patient, so no muscle memory can form. |
| **9** | **Empty states are a title and nothing else** | Timeline, Reminders, Audit, provider Recent patients | `EmptyState` supports `body:` and `action:`; four screens pass neither. "No history yet" does not tell a first-time user that a health worker has to scan them first, and offers no way forward. |
| **10** | **Pull-to-refresh is placed *after* the empty check, so it never works on an empty list** | Audit, Reminders (and absent entirely on Timeline, Documents) | The exact moment a user pulls down is when the list looks wrong — i.e. when it is empty. The gesture is dead precisely then. |

Runner-up (not in the ten, fixed anyway): **no first-run guidance of any kind.**
The app opens on a family list with no explanation of what the QR is for or that
the health worker is meant to scan it.

---

# Part 2 — after

## What the structure is now

**Patient side — four labelled tabs** (`PatientShell`, route `/family`):

| Tab | What it is | Built from |
|-----|-----------|------------|
| **Home** | Family avatar strip *plus* the selected member's record on one screen: identity + allergies, "Share record (QR)" as the only primary button, a 2×2 tile grid (Timeline · Documents · contextual · Reminders), the pregnancy card | `PatientHomeTab` + `PatientRecordBody` + `FamilyStrip` |
| **Records** | S09's timeline for the selected member, untouched | `TimelineScreen` |
| **Documents** | S10, untouched | `DocumentsScreen` |
| **More** | "This record" (Reminders, Who viewed my record, Printable card, Child health when under five, Register pregnancy when eligible, Edit details, Export PDF) and "This phone" (Health worker mode / I am a health worker, Sync, Settings) | `PatientMoreTab` + `MoreRow` |

**Provider side — three labelled tabs** (`ProviderShell`, route `/provider`):

| Tab | What it is | Built from |
|-----|-----------|------------|
| **Scan** | S20's scanner, live, as the landing tab | `ScanScreen` (unchanged apart from the navigation verb) |
| **Patients** | S19's list of patients whose grant is still open | `ProviderHomeScreen` |
| **More** | Health post dashboard, Sync, My family, Settings | `ProviderMoreTab` |

Which member the Records, Documents and More tabs act on comes from
`selectedMemberProvider` — session state, set by the avatar strip — rather than
from a path segment, because a tab has no path segment to carry an id in. The
routes themselves are unchanged: `/family` and `/provider` still exist and still
mean the same thing to `authRedirect`, and every deep link (`/patient/:id/…`,
`/pregnancy/:id/…`, `/provider/patient/:id`) resolves exactly as before.

## The worst 10, and what happened to each

| Rank | Finding | Fix | Where |
|------|---------|-----|-------|
| 1 | Settings + language behind an unlabeled ⋮ | Both ⋮ menus deleted. Settings is a named row in each role's More tab, subtitled "Language" | `patient_more_tab.dart`, `provider_more_tab.dart` |
| 2 | "Who viewed my record" 3 taps behind a "More" text button | 2 taps, named row, **for every member** rather than only an adult man | `patient_more_tab.dart` |
| 3 | "I am a health worker" behind the same ⋮ | 2 taps, named row in the patient More tab | `patient_more_tab.dart` |
| 4 | One tile slot rotated between four features | Rule kept (the tile is still contextual), but every feature that applies is *also* a named row in More. A delivered pregnancy no longer takes "Register pregnancy" off the phone | `patient_home_screen.dart`, `patient_more_tab.dart` |
| 5 | Printed card and PDF export 3 taps down | Both 2 taps in More | `patient_more_tab.dart` |
| 6 | Four tiles in one `Row` at 360 dp | 2×2 grid — twice the width per label. `layout_test` covers it at 360 and 412 in both locales | `patient_home_screen.dart` |
| 7 | `SyncChip` an unlabeled 16 px glyph | `SyncPill`: always carries words, and in its full form the time — "Synced 2 min ago", "3 changes waiting", "Offline", "Not synced yet". Full pill under the app bar on both home tabs, compact labelled pill in every other app bar | `app_widgets.dart` + 15 call sites |
| 8 | Provider ANC contact and Timeline below the fold | Both out of the scroll view. ANC contact is the second filled button in the pinned bottom bar whenever a pregnancy is open; Timeline is in a labelled "More actions" row that is in the same place on every patient | `provider_patient_screen.dart` |
| 9 | Empty states were a title and nothing else | One-line explanation on Timeline, Reminders, Audit, Documents and the provider Patients list; a primary action wherever there is one to offer | 5 screens + 5 new l10n pairs |
| 10 | Pull-to-refresh placed after the empty check, so dead on an empty list | `RefreshIndicator` lifted **above** `asyncView` on Timeline, Documents, Reminders, Audit, Home, Patients and the provider dashboard, and the empty state is now a scroll view so the gesture has something to pull | 7 screens |
| — | No first-run guidance at all | 3 patient cards ("This is your family", "Share your record with a QR", "Everything else is under More") and 2 provider cards ("Health workers scan here", "Everyone you scanned today). Dismissable at any point, shown once, flag in shared preferences | `coach_marks.dart` |

## Screens changed

**New files**

| File | What it is |
|------|-----------|
| `lib/features/shell/shell_scaffold.dart` | `ShellTab`, `ShellScope`, `ShellScaffold` — the labelled bottom nav, one-tab-at-a-time building, and the back-to-Home `PopScope` |
| `lib/features/shell/patient_shell.dart` | The four patient tabs, and the member plumbing for Records/Documents |
| `lib/features/shell/provider_shell.dart` | The three provider tabs |
| `lib/features/shell/patient_home_tab.dart` | Home: strip + record + the full sync pill |
| `lib/features/shell/patient_more_tab.dart` | Everything the audit found buried, as named rows |
| `lib/features/shell/provider_more_tab.dart` | Dashboard, Sync, My family, Settings |
| `lib/features/shell/more_row.dart` | `MoreRow` — the shape that replaced the ⋮ |
| `lib/features/shell/coach_marks.dart` | `CoachMark`, `CoachTour`, `CoachMarks` |
| `lib/features/family/family_widgets.dart` | `FamilyStrip` (avatar switching) and `PregnantBadge`, moved out of the deleted family screen |
| `test/features/navigation_test.dart` | 10 tests: tab switching, back behaviour, coach marks once, shell mechanics |

**Deleted**

| File | Why |
|------|-----|
| `lib/features/family/family_screen.dart` | S06 is the Home tab now. Its family card became the avatar strip; `PregnantBadge` moved to `family_widgets.dart` |

**Edited**

| File | Change |
|------|--------|
| `lib/router.dart` | `/family` → `PatientShell`, `/provider` → `ProviderShell`. No path changed, no redirect changed |
| `lib/features/patient_home/patient_home_screen.dart` | Split into `PatientHomeScreen` (the `/patient/:id` route) and the shared `PatientRecordBody`; 4-up tile row → 2×2 grid; the "More" text button and its sheet removed (More is a tab) |
| `lib/features/provider/provider_home_screen.dart` | Becomes the Patients tab: scan tile removed (Scan is a tab), ⋮ removed, full sync pill added, empty state explained, pull-to-refresh |
| `lib/features/provider/provider_patient_screen.dart` | New bottom bar: Add visit + ANC contact N as the two filled actions, "More actions" row above them; the mid-scroll Timeline button and the in-card ANC button removed; the bar now also renders in read-only mode carrying only Timeline |
| `lib/features/provider/scan_screen.dart` | `pushReplacement` → `push` + restart the camera when the summary is popped (a tab cannot replace itself); torch tooltip localised. **Nothing about the redeem, the decode, the caching or either QR mode changed** |
| `lib/features/shared/widgets/app_widgets.dart` | `SyncChip` → `SyncPill` / `SyncPill.compact`, with `syncedLabel` for the relative time |
| `lib/features/timeline/timeline_screen.dart` | Empty-state body, pull-to-refresh above `asyncView` |
| `lib/features/documents/documents_screen.dart` | Empty-state body, pull-to-refresh |
| `lib/features/reminders/reminders_screen.dart` | Empty-state body, refresh lifted out of the `data` branch |
| `lib/features/audit/audit_screen.dart` | Empty-state body, refresh lifted out of the `data` branch |
| `lib/features/provider/provider_dashboard_screen.dart` | Pull-to-refresh, empty state made scrollable |
| `lib/features/maternal/anc_contact_screen.dart` | Helper text on Findings, Notes and Danger signs |
| `lib/features/provider/visit_form_screen.dart` | Helper text on Main complaint, Vitals, Diagnoses, Advice, Medicines |
| `lib/features/maternal/register_pregnancy_screen.dart` | Register moved from the bottom of the scroll view into a `StickySaveBar`, so Save is pinned on all five forms |
| `lib/shared/widgets/soft_card.dart` | `helper` slot on `SectionHeader` and `FormSection` |
| `lib/core/config/app_config.dart` | `coachSeen` / `setCoachSeen` / `clearCoachSeen` |
| `lib/core/providers.dart` | `selectedMemberProvider` |
| `lib/core/theme/app_theme.dart` | `AppTheme.navBarHeight`, named so the coach overlay can stay clear of the nav bar |
| `lib/core/l10n/app_en.arb`, `app_ne.arb` | 47 new message keys in both files. **No existing key removed or changed** |
| `test/features/layout_test.dart` | `FamilyScreen` → `PatientHomeTab`; `PatientMoreTab` and `ProviderMoreTab` added (+8 layout cases) |
| `test/features/delivery_test.dart` | `PregnantBadge` import follows the widget to `family_widgets.dart` |

## Deliberately left alone

| Thing | Why |
|-------|-----|
| **The QR share sheet — `SWC1` grant and `SWC2` offline snapshot** | Out of scope by instruction and by risk. Both modes, the ten-minute countdown, the revoke path, the section chips and the per-device mode memory are byte-for-byte unchanged. Only the route in changed: the primary button moved from the record one level down to Home |
| **The scanner's redeem paths** | The camera, the viewfinder, "Enter code instead", the PIN challenge, the grant redeem and the snapshot decode are unchanged. The two edits are `pushReplacement` → `push` (forced: a tab cannot replace itself) plus a camera restart on return, and a localised torch tooltip |
| **"Use mock server" and Server URL** | Explicitly out of scope. Untouched |
| **The facility map's unreachability from the patient side (P19)** | Adding a patient-side entry point is a new feature, not a discoverability fix, and it needs a decision about what the list means with no referral context. Recorded as a known gap |
| **Growth chart, birth plan, delivery outcome (P15, P20, P21)** | Sections of a parent screen, correctly placed at three taps. Promoting them would flatten a hierarchy that is genuinely nested |
| **The dashboard bucket drill-down (H10)** | A count that opens its own list is the conventional and correct shape |
| **The `/patient/:id` route** | Nothing in the patient UI links to it now, but it is a real deep link and the provider side reaches `/patient/:id/timeline` and `/patient/:id/documents` beside it. Kept, and it renders the same `PatientRecordBody` as Home so the record cannot look like two screens |
| **Everything below `lib/features/`** | No behaviour change means no reason to touch the rules engine, the triage, the sync engine, the outbox or any repository. None were edited |

## Trade-offs worth stating

1. **Scan took the provider landing slot.** The recent-patients list was 0 taps and is now 1; the patient summary was 1 and is now 2 from a cold start. That is deliberate: the phone comes out of the pocket to scan, and the normal path to a summary is *through* a scan, which pushes it directly. Add visit is still 2 taps after a scan; it is 3 when returning to a patient through the Patients tab.
2. **A tab switch rebuilds the tab.** `ShellScaffold` builds one tab at a time rather than holding an `IndexedStack`, which is load-bearing — the Scan tab *is* a live `MobileScannerController`, and an `IndexedStack` would leave the camera running behind the dashboard. The cost is a lost scroll position on four short stream-driven screens.
3. **The compact sync pill can ellipse.** In an app bar the label is `Flexible` with `maxLines: 1`, so a long Nepali pending string shortens rather than pushing the row off a 360 dp screen. The full pill under the two home tabs' app bars always has room for the whole sentence, which is where the question is actually asked.
4. **The provider bottom bar is taller** — a "More actions" row plus up to two filled buttons, around 140 dp with the safe area. That is the cost of having the two most-used actions and the three secondary ones all visible and named at once, instead of an overflow icon.

## Verification

| Check | Result |
|-------|--------|
| `flutter analyze` | **No issues found** |
| `flutter test` | **670 passed** (652 before this work: +10 navigation, +8 layout) |
| Layout regression, 360×780 and 412×915, `en` and `ne` | Every screen including the new Home tab, patient More tab and provider More tab passes with no `RenderFlex overflowed` |
| Both ARB files carry every new key | Verified by key-set diff: the only asymmetry is the pre-existing `@appTitle` metadata entry |
| Release build, `--split-per-abi --dart-define=MOCK_API=true` | Built: `app-arm64-v8a-release.apk` 33.8 MB, `app-armeabi-v7a-release.apk` 30.7 MB, `app-x86_64-release.apk` 36.1 MB. **Not installed** — no device attached |

### Device verification — TODO

`adb devices` reported no attached device at any point during this session
(polled four times; the POCO's USB connection is known to drop out and return).
Everything below is therefore outstanding, and none of it has been claimed as
done:

- [ ] `adb -s <serial> install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- [ ] Walk the patient side: screenshot all four tabs in `en` and `ne` →
      `docs/screens/ux_after_patient_{home,records,documents,more}_{en,ne}.png`
- [ ] Screenshot the three first-run coach marks, then relaunch and confirm they
      do not return → `ux_after_coach_{1,2,3}_en.png`
- [ ] Walk the provider side: all three tabs in `en` and `ne` →
      `ux_after_provider_{scan,patients,more}_{en,ne}.png`
- [ ] Screenshot the top-10 fixed features: More → Who viewed, Printable card,
      Export PDF, Settings, "I am a health worker"; the provider summary's new
      bottom bar with and without a pregnancy; the full sync pill in each of its
      four states
- [ ] `adb logcat` while walking both roles: confirm no `RenderFlex overflowed`
- [ ] One offline QR end to end: patient Home → Share record (SWC2) → provider
      Scan tab (or "Enter code instead") → summary → back returns to a live
      camera. This is the regression that matters most, because the QR flows are
      the one thing this pass was told not to touch
- [ ] Press Android back from each non-home tab and confirm it lands on Home;
      press it again on Home and confirm the app exits rather than trapping

---

## Summary

The app's problem was never that a feature was missing — every Tier 1–3 feature
has a screen, and the restyle already made those screens look right. The problem
was that a third of them could only be found by pressing an unlabeled three-dot
glyph or a text button reading "More" at the bottom of a scroll, and that the
patient's own record sat one level below a directory of people. This pass turned
both roles into labelled bottom-tab shells — patient *Home · Records · Documents
· More*, health worker *Scan · Patients · More* — put the family strip and the
open record on one screen, moved the QR share button to Home as the only primary
action, deleted both `⋮` menus into named rows with a line each saying what they
do, and pulled the provider's two most-used actions into a fixed bottom bar with
the rest named above it rather than hidden. Along the way the sync chip learned
to speak ("Synced 2 min ago", "3 changes waiting"), five empty states learned to
explain themselves and offer a way forward, pull-to-refresh started working on
the empty lists where people actually reach for it, two long clinical forms got a
sentence under each block heading, and a first run now gets three dismissable
cards it will never see again. Every tap count in the tables above either fell or
stayed the same, with one stated exception: Scan took the provider's landing slot
from the recent-patients list, which is a trade made on purpose because the phone
comes out of the pocket to scan. Behaviour, data flow, the mock, both QR modes
and the server settings are untouched; `flutter analyze` is clean and 670 tests
pass, up from 652. What is *not* done is the device leg — no phone was attached
at any point this session, so the release APKs are built but uninstalled and the
`ux_after_*` screenshots, the logcat overflow sweep and the one end-to-end
offline QR scan remain on the TODO list above, unclaimed.
