# Mero Swasthya — two-minute demo script

For the release build with `--dart-define=MOCK_API=true`. Everything below runs
against the in-app mock: no backend, no SIM, no second phone required.

**Constants you will need**

| Thing | Value |
|---|---|
| Demo OTP | `123456` (any phone number) |
| PIN | any 4 digits — use `1234` |
| Provider invite code | `HA-GHORAHI-01` → "Ghorahi Health Post" |
| FCHV invite code | `FCHV-W5-01` |
| Seeded patients | Sita Chaudhary (pregnant, week 30, allergy **sulpha**), Ram Bahadur Chaudhary (diabetes, allergy **penicillin**) |
| Patient PIN for a printed card | the PIN set at S05 — `1234` in this script |
| Health-post caseload (Tier 2) | Gita Tharu (week 10), Maya B.K. (week 37), Parbati Chaudhary (week 22, one contact missed, amber) |
| Child (Tier 3) | Aarav Chaudhary, 3 years, 16 of 18 doses given, **2 overdue** (MR dose 2, TCV), three weights |

**Where things are (the navigation changed — see `UX_AUDIT.md`)**

Both roles are now bottom tabs, labelled with words, not icons. Nothing is
behind a `⋮` any more.

| Role | Tabs | What used to be where |
|---|---|---|
| Patient | **Home** · **Records** · **Documents** · **More** | Home is the family strip *and* the open record on one screen; Records is the timeline; More holds Who viewed my record, Printable card, Export PDF, Reminders, Child health, Register pregnancy, Edit details, "I am a health worker", Sync and **Settings (language)** |
| Health worker | **Scan** · **Patients** · **More** | Scan is the landing tab, so the camera is up the moment the app opens; Patients is the old recent-patients list; More holds the Health post dashboard, Sync, My family and Settings |

Two things the demo now leans on:

* **Switching family member never leaves the record.** Tap a face in the strip
  along the top of Home and the card underneath changes. There is no separate
  family list screen any more.
* **The sync pill says the time in words.** Under the app bar on Home and on
  Patients: *"Synced 2 min ago"*, *"3 changes waiting"*, *"Offline"*. Tap it for
  the Sync screen. The old cloud glyph in other app bars now carries a word too.

