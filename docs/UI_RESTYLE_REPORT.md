# UI restyle — premium, calm, clinical

A visual pass over every screen of Mero Swasthya. **No behaviour changed**: no
route, provider, repository, model, DAO, sync rule or l10n key was altered. The
work is colour, spacing, type, shape and — on four screens — where an existing
control sits on the page.

Verified without a device, as instructed: `flutter analyze`, `flutter test` and
`flutter build apk --debug` only. No `adb`, no `flutter run`.

---

## 1. Where the tokens live

| File | What is in it |
|---|---|
| `lib/core/theme/app_colors.dart` | `AppColors` — every colour in the app, and `TriageColors`, which maps the rules engine's wire strings (`'red'`, `'amber'`, `'green'`) to a colour, a tint, an ink and an icon. |
| `lib/core/theme/app_theme.dart` | `AppSpacing` (the 4 / 8 / 12 / 16 / 24 scale, the 20 px gutter, the two radii), `AppTheme.light()` / `.dark()`, and the text theme. It `export`s `app_colors.dart`, so the ~30 files that already imported `app_theme.dart` for `TriageColors` kept working unchanged. |
| `lib/shared/widgets/soft_card.dart` | The shared shapes: `SoftCard`, `SectionHeader`, `SoftPill`, `SoftTile`, `StatTile`, `FactRow`, `FormSection`, `StepperGrid`, `SegmentedControl`, `StickySaveBar`, `PageGutter`. |

### The palette

```dart
brandBlue      Color(0xFF004C8A)   primary CTA, active states, app-bar accents
brandGreen     Color(0xFF109B75)   success, synced, "live", secondary accents
background     Color(0xFFF8FAFC)   Scaffold
surface        Color(0xFFFFFFFF)   cards and sheets
textPrimary    Color(0xFF1E293B)   headings and body — never pure black
textSecondary  Color(0xFF64748B)   timestamps, subtext, inactive icons

triageGreen    Color(0xFF109B75)
triageAmber    Color(0xFFD97706)
triageRed      Color(0xFFDC2626)
allergyRed     Color(0xFFDC2626)  on allergyTint Color(0xFFFEF2F2)
```

Tints are opaque rather than alpha-blended, because a triage colour sits on top
of a card *and* on top of the page, and a translucent tint that changes shade
depending on what is behind it is not a safety colour any more. Everything
genuinely derived — the card shadow, the hairline, the skeleton grey — uses
`.withValues(alpha: …)`. The deprecated `withOpacity` appears nowhere:

```
$ grep -rn "withOpacity" lib --include=*.dart | wc -l
0
```

### The theme

One `ThemeData`, `useMaterial3: true`, built from
`ColorScheme.fromSeed(seedColor: brandBlue)` and then overridden on
`primary` / `onPrimary` / `secondary` / `onSecondary` / `surface` / `onSurface`
/ `onSurfaceVariant` / `outline` / `outlineVariant` / `error` / `onError` — so
the generated scheme only decides container shades nothing names directly.

Themed components: `AppBar`, `FilledButton`, `OutlinedButton`, `TextButton`,
`IconButton`, `FloatingActionButton`, `InputDecoration`, `Chip`, `BottomSheet`,
`SnackBar`, `NavigationBar`, `Dialog`, `Card`, `ListTile`, `Divider`, `Switch`,
`Checkbox`, `Radio`, `SegmentedButton`, `ProgressIndicator`, `TabBar`.

`InputDecorationTheme` is filled with `surface`, `BorderSide.none` on the
enabled and default borders, 12 px radius, and a 2 px brand-blue focus ring.
`CardTheme` is flat, borderless and 16 px — so a stray `Card` left anywhere
cannot reintroduce the outlined look `SoftCard` replaced.

### Type

A 32 / 24 / 20 / 16 / 14 / 12 scale with headings at `FontWeight.w700`:

