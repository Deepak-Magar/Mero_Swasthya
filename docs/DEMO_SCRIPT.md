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
- [ ] **Nepali locale.** Open Settings and flip to नेपाली once, then back to
      English. Confirms the language toggle and warms the font cache.
- [ ] **Laptop QR image ready.** Open the patient's QR full-screen on the laptop
      in advance if you plan to use the laptop-screen fallback (below). White
      background, brightness up.

### If you are showing the Tier 2 segment, also:

- [ ] **Grant notifications and fire one for real.** Settings → **Test a
      medicine reminder** → Allow. A reminder appears about thirty seconds
      later. This is the only way to find out whether *this* phone will show
      one, and finding out on stage is too late. (`POST_NOTIFICATIONS` is an
      Android 13+ runtime permission; you can pre-grant it with
      `adb shell pm grant com.meroswasthya.app android.permission.POST_NOTIFICATIONS`,
      but do the live test anyway.)
- [ ] **Check for a Nepali TTS voice.** Open a visit's medicine row and tap the
      **speaker** icon. If you see *"No Nepali voice on this phone — read in
      English"*, install one: Settings → Additional settings → Language & input
      → Text-to-speech → install the Nepali voice data. The app does not crash
      without it, but the Nepali line is half the point.
- [ ] **Internet on for the map.** OpenStreetMap tiles are fetched live and
      nothing is cached. Without a connection the facility markers and distances
      still show over a plain background with a note — which is a fine thing to
      demonstrate deliberately, and a bad thing to discover by accident.

### If you are showing the Tier 3 segment, also:

- [ ] **Check for a Nepali speech recogniser.** Open any ANC contact, scroll to
      **Notes**, and look for the microphone. If it is missing, this phone has
      no recogniser at all and the voice beat is off. If it is there, tap it
      once: *"No Nepali dictation on this phone — using English"* means you
      will get English words back. Install the Nepali voice from Settings →
      Additional settings → Language & input → Google Voice Typing → Offline
      speech recognition.
- [ ] **Confirm the PDF font is in the build.** Tap **Export PDF** on Ram once.
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
4. **S06 — My family.** Ram and Sita appear, already carrying history, with the
   sync chip green.
   **Say:** *"One phone can hold the whole family. This is a first sync — the
   record came down from the server complete."*
   Point at Sita's **"Pregnant · week 30"** chip.
5. **Tap Sita → S08.** Point at the red **⚠ sulpha** chip.
   **Say:** *"Allergies are always at the top, in red. A health worker should
   never have to go looking for that."*
6. **Tap the pregnancy card → S12.**
   **Say:** *"Eight antenatal contacts on the national schedule. Three are done,
   contact four is due today — and the dates are Bikram Sambat, because that is
   the calendar the register is kept in."*

### Part 2 — the health worker (about 60 seconds)

7. **Back to S06 → the badge icon → S18.** Type `HA-GHORAHI-01` → Activate.
   **Say:** *"The same app becomes the health worker's app with an invite code.
   She keeps her own family record on the same phone."*
   Land on **S19 — Ghorahi Health Post**.
8. **The QR.** Go to My family → Sita → **Share record (QR)**.
   **Say:** *"The patient shows this. It is a ten-minute, single-use grant — the
   patient is handing over access, deliberately, and it expires by itself."*
   Point at the countdown.
9. **Scan it.** S19 → **Scan patient QR** → hold the phone over the QR.
   - *One phone:* put the QR on a laptop screen and scan that (see fallbacks).
   - *If the camera will not bite:* tap **"Enter code instead"**, paste or type
     the `SWC1:…` payload, **Open record**. Same code path, same validation.
10. **S21 — the summary.**
    **Say:** *"Ten seconds to everything that matters: allergies in red, the
    active pregnancy, last vitals."*
11. **Add a visit (S22).** Pick a complaint and a diagnosis from the picklists.
    **Say:** *"Sixty seconds, all taps, no typing — because this has to work
    faster than the paper register it replaces."*

### Part 3 — the point (about 20 seconds)