**First run shows three coach marks** on the patient side ("This is your
family", "Share your record with a QR", "Everything else is under More") and two
on the provider side ("Health workers scan here", "Everyone you scanned today").
They are shown once per install. **Decide before you start** whether you want
them: after `pm clear` they will appear, and they are a good thirty seconds of
story — or tap **Skip** and carry on.

---

## Pre-demo checklist

Do all of this **before** the audience is watching. It takes about five minutes.

- [ ] **Charge the phone** past 60%, and plug it in if you can. Set
      `adb shell svc power stayon true` so the screen never sleeps mid-sentence.
- [ ] **Fresh reinstall.** `adb install -r build/MeroSwasthya-demo-<abi>.apk`
      then `adb shell pm clear com.meroswasthya.app`. The first-run flow is part
      of the story, and a stale database will show yesterday's test visits.
- [ ] **Grant the camera** up front so no permission dialog interrupts you:
      `adb shell pm grant com.meroswasthya.app android.permission.CAMERA`.
- [ ] **Lock the rotation** to portrait. Every screen is designed for it.
- [ ] **Rehearse one real camera scan.** The one step never exercised end to
      end — see "Known risk" below. Do it once, with the actual QR on the actual
      laptop screen, at the actual brightness.
- [ ] **Open the camera app once** and take any photo, to be sure this phone's
      camera works at all before you rely on Capture paper.
- [ ] **Airplane-mode test.** Toggle it on, add a visit, watch the pending cloud
      icon, toggle it off, watch the chip go green. If this does not work,
      something is wrong with the build — find out now, not on stage.
- [ ] **Nepali locale.** **More → Settings** (it is a named row now, subtitled
      "Language" — no longer behind a `⋮`) and flip to नेपाली once, then back to
      English. Confirms the language toggle, warms the font cache, and shows you
      where the tab bar's Nepali labels sit.
- [ ] **Walk the four patient tabs and the three provider tabs once** so you
      know which is where before the room is watching. Press Android back on a
      non-Home tab and watch it return to Home rather than leaving the app.
- [ ] **Laptop QR image ready.** Open the patient's QR full-screen on the laptop
      in advance if you plan to use the laptop-screen fallback (below). White
      background, brightness up.

### If you are showing the Tier 2 segment, also:

- [ ] **Grant notifications and fire one for real.** **More → Settings** →
      **Test a medicine reminder** → Allow. A reminder appears about thirty seconds
      later. This is the only way to find out whether *this* phone will show
      one, and finding out on stage is too late. (`POST_NOTIFICATIONS` is an
      Android 13+ runtime permission; you can pre-grant it with
      `adb shell pm grant com.meroswasthya.app android.permission.POST_NOTIFICATIONS`,
      but do the live test anyway.)
- [ ] **Check for a Nepali TTS voice.** **Records** tab → a visit → its
      medicine row → the **speaker** icon. If you see *"No Nepali voice on this phone — read in
      English"*, install one: Settings → Additional settings → Language & input
      → Text-to-speech → install the Nepali voice data. The app does not crash
      without it, but the Nepali line is half the point.
- [ ] **Internet on for the map.** OpenStreetMap tiles are fetched live and
      nothing is cached. Without a connection the facility markers and distances
      still show over a plain background with a note — which is a fine thing to
      demonstrate deliberately, and a bad thing to discover by accident.

### If you are showing the Tier 3 segment, also:

- [ ] **Check for a Nepali speech recogniser.** Open any ANC contact, scroll to
      **Notes** — it now carries a line telling the worker to tap the microphone
      to dictate in Nepali — and look for the microphone. If it is missing, this phone has
      no recogniser at all and the voice beat is off. If it is there, tap it
      once: *"No Nepali dictation on this phone — using English"* means you
      will get English words back. Install the Nepali voice from Settings →
      Additional settings → Language & input → Google Voice Typing → Offline
      speech recognition.
- [ ] **Confirm the PDF font is in the build.** Select Ram in the family strip,
      then **More → Export PDF**, once.
      If the sheet appears with a `.pdf` filename, the Devanagari font is
      bundled and the document built. (If the font were missing the export
      would fail outright with "Could not build the PDF" — it cannot fail
      silently.)
- [ ] **Know that the print *preview* lies.** Android's print dialog renders a
      tiny thumbnail and draws small text as black blocks. The PDF itself is
      fine — open it in a real viewer if you want to show it, or just share the
      file. Do not panic at the preview on stage.
- [ ] **Grant the microphone** up front so no permission dialog interrupts:
      `adb shell pm grant com.meroswasthya.app android.permission.RECORD_AUDIO`.
- [ ] **Silence the phone.** Notifications steal taps during a demo —
      `adb shell settings put global zen_mode 1`, or just turn on Do Not
      Disturb.

---

## The demo

### Part 1 — the patient (about 50 seconds)

**Say:** *"This is a health record that belongs to the patient, not to a
hospital. It works with no signal. Let me show you from a brand-new phone."*

1. **S02 — phone number.** Type `9801000001`. Point out the number is
   normalised to `+977…`.
   **Say:** *"Phone and a one-time code. No email, no password."*
2. **S03 — OTP.** Type `123456`.
   **Say:** *"In the demo the code is fixed. In production it is an SMS that
   reaches a feature phone."*
3. **S05 — create PIN.** Name `Sita Chaudhary`, PIN `1234` twice.
   **Say:** *"The PIN unlocks the record every day, offline. The database never
   leaves the phone unless the patient shares it."*
4. **Home.** The app lands on the **Home** tab: Ram and Sita as faces in the
   strip across the top, one of them already open underneath, and the sync pill
   reading **"Synced just now"**.
   *(If the coach marks appear, use them: three cards, tap through or Skip.)*
   **Say:** *"One phone holds the whole family, and the record is the home
   screen — not a list you have to get past. This is a first sync; the record
   came down from the server complete, and the phone says so in words."*
5. **Tap Sita's face in the strip.** Her card opens in place — no navigation.
   Point at the red **⚠ sulpha** chip, then at **"Share record (QR)"**, the one
   blue button on the screen.
   **Say:** *"Allergies are always at the top, in red. A health worker should
   never have to go looking for that. And the one thing this app is for —
   handing your record to a health worker — is the only primary button on the
   screen."*
   Point at her **"Pregnant · week 30"** card below the tiles.
6. **Tap the pregnancy card → S12.**
   **Say:** *"Eight antenatal contacts on the national schedule. Three are done,
   contact four is due today — and the dates are Bikram Sambat, because that is
   the calendar the register is kept in."*

### Part 2 — the health worker (about 60 seconds)

7. **More → "I am a health worker" → S18.** Type `HA-GHORAHI-01` → Activate.
   **Say:** *"The same app becomes the health worker's app with an invite code —
   and it is a row that says so, not a three-dot menu. She keeps her own family
   record on the same phone."*
   Land on the provider shell, **Scan** tab, camera already up, under
   **Ghorahi Health Post**.
   *(Two provider coach marks appear on a first run — tap through or Skip.)*
8. **The QR.** **More → My family** → Sita in the strip →
   **Share record (QR)**.
   **Say:** *"The patient shows this. It is a ten-minute, single-use grant — the
   patient is handing over access, deliberately, and it expires by itself."*
   Point at the countdown. *(The sheet itself is unchanged: both QR modes, the
   countdown, the revoke button and the section chips all work exactly as they
   did.)*
9. **Scan it.** **More → Health worker mode** → the **Scan** tab is already the
   camera. Hold the phone over the QR.
   **Say:** *"No taps. The app opens on the scanner, because that is why the
   phone came out of the pocket."*
   - *One phone:* put the QR on a laptop screen and scan that (see fallbacks).
   - *If the camera will not bite:* tap **"Enter code instead"**, paste or type
     the `SWC1:…` payload, **Open record**. Same code path, same validation.
10. **S21 — the summary.**
    **Say:** *"Ten seconds to everything that matters: allergies pinned in red,
    the active pregnancy, last vitals."*
    Point at the bottom bar: a labelled **"More actions"** row — Capture paper,
    Register pregnancy, Timeline — over the two buttons she presses all day,
    **ANC contact 4** and **Add visit**.
    **Say:** *"The two things she does most are always in the same place, and
    the rest are named rather than hidden under a dot menu. On a long record she
    used to have to scroll past the medicines to find the antenatal contact."*
11. **Add a visit (S22).** Pick a complaint and a diagnosis from the picklists.
    Point at the short grey line under each block heading.
    **Say:** *"Every block says what it is for, because the first person to use
    this will be learning it with a patient in front of them."*
    **Say:** *"Sixty seconds, all taps, no typing — because this has to work
    faster than the paper register it replaces."*

### Part 3 — the point (about 20 seconds)

12. **Before saving, turn on airplane mode** (or have it on already).
    Save the visit. The row shows the **pending cloud** icon, and the pill on the
    **Patients** tab reads **"1 change waiting"**.
    **Say:** *"No signal. The visit is saved on the phone and queued — and the
    phone tells her so in a sentence, not a coloured dot."*
13. **Turn airplane mode off.** Within a few seconds the pill reads
    **"Synced just now"** and the pending icon clears.
    **Say:** *"Signal comes back and it syncs itself. The health worker never
    thinks about it."*
14. **More → My family → Sita → the Records tab.** The new visit is there,
    grouped under its Bikram Sambat month.
    **Say:** *"And it is in the patient's record, on the patient's phone, in the
    patient's calendar."*

**Close:** *"Patient-owned, offline-first, and the danger-sign triage cites the
national protocol. Everything you just saw ran with no backend at all."*

### If you have thirty seconds more — the triage

Open **S13 — ANC contact 4**, enter BP **150 / 95**, tick **severe headache**.
The banner turns **red** and names the rule, a referral card appears with the
nearest birthing centre and a **Call** button.
**Say:** *"The rules come from a table the ministry can update, and the app tells
the worker which rule fired — it does not just say 'bad'."*

---

## Optional Tier 2 segment (about 60 seconds)

Run this after Part 3, only if the room is still with you. Five beats, none of
which needs a second phone.

**Say:** *"Four things we added once the core worked. Each one is about the
person who is not holding the phone."*

1. **Printed card + PIN (about 20 s).** Sita in the family strip →
   **More → Printable card** (two taps; it used to be three, behind a "More"
   text button at the bottom of a scroll).
   A year-long read-only QR with her name, date of birth in both calendars,
   blood group, and — in Nepali and English — *"Ask the patient for their
   4-digit PIN"*. Tap **Share / save image**: it is a PNG, so it goes to a print
   shop.
   Now redeem it: **More → Health worker mode** → the **Scan** tab →
   *Enter code instead* → the card's payload → **Open record**. The app asks for **the patient's PIN**. Type a
   wrong one first — *"That PIN was not accepted"* — then `1234`.
   S21 opens under a **"Read-only access"** banner with **no Add visit, no ANC
   contact and no Register pregnancy** — only **Timeline** is left in the
   "More actions" row, so the record can still be read.
   **Say:** *"A card on a wall is not a credential. The paper gets you as far as
   the door; the patient's four digits get you in, and only to read."*

2. **Delivery (about 10 s).** Sita's pregnancy → **Record delivery** → place,
   mode, outcome, baby weight and sex, complication chips → Save. The pregnancy
   card is replaced by a green **Delivered** card. Then show
   **More → Register pregnancy**, which is still listed.
   **Say:** *"And the next pregnancy is still one row away. Before this pass a
   delivered pregnancy took 'Register pregnancy' off her phone entirely."*

3. **AI draft summary (about 15 s).** Ram in the family strip → the
   **Documents** tab → **Bharatpur Hospital discharge sheet** → **Draft summary (AI)**. It reads *"Reading the
   document…"*, then a bilingual summary appears **under an amber
   "AI-generated, unverified — confirm with a health worker" label in both
   languages**, listing two medicines and their doses.
   **Say:** *"A dense hospital printout, read back in Nepali. Labelled as a
   draft, because a machine reading a dose is not a clinician reading a dose."*

4. **Nearest facility map (about 10 s).** From the red ANC contact's referral
   card, or the birth plan, tap **Show on map**. Four facilities, nearest first
   with distances, tap a marker to centre it, **Call** on each row.
   Turn on airplane mode: the tiles go, the markers and distances stay, and an
   amber note says *"Map tiles need internet"*.
   **Say:** *"The map is a convenience. Knowing which birthing centre is
   nineteen kilometres away is not, so that part works with the radio off."*

5. **Medicine reminder (about 5 s).** Ram → the **Records** tab → the visit →
   the medicine row. Tap the **speaker** to hear the drug and the Nepali instruction read
   aloud; tap **Set reminders** and it confirms *"13 reminders set for the next
   7 days"* — 08:00 and 20:00 for a BD prescription, with the Nepali instruction
   in the notification body.
   **Say:** *"Most people who are handed four tablets a day cannot read the
   label. So the phone says it, and then keeps saying it."*

**Optional close:** *"Health post dashboard"* — provider **More → Health post
dashboard** counts the caseload cached on this phone: pregnancies by trimester, who has been missed,
who was flagged red or amber this week, deliveries this month. Every tile opens
the list of women behind it. It is computed locally, so it works in a building
with no connection — which is where the question usually gets asked.

---

## Optional Tier 3 segment (about 60 seconds)

The roadmap tier. Run it only if the room has asked "what's next" — it is four
beats and each one answers a different objection.

**Say:** *"Four things on the roadmap, all built, none of them requiring a
government API we do not have."*

1. **Child health (about 20 s).** **Aarav Chaudhary**, 3 years, in the family
   strip → the **Child health** tile in the 2×2 grid, which already carries a
   red **2** badge. *(It is also a named row in **More**, for whenever the
   contextual tile is showing something else.)*
   Open it: the national EPI schedule, one row per dose, green for given, a red
   outline for the two he has missed — **Measles-Rubella dose 2** and
   **Typhoid conjugate**, both due at 15 months. Dates in Bikram Sambat.
   Scroll to **Growth**: his three weights plotted over the WHO median and
   ±2 SD band.
   **Say:** *"Every dose exists as a row from the day he is registered, so the
   question 'what is this child missing' is answered by looking rather than by
   remembering."*
   Point at the two amber lines — *"Schedule checked against published
   sources on 19 Sep 2026, not against the official Ministry list"* and
   *"WHO Child Growth Standards, weight-for-age — weight alone cannot tell a
   short child from a thin one"*.
   **Say:** *"And it tells you exactly how far it has been checked. We
   cross-checked the schedule against three published sources and it caught a
   real error — we had fIPV at 6 and 14 weeks when Nepal gives it at 14 weeks
   and 9 months. It still needs somebody with the Ministry's own list. The
   growth band used to be a drawn-in curve; it is now the WHO tables, parsed
   straight out of WHO's own published sheets — and checking that caught a
   second error, because the curve it replaced was out by a kilo and a half at
   a child's first birthday, in both directions."*
   *(If asked: 18 doses, 7 visits — birth, 6, 10, 14 weeks, 9, 12, 15 months.)*

2. **Consent, section by section (about 15 s).** Sita in the family strip →
   **Share record (QR)** on Home (one tap now, not two). Above the QR there is now a **"What to share"** row. Tap
   **Pregnancy** — the QR regenerates, because the token carries the consent.
   Redeem it on the provider side. S21 opens with a line at the top reading
   **"Patient shared: Pregnancy"**, the pregnancy card is there, and the
   medicines, vitals and documents are simply gone.
   **Say:** *"She can hand over her pregnancy without handing over her
   diabetes. The filtering happens on the server, not in the app — otherwise it
   would not be consent."*
   Point at the allergy chip, still red, still there.
   **Say:** *"Allergies always travel. A consent feature that could hide a
   sulpha allergy would be a consent feature that kills somebody."*

3. **Voice note (about 10 s).** Open any ANC contact → **Notes** → tap the
   **microphone** → say a sentence in Nepali → it appears in the field, and you
   can edit it before saving.
   **Say:** *"Dictated, then read back before it is saved. Nothing reaches a
   medical record that the person who said it has not had a chance to correct."*

4. **PDF (about 15 s).** Ram in the strip → **More → Export PDF** → the share
   sheet appears with a real file. Open it in a PDF viewer if one is handy.
   **Say:** *"The record belongs to the patient, so it has to be able to leave
   the app. Allergies boxed in red at the top, medicines with the Nepali
   instruction, the immunisation card if it is a child, dates in both
   calendars. That sheet works in a referral hospital with no network, no
   account and no copy of this software."*

**Optional close — the honest slide.** **More → Settings** → scroll to
**Integrations**.
Three rows: National ID verification, HMIS/DHIS2 export, Provider council
verification. Each says **"Not connected — requires government API access"**,
explains in both languages what it would do and what the app does instead, and
the Connect button is greyed out.
**Say:** *"These are the three integrations this needs to be real, and we do not
have the API access for any of them. We would rather show you a disabled button
than a fake green tick."*

---

## Fallbacks, in the order you should reach for them

1. **Camera on a laptop screen.** Open the QR PNG full-screen, brightness up.
   Works, but a glossy screen and a phone's autofocus can fight each other.
2. **"Enter code instead" on the Scan tab.** The link sits under the camera
   preview, exactly where it always did. It
   accepts the whole `SWC1:…` payload and goes through exactly the same redeem
   path — same prefix check, same rejection toast. This is the reliable one.
   To get the payload without a camera:
   `adb exec-out screencap -p > s.png` and decode it, or read it off the share
   sheet.
3. **Skip the scan.** The provider's **Patients** tab keeps anyone already
   redeemed for 24 hours, so a scan done before the demo still opens S21 in two
   taps — Patients, then the card.

## Known risk

**No QR has ever been read optically.** The scanner opens and previews on both
phones tested, and the redeem path is exercised every other way — manual code,
expired grant, revoked grant, foreign code — but never through the lens.
Rehearse it once before the demo; if it misbehaves, use the manual-code
fallback, which is indistinguishable to the audience.

**If you are demoing on a Xiaomi/MIUI phone**, check the system camera first.
On the POCO X3 Pro used for testing, MIUI's own camera app crashes
("Camera keeps stopping"), which breaks **Capture paper** — the app survives it
cleanly, but the paper-capture beat of the demo is gone. Use a different phone
for that step, or drop it.

## What not to demo

Everything in the app now has a screen behind it. Three things still have sharp
edges — the first two in `TIER2_HANDOFF.md`, the third in `TIER3_HANDOFF.md`:

- **Document capture on a MIUI phone** (the system camera crashes — Xiaomi's
  bug, not ours).
- **Optical QR scanning**, which has still never been done through the lens.
- **Nepali dictation actually being heard.** The microphone appears and the
  permission is granted, but nobody has spoken Nepali at it and read the
  transcript back. Rehearse it once.

The Tier 2 segment is optional on purpose. If Part 1–3 has already made the
point, stop there: the core story is offline-first and patient-owned, and five
more features will not make it truer.