| Style | Size | Weight |
|---|---|---|
| `displaySmall` | 32 | w700 |
| `headlineMedium` / `headlineSmall` | 24 | w700 |
| `titleLarge` | 20 | w700 |
| `titleMedium` | 16 | w700 |
| `titleSmall` / `labelLarge` | 14 | w700 / w600 |
| `bodyLarge` | 16 | w400 |
| `bodyMedium` / `labelMedium` | 14 / 12 | w400 / w600 |
| `bodySmall` / `labelSmall` | 12 | w400 / w700 tracked |

**The font is unchanged.** No `fontFamily` is set anywhere in the theme, so the
app keeps the platform font, which is what renders Devanagari correctly on a
Nepali phone. Naming a Latin family in the text theme would have silently broken
every Nepali string — conjuncts falling back glyph by glyph, matras detaching.
Every style instead carries an explicit `height` (1.25–1.45), because Devanagari
vowel signs need headroom above and below the baseline that the default line box
does not give them.

This is pinned by test, not by inspection: `test/features/layout_test.dart`
pumps **every restyled screen under `Locale('ne')`** and fails on any overflow,
and `widgets_test.dart` still asserts that a Nepali triage reason renders as
`गम्भीर रक्तअल्पता` and not as its English counterpart.

---

## 2. Hard-coded colours replaced

Counted before and after with the same two greps.

| | Before | After |
|---|---|---|
| `Color(0x…)` literals outside the token files | **14** | **0** |
| Material `Colors.*` outside the token files (excluding `Colors.transparent`) | **13** | **0** |
| **Total replaced** | | **27** |

`Colors.transparent` survives in 11 places. It is a structural no-op — a
`surfaceTintColor`, an unselected segment, an `InkWell`'s own Material — not a
colour choice, so tokenising it would add indirection and say nothing.

Two groups were tokenised rather than re-coloured, because their values are
*functional*:

* **`AppColors.qrCanvas`** (white) — a QR code needs black on white to be
  scannable. S08's share sheet and A.7's printed card both paint on it.
* **`AppColors.printInk` / `printMuted` / `printBorder` / `printNoticeBg` /
  `printNoticeBorder`** — the printed card is a *picture of a piece of paper*
  that is captured and shared as an image, so it must come out identical in
  dark mode. Those five literals moved into a named "Print" block in
  `AppColors` and render exactly as before.
* **`AppColors.cameraBackdrop`** (black) and **`markerShadow`** — darkening a
  live camera preview, a full-screen photograph and a map pin.

`lib/features/export/patient_pdf.dart` uses `PdfColors.*` from the `pdf`
package. That is a different colour type in a generated document, not a Flutter
widget colour, and is out of scope — see §6.

---

## 3. Contrast

Measured with the WCAG 2.1 relative-luminance formula. "Body" is the 4.5:1
threshold; "large" is 3:1 (≥ 18.66 px bold or ≥ 24 px regular) and also the
threshold for icons, borders and other graphical objects.

### Pairs used for text

| Foreground | Background | Ratio | Body | Large |
|---|---|---|---|---|
| `textPrimary` #1E293B | `background` #F8FAFC | **13.98:1** | ✅ | ✅ |
| `textPrimary` #1E293B | `surface` #FFFFFF | **14.63:1** | ✅ | ✅ |
| `textSecondary` #64748B | `surface` #FFFFFF | **4.76:1** | ✅ | ✅ |
| `textSecondary` #64748B | `background` #F8FAFC | **4.55:1** | ✅ | ✅ |
| `onBrand` #FFFFFF | `brandBlue` #004C8A | **8.75:1** | ✅ | ✅ |
| `brandBlue` #004C8A | `surface` #FFFFFF | **8.75:1** | ✅ | ✅ |
| `brandBlue` #004C8A | `brandBlueTint` #E8F0F8 | **7.60:1** | ✅ | ✅ |
| `onTriageRed` #991B1B | `triageRedTint` #FEF2F2 | **7.60:1** | ✅ | ✅ |
| `onTriageAmber` #92400E | `triageAmberTint` #FFFBEB | **6.84:1** | ✅ | ✅ |
| `onTriageGreen` #065F46 | `triageGreenTint` #ECFDF5 | **7.29:1** | ✅ | ✅ |
| `triageRed` #DC2626 | `surface` #FFFFFF | **4.83:1** | ✅ | ✅ |