12. **Before saving, turn on airplane mode** (or have it on already).
    Save the visit. The row shows the **pending cloud** icon.
    **Say:** *"No signal. The visit is saved on the phone and queued."*
13. **Turn airplane mode off.** Within a few seconds the chip goes green and the
    icon clears.
    **Say:** *"Signal comes back and it syncs itself. The health worker never
    thinks about it."*
14. **Open Sita's timeline (S09).** The new visit is there, grouped under its
    Bikram Sambat month.
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

1. **Printed card + PIN (about 20 s).** My family → Sita → **Printable card**.
   A year-long read-only QR with her name, date of birth in both calendars,
   blood group, and — in Nepali and English — *"Ask the patient for their
   4-digit PIN"*. Tap **Share / save image**: it is a PNG, so it goes to a print
   shop.
   Now redeem it: S19 → **Scan patient QR** → *Enter code instead* → the card's
   payload → **Open record**. The app asks for **the patient's PIN**. Type a
   wrong one first — *"That PIN was not accepted"* — then `1234`.
   S21 opens under a **"Read-only access"** banner with **no Add visit and no
   Register pregnancy**.
   **Say:** *"A card on a wall is not a credential. The paper gets you as far as
   the door; the patient's four digits get you in, and only to read."*

2. **Delivery (about 10 s).** Sita's pregnancy → **Record delivery** → place,
   mode, outcome, baby weight and sex, complication chips → Save. The dashboard
   button is replaced by a green **Delivered** card, and back on My family her
   badge has changed from *Pregnant · week 30* to **Delivered**.

3. **AI draft summary (about 15 s).** Ram → Documents → **Bharatpur Hospital
   discharge sheet** → **Draft summary (AI)**. It reads *"Reading the
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

5. **Medicine reminder (about 5 s).** Ram's timeline → the visit → the medicine
   row. Tap the **speaker** to hear the drug and the Nepali instruction read
   aloud; tap **Set reminders** and it confirms *"13 reminders set for the next
   7 days"* — 08:00 and 20:00 for a BD prescription, with the Nepali instruction
   in the notification body.
   **Say:** *"Most people who are handed four tablets a day cannot read the
   label. So the phone says it, and then keeps saying it."*

**Optional close:** *"Health post dashboard"* — the chart icon on S19 counts the
caseload cached on this phone: pregnancies by trimester, who has been missed,
who was flagged red or amber this week, deliveries this month. Every tile opens
the list of women behind it. It is computed locally, so it works in a building
with no connection — which is where the question usually gets asked.

---

## Optional Tier 3 segment (about 60 seconds)

The roadmap tier. Run it only if the room has asked "what's next" — it is four
beats and each one answers a different objection.

**Say:** *"Four things on the roadmap, all built, none of them requiring a
government API we do not have."*

1. **Child health (about 20 s).** My family → **Aarav Chaudhary**, 3 years →
   the **Child health** card, which already reads **"Overdue: 2"** in red.
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

2. **Consent, section by section (about 15 s).** My family → Sita → **Share
   record (QR)**. Above the QR there is now a **"What to share"** row. Tap
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

4. **PDF (about 15 s).** Back to Ram → **Export PDF** → the share sheet appears
   with a real file. Open it in a PDF viewer if one is handy.
   **Say:** *"The record belongs to the patient, so it has to be able to leave
   the app. Allergies boxed in red at the top, medicines with the Nepali
   instruction, the immunisation card if it is a child, dates in both
   calendars. That sheet works in a referral hospital with no network, no
   account and no copy of this software."*

**Optional close — the honest slide.** Settings → scroll to **Integrations**.
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
2. **"Enter code instead" on S20.** The link sits under the camera preview. It
   accepts the whole `SWC1:…` payload and goes through exactly the same redeem
   path — same prefix check, same rejection toast. This is the reliable one.
   To get the payload without a camera:
   `adb exec-out screencap -p > s.png` and decode it, or read it off the share
   sheet.
3. **Skip the scan.** The provider's "Recent patients" list on S19 keeps anyone
   already redeemed, so a scan done before the demo still opens S21 in one tap.

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