### Pairs used for signal — icons, borders, dots, fills, short bold labels

| Foreground | Background | Ratio | Body | Large / graphical |
|---|---|---|---|---|
| `triageRed` #DC2626 | `triageRedTint` #FEF2F2 | **4.41:1** | ⚠️ | ✅ |
| `allergyRed` #DC2626 | `allergyTint` #FEF2F2 | **4.41:1** | ⚠️ | ✅ |
| `triageAmber` #D97706 | `triageAmberTint` #FFFBEB | **3.07:1** | ❌ | ✅ |
| `triageGreen` #109B75 | `triageGreenTint` #ECFDF5 | **3.34:1** | ❌ | ✅ |
| `onBrand` #FFFFFF | `brandGreen` #109B75 | **3.52:1** | ❌ | ✅ |
| `brandGreen` #109B75 | `surface` #FFFFFF | **3.52:1** | ❌ | ✅ |

### The rule that follows from those two tables

The mandated semantic hexes were kept **exactly** as specified. They are used as
the *signal*: the icon, the 2 px border, the dot, the left accent, the filled
bar, and short bold labels. Multi-line body copy sitting on a tint uses the
matching `on*` ink instead — same hue, materially more contrast.

That split exists because of one measured conflict, stated plainly:

> **#DC2626 on #FEF2F2 is 4.41:1** — 0.09 short of the 4.5:1 body threshold.

It clears AA for large and bold text and for graphical objects, so the triage
banner's 16 px w700 headline, its filled icon and its 2 px border are all fine
at the mandated value. The *reasons* under that headline are wrapped sentences
at body size, and they are the most consequential text in the application — they
are why somebody is being sent to hospital tonight — so they take
`AppColors.onTriageRed` and read at **7.60:1** instead of 4.41:1.

The **allergy chip keeps the mandated pair as written** (`allergyRed` on
`allergyTint`, 4.41:1): the brief specified those two values character for
character as a safety decision, and its label is a short bold word rather than
prose. If you want that last 0.09, changing `AppColors.allergyRed` to `#B91C1C`
takes it to 5.91:1 in one edit and touches nothing else; the pill, the border
and the warning icon all read from that one token.

The amber and green pairs are only ever used for icons, dots, progress bars and
filled buttons — never for text on their own tint. Text on those tints uses
`onTriageAmber` / `onTriageGreen`.

### Colour is never alone

Spec §16 is preserved and extended. Every triage state carries a colour **and**
an icon **and** a word: the banner, the timeline row's left accent plus trailing
glyph, the S12 stepper dot, the overdue contact card, the immunisation dose row,
the sync pill, the reminder status pill.

---

## 4. Styling rules, and where each one landed

**Whitespace over borders.** Every `Card` and every `Divider` in the feature
layer is gone — 32 `Card(` call sites and 8 `Divider(height: …)` separators
replaced by `SoftCard` and `SectionHeader` / `FormSection`. Groups are made by a
surface and 16 / 24 px of air, on a 20 px page gutter.

Four deliberate exceptions, all of them safety work rather than decoration:

1. The **triage banner** keeps its 2 px coloured border and its filled icon. It
   is the one thing in the app allowed to read as an interruption.
2. A **selected danger-sign tile** on S13 swaps its shadow for a 2 px outline in
   its own triage colour.
3. The **AI draft summary** keeps its amber edge around the "unverified" notice.
4. The **printed card** keeps a border so its edge survives photocopying.

**Soft elevation.** One shadow definition exists in the app, in `SoftCard`:
`BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20,
offset: Offset(0, 4))`. 29 call sites use it. The S21 action bar and the sticky
save bar use the same shadow inverted (`Offset(0, -4)`).

A tappable `SoftCard` wraps its content in an `InkWell` rather than laying one
over the top. That is not a detail: an overlay would have silently swallowed
taps meant for buttons *inside* a card — S12's call button on a red referral
strip, S21's "ANC contact 3" — and a call button that stops working on a red
triage is the worst bug this restyle could have shipped.

**Typography hierarchy.** Related lines cluster at `AppSpacing.tight` (4 px) and
clusters separate at 16 / 24 px. Name → age → last visit on an S06 card is one
block at 4 px; the pregnancy badge under it is a separate statement at 12 px.

**Icons.** Outlined and rounded throughout. Sweeping `lib` for any glyph that is
not `*_outlined`, `*_rounded`, `*_outline` or `*_none` leaves five names:

| Left as-is | Why |
|---|---|
| `Icons.error`, `Icons.check_circle` | Inside `TriageColors.icon()` — the triage banner, the one place filled icons are specified. |
| `Icons.more_vert`, `Icons.arrow_drop_down` | Three dots and a solid triangle. Neither has an outlined variant; there is no filled/outlined distinction to make. |
| `Icons.network_check` | No outlined variant exists in the Material set. |

**Touch targets.** `AppTheme.minTapTarget` is 48 and is applied through
`FilledButtonTheme`, `OutlinedButtonTheme`, `TextButtonTheme` and
`IconButtonTheme` rather than per call site. `SyncChip` renders a 28 dp pill
inside a 48 dp tap target. `widgets_test.dart` still asserts the stepper's bump
buttons clear 48 dp in both dimensions.

**States.** Loading, empty, error and offline all kept their logic and got the
new styles. `LoadingList` now renders `SoftCard` skeletons with the same
silhouette as the rows that replace them, so the list does not jump when the
data lands. `OfflineBanner`, `PendingDot` and the sync pill all survive,
restyled.

---

## 5. Per-screen summary

### Patient side

| Screen | What changed |
|---|---|
| **S01 splash** | Logo in a 112 dp brand-tint disc, `headlineMedium` title, quieter spinner. |
| **S02 phone** | Centred single purpose: glyph disc, title, subtitle, one field, one `FilledButton`. Demo-OTP banner became `DemoNotice` — a `SoftCard` on `brandGreenTint` with `onTriageGreen` text (green because it says something helpful is switched on, not that something is wrong). |
| **S03 OTP** | Six wide-tracked tabular digits on the card surface, centred sent-to line, one primary button, resend countdown below it. Still one `TextField` with the same auto-submit — the entry behaviour is untouched. |
| **S04 PIN unlock** | Lock glyph in a tint disc; the user's name sits 4 px under the title as one cluster. Keypad keys are filled brand-tint rather than twelve outlined boxes; dots animate and are hollow rings when empty. |
| **S05 set PIN** | Same treatment, gutter-aligned name field, centred error. |
| **S06 family list** | Greeting **"Namaste, ‹name›"** over a quiet "My family" label in the app bar; sync pill beside it; **"I am a health worker" and Settings moved into a single overflow menu**. Patient cards are `SoftCard`s — 52 dp sex avatar, name / age / last-visit clustered at 4 px, pregnancy badge as a `SoftPill` 12 px below. One FAB. |
| **S07 add / edit patient** | Sectioned into Name · Municipality · Allergies. Sex is a `SegmentedControl`. Allergy chips render in the same allergy red they will be read in on S08 and S21. Sticky save bar. |
| **S08 patient home** | Rebuilt for progressive disclosure. Header cluster (name, age · blood group) is the page's own headline, not a card. **Allergy chip row always present** — "No known allergies" in green when empty. **One** primary `FilledButton`, "Share record (QR)", 60 dp in brand blue. Then a row of **four soft tiles**: Timeline, Documents, ‹Pregnancy \| Child health \| Register pregnancy \| Who viewed›, Reminders — the third slot is whichever journey this person is actually on, with the overdue-dose count as a red badge. Pregnancy / delivered cards below. **Who viewed, Printable card and Export PDF moved into a "More" sheet.** |
| **S09 timeline** | BS-month headers as tracked `textSecondary` caps. Items are `SoftCard`s; **only triaged items get a coloured left accent**, and they also carry the triage glyph. Detail sheet regrouped with `SectionHeader`s and `StatTile` vitals. |
| **S10 documents** | Two-column grid of soft tiles with the real thumbnail filling most of the tile, the **type chip floating on the photo**, the title, and the BS date. Upload status keeps its icon and colour. |
| **S12 pregnancy dashboard** | Hero `SoftCard`: week X of 40, risk `SoftPill`, EDD, and a rounded progress bar. Eight-contact stepper — each contact a `SoftCard` with a **semantic dot** (triage colour when done, red when overdue, quiet outline when upcoming), a red left accent when overdue, and the red referral strip with its call button. Birth-plan card and reminders list in `SoftCard`s. |
| **S15 reminders** | `SoftCard` rows: kind, a tinted status pill (sent / failed / scheduled), the message, then date · recipient. Demo-SMS hint restyled green. |
| **S16 audit** | `SoftCard` rows, one 4 px cluster per entry: what happened, who, where, when. |
| **S17 sync** | Status `SoftCard` with the headline answer, last-sync line, an amber tinted block for stuck uploads, and "Sync now". Rejected ops get a **red left accent** — the one list in the app where a row is a problem to resolve. |
| **S23 settings** | Four `FormSection`s: Language (a `SegmentedControl`), Server (demo switch + URL + test buttons), Versions, Integrations. Integration rows became `SoftCard`s with a "not connected" pill; the disabled Connect button is untouched — **no mock success states**. |
| **Child health** | Header card, section header, dose rows as `SoftCard`s with a red left accent when overdue. Growth chart in a `SoftCard`. |

### Provider side

| Screen | What changed |
|---|---|
| **S18 activation** | One field, one primary button, glyph disc. **Success state added**: when the phone is already activated, a `brandGreenTint` `SoftCard` names the facility. |
| **S19 provider home** | Facility name in the app bar. **One large brand-blue "Scan patient QR" tile** with the QR-scanner glyph. Dashboard as an outlined button beneath it. "Recent patients" as `SoftCard`s — initial avatar, name, **age**, allergies in red with a warning glyph, pregnancy pill. My family and Settings moved to an overflow menu. |
| **S20 scanner** | **Full-bleed camera** behind a transparent app bar. A **rounded viewfinder** painted as a single window cut out of a dark scrim (one `CustomPainter`, so no seams over a moving preview). Hint on a dark pill; **"Enter code instead" as a text button directly under it**. The A.7 PIN prompt became a **bottom sheet** instead of a dialog. |
| **S21 provider summary** | **Allergy chip row pinned** in a `SliverPersistentHeader` — scrolling to the medicines cannot take the one fact off screen that decides whether they are safe. The row scrolls sideways rather than wrapping, so nothing is ever clipped. Then the identity cluster and **three `SoftCard`s**: Active problems (pills), Current medicines (**Nepali instruction in `textSecondary` on its own line under each drug**), Last vitals as a **2-column grid of number tiles** with tabular figures. Pregnancy card when active. **Bottom action bar**: "Add visit" primary, "Capture paper" / "Register pregnancy" outlined. **Read-only mode removes the action bar entirely** and shows the banner outside the scroll view. |
| **S22 add visit** | Seven `FormSection`s — Complaint · Vitals · Diagnoses · Medicines · Advice · Follow-up · Referral. **Vitals as large numeric steppers in a two-column grid** (new `NumberStepperLayout.stacked`). Medicine rows are `SoftCard`s; the six frequencies are a **segmented control**. **Sticky save bar.** |
| **S13 ANC checklist** | Findings grouped per the contact's checklist in a `FormSection`, with the off-checklist fields still folded into "More fields". Danger signs are **large toggles**, and a selected **red-level tile takes a `triageRed` 2 px outline**. The **triage banner is full-width and pinned above the Save button** — it recomputes on every tick, and on a form this long it is only useful if it can be seen while ticking. The **call button sits beside Save**, coloured by level, so the number is one tap from anywhere in the form; the referral card (facility picker, reason, map link) is the first thing in the body. |
| **S14 delivery** | Three `FormSection`s plus complications. Place / mode / outcome / baby sex became `SegmentedControl`s. Sticky save bar. |
| **Tier 2 dashboard** | Six `SoftCard` tiles, `displaySmall` count in the bucket's colour over a quiet label. Bucket lists are `SoftCard` rows with the triage dot. |
| **Facility map** | Markers use brand blue / triage red with a tokenised shadow. Facility list rows are `SoftCard`s; the chosen one takes a brand-blue left accent instead of a full border. |

---

## 6. Screens and files left alone, and why

| File | Why |
|---|---|
| `features/export/patient_pdf.dart` | It builds a **PDF document**, not a Flutter widget tree. Its colours are `PdfColors.*` from the `pdf` package — a different type in a different renderer. Restyling it is a separate job with its own constraints (print contrast, greyscale fallback). |
| `features/export/patient_pdf_service.dart`, `export_pdf_button.dart` | Service and a single themed button; the button already picks up the new `OutlinedButtonTheme`. |
| `features/auth/auth_controller.dart`, `documents/ai_summary.dart`, `timeline/local_timeline.dart`, `reminders/medicine_notifications.dart`, `medicine_speech.dart`, `shared/voice/speech_locale.dart` | No UI. |
| `features/reminders/prescription_actions.dart`, `shared/voice/voice_note_button.dart`, `shared/widgets/bs_date_field.dart` | Small controls that render entirely through themed widgets (`OutlinedButton`, `IconButton`, `InputDecorator`), so they restyled themselves. Their icons were swept to outlined variants. |
| `lib/router.dart`, `lib/app.dart` | `app.dart` still hands `AppTheme.light()` / `.dark()` to `MaterialApp.router`; nothing else needed to change. The router is untouched. |

**Not rendered, and flagged:** spec S19 wants `providerAccessUntil`
("Access until {time}") on each recent-patient row. The l10n key exists, but
`access_until` lives on the Drift row and is **not carried on the `Patient`
model**, so the UI layer cannot read it. Surfacing it needs a model or DAO
change, which this brief explicitly forbids. The row therefore shows name, age,
allergies and pregnancy. One added field on `Patient` plus its mapper would
close it.

---

## 7. Verification

| Gate | Before | After |
|---|---|---|
| `flutter analyze` | No issues found | **No issues found** |
| `flutter test` | 533 passing | **629 passing** (533 kept + 96 new) |
| `flutter build apk --debug` | — | **✓ Built `build/app/outputs/flutter-apk/app-debug.apk`** |

No test was removed, so the count could only go up.

No device was used at any point: no `adb`, no `flutter run`, no emulator. One
build failed part-way with a corrupted Kotlin incremental-compile cache under
`build/speech_to_text/kotlin` — an artefact of a build process being killed, not
of any change here. Deleting that cache directory and rebuilding succeeded.

### Tests changed rather than behaviour

Two assertions in `test/features/widgets_test.dart` failed **only** because of a
style change, and were updated per the brief's rule 5 — the behaviour they guard
is unchanged:

1. `NumberStepper` finders moved from `Icons.add` / `Icons.remove` to
   `Icons.add_rounded` / `Icons.remove_rounded`, because the design rule is
   outlined-or-rounded icons only. The tests still walk the BP stepper down to
   exactly 150 and still assert the 48 dp tap target.
2. The triage banner's reason-line colour assertion moved from
   `TriageColors.red` to `TriageColors.ink('red')`. The test's stated
   intent — *"they have to carry the banner's colour, not the page's"* — is
   preserved and now also asserted explicitly with an `isNot(…onSurface)`
   check. The comment records why the darker ink is correct (4.41:1 → 7.60:1).

No test was weakened or deleted.

### New tests

`test/features/layout_test.dart` — **96 tests**: 24 screens × 2 locales × 2
phone sizes. Every restyled screen that can be pumped without a platform channel
is rendered in **both locales** at **360×780 and 412×915** against a seeded
record — a pregnancy with eight contacts, a red-triaged contact with a referral,
a prescription with a long Devanagari instruction, three allergies — and the
test fails on any `RenderFlex overflowed`.

Overflow is captured through `FlutterError.onError`, and the failure message
carries the render object's `debugCreator` chain, so it names the widget and the
file rather than only the pixel count. Anything that is *not* an overflow is
passed through to the normal reporter rather than swallowed.

Screens covered: S02–S12, S13 (twice — routine **and** red-with-referral, which
are different layouts), S14–S19, S21, S22, S23, child health, Tier 2 dashboard.

It earned its keep immediately. It found three real defects the eye would not
have caught until a phone was in hand:

1. **S08, S12, S21** — `Row(children: [Text(label), BsDateText(value)])` with no
   `Flexible` on either side overflowed by up to 254 px. This is why `FactRow`
   exists, and the same shape is now fixed in all three places.
2. **Tier 2 dashboard** — the tile grid's `childAspectRatio: 1.25` clipped the
   second line of a bucket label by 6.8 px at 360 dp. Now 1.05.
3. **S21's pinned allergy header** — a fixed-height sliver header cannot hold a
   wrapping `Wrap`, so `AllergyChipRow` gained a `singleLine` mode that scrolls
   sideways. Allergies being silently clipped would have been the worst possible
   failure mode.

Not covered, and why: **S01 splash** (initialises the notifications plugin),
**S20 scanner** (needs a camera), **the facility map** (needs map tiles) and
**the printed-card screen** (needs a live grant — the `PrintedCard` widget
itself is already covered by `printed_card_test.dart`).

One note on the test's own shape: it deliberately does **not** close its
in-memory database in a `tearDown`, matching `grant_sections_test.dart` and
`printed_card_test.dart`. Closing a Drift database waits for its query streams
to finish cancelling, and that completes on a zero-duration timer; inside
`testWidgets` the clock is fake, so once the body returns nothing advances it
and the close never completes. The comment in the file records this so the next
person does not "fix" it back.

### Two pre-existing flakes, neither caused by this work

Both are timing-sensitive tests of the outbox's ordering contract, and both
surfaced only on a heavily loaded machine — the 96 new widget tests raise CPU
contention for everything running beside them.

| Test | Seen | Verified |
|---|---|---|
| `sync_engine_test.dart: push more than one batch is pushed in created_at order` | once | Passed in isolation and on the next full run. Already investigated in `docs/FLAKY_TEST.md`. |
| `outbox_test.dart: ordering ops queued in the same millisecond keep their insertion order` | once | Passed 3 / 3 in isolation and on the next full run (`+629: All tests passed!`). |

They share a root cause worth recording even though fixing it is out of scope
here. `Outbox.enqueue` reads `max(created_at)` and then inserts, and those two
statements are not one transaction. Under load, two enqueues can read the same
maximum and write the same timestamp, and `ORDER BY created_at` is then free to
return them in either order — which is exactly what both tests assert against.
Making the read and the insert atomic (or using a monotonic sequence column)
would close it, but that is a **behaviour change** to the sync path, which this
brief explicitly excludes.

---

## 8. Device verification TODO

**Done — 20 September 2026.** The patient side of this list has since been
verified on a POCO M2102J20SI (Android 13, 1080×2400), in both locales, on a
release build. The screenshots live in `docs/screens/` as
`enduser_<screen>_<en|ne>.png` rather than under the `ui_after_` names sketched
below, and the findings — eleven defects found and fixed, one open camera
failure that belongs to the handset — are written up in
`docs/EndUser_Verification_Report.docx`. The provider side of the list below is
still outstanding.

The original plan, kept for the provider pass:

```bash
flutter devices                 # confirm exactly one physical handset
flutter run --release
```

Take each screenshot in **both locales** (toggle in S23) and save as
`ui_after_<screen>_<locale>.png` under `docs/screens/`.

**Patient side**

- [ ] `ui_after_s01_splash_en.png` / `_ne.png`
- [ ] `ui_after_s02_phone_en.png` / `_ne.png` — with the demo-OTP banner visible
- [ ] `ui_after_s03_otp_en.png` / `_ne.png`
- [ ] `ui_after_s04_pin_en.png` / `_ne.png`
- [ ] `ui_after_s05_setpin_en.png` / `_ne.png`
- [ ] `ui_after_s06_family_en.png` / `_ne.png` — greeting, a pregnant badge, the overflow menu open
- [ ] `ui_after_s07_patientform_en.png` / `_ne.png` — with two allergy chips entered
- [ ] `ui_after_s08_home_en.png` / `_ne.png` — allergy row, four tiles, More sheet open
- [ ] `ui_after_s09_timeline_en.png` / `_ne.png` — including a red-accented item
- [ ] `ui_after_s10_documents_en.png` / `_ne.png` — **with real photographs**, which is the one thing a test cannot check
- [ ] `ui_after_s12_pregnancy_en.png` / `_ne.png`
- [ ] `ui_after_s15_reminders_en.png` / `_ne.png`
- [ ] `ui_after_s16_audit_en.png` / `_ne.png`
- [ ] `ui_after_s17_sync_en.png` / `_ne.png` — once with a rejected op
- [ ] `ui_after_s23_settings_en.png` / `_ne.png`
- [ ] `ui_after_child_health_en.png` / `_ne.png`

**Provider side**

- [ ] `ui_after_s18_activate_en.png` / `_ne.png` — including the green success state
- [ ] `ui_after_s19_providerhome_en.png` / `_ne.png`
- [ ] `ui_after_s20_scanner_en.png` / `_ne.png` — **the viewfinder over a live preview**, and the PIN bottom sheet
- [ ] `ui_after_s21_summary_en.png` / `_ne.png` — scrolled down, to prove the allergy header stays pinned
- [ ] `ui_after_s21_summary_readonly_en.png` — no action bar, banner visible
- [ ] `ui_after_s22_visit_en.png` / `_ne.png` — the vitals grid and the sticky save bar
- [ ] `ui_after_s13_anc_green_en.png` / `_ne.png`
- [ ] `ui_after_s13_anc_red_en.png` / `_ne.png` — **the pinned banner plus the call button beside Save**
- [ ] `ui_after_s14_delivery_en.png` / `_ne.png`
- [ ] `ui_after_dashboard_en.png` / `_ne.png`
- [ ] `ui_after_facility_map_en.png` / `_ne.png`

**Checks that need eyes and a phone, not a test**

- [ ] Devanagari renders with correct conjuncts and matras at every size on a
      real Android font stack — the widget tests prove it *fits*, not that it is
      *shaped* correctly.
- [ ] The card shadow is visible but not muddy on an OLED panel at low
      brightness.
- [ ] The triage banner, the allergy chips and the danger-sign outlines are
      legible **in direct sunlight**, which is where this app is used.
- [ ] The S20 viewfinder cut-out lines up with what the scanner actually reads.
- [ ] Dark mode on every screen (the theme builds one, and nothing in this pass
      has been seen in it).
- [ ] Every 48 dp target is comfortably hittable with a thumb, especially the
      S13 danger-sign toggles and the S22 stepper buttons.
