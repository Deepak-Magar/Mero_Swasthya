# Device run report

## Devices

**Session 1 and most of session 2 — Nothing Phone (Spacewar), Android 15.**
Serial `P21297002263`, model A063, 1080x2400, API 35, arm64-v8a. Everything
below was run here.

**End of session 2 — no device.** The Nothing Phone dropped off USB mid-session
and never re-enumerated: `adb devices` stayed empty and Windows
`Get-PnpDevice -PresentOnly` listed no Android or ADB device at all, so it was a
physical disconnection rather than an adb fault (killing and restarting the adb
server did not bring it back). A replacement phone was expected; `adb devices`
was polled roughly sixty times over the remainder of the session and never
listed one, authorized or otherwise. The device work still outstanding because
of this is listed in `docs/SESSION_2_HANDOFF.md` section 2.

**Replacement phone — POCO X3 Pro.** Serial `483a08e5`, model `M2102J20SI`
(`bhima_in`), POCO / Xiaomi, **Android 13 (API 33), MIUI V140**, 1080x2400 at
440 dpi, **arm64-v8a**. The full session-2 device suite was re-run here; see
"Session 2, third run" below.

Two MIUI settings had to be turned on before anything could be driven, and they
are worth knowing for any future Xiaomi device: **Developer options → "USB
debugging (Security settings)"** (without it `adb shell input` fails with
`SecurityException: … INJECT_EVENTS`, and `settings put` fails with
`WRITE_SETTINGS`) and **"Install via USB"** (without it `adb install` fails with
`INSTALL_FAILED_USER_RESTRICTED`, and `pm install` from a pushed APK fails the
same way). Both require a Mi account. `svc power stayon true` is also a no-op
until the first is on.

---|---|
| `adb install -r build/MeroSwasthya-demo-arm64.apk` | `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user` |
| `adb shell input keyevent` / `input tap` / `input text` | `SecurityException: Injecting input events requires … INJECT_EVENTS` |
| `adb shell settings put system screen_off_timeout …` | `SecurityException: … WRITE_SETTINGS` |
| `adb shell svc power stayon true` | accepted but ineffective — `dumpsys power` still reports `mStayOn=false` |

All four are the same MIUI family of restrictions. To unblock, in
**Settings → Additional settings → Developer options** turn on **"Install via
USB"** and **"USB debugging (Security settings)"**. On MIUI 14 both require being
signed into a Mi account, and the second one also enables input injection and
`settings put`. Nothing about the app or the APK is implicated — the same APK
installs and runs on the Nothing Phone.

---

## The original run

Release APK, `--dart-define=MOCK_API=true`, installed with `adb install -r`.
Screenshots in `docs/screens/device_*.png`.

Gate at every step: `flutter analyze` clean and `flutter test` green.
Final state: **analyzer clean, 294 tests passing**, release APK builds (78.1 MB
fat; a `--split-per-abi` build will be roughly a third of that).

---

## §17 acceptance checklist

| # | Item | Result |
|---|---|---|
| 2 | Fresh install → OTP → set PIN → add family member | **PASS** — after fixing D1 |
| 5 | ANC contact, BP 150/95 + severe headache → red + referral + call | **PASS** — after fixing D3 |
| 6 | Document capture with the real camera | **PASS** — after fixing D4 |
| 7 | Timeline grouped by BS month | **PARTIAL** — see below |
| 9 | Language toggle switches every visible string | **PASS** |
| 10 | Release APK installs, camera and scanner work in release mode | **PASS (camera)**, scanner not exercised — see below |

### What each one actually showed

**Item 2.** Fresh install (`pm clear`) → phone entry normalised `9801000001` to
`+9779801000001` → demo OTP `123456` → **S05 "Create your PIN"** → family list.
"Gita Chaudhary" appeared immediately with the sync chip green. The Bikram
Sambat picker opened on **Ashwin 2083** (today) with future days greyed out, and
the saved DOB rendered **"2083 Ashoj 1 (2026-09-17)"** — BS primary, AD
secondary, per §13.

**Item 5.** Registering a pregnancy computed **LMP 2026-09-18 → EDD 2027-06-25**
live (exactly +280 days) and previewed the eight contacts at the A.5 weeks
`[12, 20, 26, 30, 34, 36, 38, 40]` with BS dates, week 40 landing on the EDD.
On contact 4, entering **BP 150** alone produced the amber banner with "Raised BP
(≥140/90)" (A.6 case 4); adding **severe headache** produced the **red** banner
carrying both reasons — the danger sign itself and "BP ≥ 140/90 with proteinuria
or severe headache — possible pre-eclampsia" (A.6 case 3). The referral card
appeared and the Call button went from amber to red. After saving, the dashboard
showed contact 4 with a red dot, "Recorded", the referral facility in red and a
Call button; progress moved to 1/8.

**Item 6.** `image_picker` launched `com.nothing.camera/.activity.CameraActivity`
from a release build, the capture-intent confirm returned to the app, the
metadata sheet opened (type/title/BS date), and Save compressed and stored the
file. The card then showed the real photograph.

**Item 9.** One tap switched every string: सेटिङ, भाषा, सर्भर ठेगाना, जडान
परीक्षण, नियम संस्करण, लगआउट… Only the URL and version numbers stayed Latin,
which is right. The document sheet showed the BS date in **Nepali numerals**
(२०८३ असोज २) beside the Latin AD date.

**Item 10.** Release APK installed and ran with no `AndroidRuntime` or `FATAL`
in logcat at any point across the whole session. Impeller/Vulkan backend,
`libflutter.so` and `libdartjni.so` loaded, R8 stripped nothing drift or freezed
needed. Camera works in release. **The QR scanner was not exercised** — redeeming
a grant needs a second device to display the QR, and this run had one phone.

**Item 7 is partial.** The timeline groups by BS month and the grouping code is
unit-tested, but nothing in this run produced entries across two different BS
months, so the grouping was not *seen* working on the device.

---

## Defects found on the device and fixed

**D1 — a fresh install could never reach S05 "Set PIN".**
`MockApi` answered `hasPin: true` to the very first `POST /auth/otp/verify`, so
S03 routed a brand-new install to the unlock screen. Step 2 of the checklist was
unreachable. The mock now records which phones have completed
`POST /auth/pin/set` and answers `hasPin: false, isNewUser: true` until then.
Tests: two in `test/net/mock_api_test.dart`.

**D2 — the seeded records never reached the device.**
S06 read only the local database. Sync pull carries patients, but the mock's pull
is empty by design, so Sita and Ram existed on the "server" and nowhere else —
and against a real backend a device signing into an existing account would show
an empty family list until something changed. Spec S06 lists
"GET /patients (on refresh)" for exactly this. Added
`PatientRepo.refreshFromServer()`, called on S06 init and on pull-to-refresh; it
skips any row with a pending outbox op so it cannot overwrite unsent edits.
Tests: three in `test/repositories/repositories_test.dart`.

**D3 — the BP steppers could not express the numbers the rules triage on.**
`NumberStepper` started at the midpoint of its range and moved in steps of 2.
For systolic (60..250) that is 155, so **every reachable value was odd**: 140,
150 and 160 could not be entered at all, and diastolic could not reach 90 or 110.
Those are the exact thresholds in A.5. The start is now snapped onto the step
grid, and tapping the value opens a numeric dialog — §16 says never *require*
typing for vitals, not that a value may be unreachable. Out-of-range input is
clamped rather than dropped. Tests: four in `test/features/widgets_test.dart`.

**D4 — an uploaded document stopped being viewable offline.**
`markUploaded` cleared `local_path`, so once the upload finished the app fetched
a picture it was already holding, and fell back to a grey type icon whenever it
could not. The status alone is enough to dequeue the upload worker, so the path
is now kept. Visible in `device_45_thumbnail_real.png`: the document captured
after the fix renders the photograph, the one captured before it still shows the
placeholder. Test: `markUploaded stops the worker but keeps the file on disk`.

---

## Not defects

Two things that looked wrong early and were not:

- A **black screen** and a confusing jump to the PIN screen were the phone's
  display timing out and the task being evicted. `pidof` showed the process
  alive and logcat was clean. Fixed the harness with `svc power stayon usb`.
- Several **mis-taps** (typing a phone number into the OTP field, toggling two
  risk-factor checkboxes, adding a stray character to a name) were blind
  coordinates from stale screenshots, not app faults. From `device_05` onward
  every step was screenshot → read → tap → verify.

---

## One thing I could not explain

A single suite run reported `+293 -1` while a documentation file was being
written in the same shell invocation. The failing test name was not captured,
and **four consecutive runs afterwards were clean** (`+294`). So there is either
a flaky test or an interaction with concurrent file writes, and I could not pin
down which. Worth watching: if it recurs, run `flutter test --concurrency=1` and
capture the name before assuming it is noise.

## Still open

- **QR redeem (S20) untested** — needs a second device. Everything downstream of
  it (the cached bundle, S21, offline visit entry) is unit-tested but has never
  run on hardware.
- **Timeline BS-month grouping unseen**, as above.
- **The database is unencrypted** — the §6.1 fallback, with `KeyDerivation`
  written and `openAppDatabase()` the single call site to change.
- **Tier 2 untouched by design**: S14 delivery record, AI summary, printed static
  QR, medicine notifications, facility map.

---

# Session 2, second run — same Nothing Phone

Same serial, release APK rebuilt with `--split-per-abi --dart-define=MOCK_API=true`
and installed with `adb install -r`. Screenshots in `docs/screens/pull_*.png`,
`qr_*.png` and `final_02_fresh_install_family.png`.

This run closed three of the four items left open above.

## Now settled

- **Sync pull (§17 items 2 and 7).** A genuinely fresh install (`pm clear`) →
  `9801000001` → OTP `123456` → PIN → **S06 already holding Ram and Sita**, with
  Sita's chip reading "Pregnant · week 30". S12 showed contacts 1–3 green,
  **contact 4 due 2083 Ashoj 2 — today** — and the remaining four scheduled to
  week 40 on the EDD. Ram's timeline put his visit under **2083 Bhadra** and his
  lab document under **2083 Shrawan**: two different BS months, so the grouping
  that was "unseen" above has now been seen.
- **QR redeem (S20/S21), on one phone.** The redeem path ran end to end using
  the new manual-code fallback rather than a second device: the share sheet's
  grant was decoded off a screenshot (`SWC1:mock_grant_…`), typed into S20's
  "Enter code instead", and **S21 came up with the red `sulpha` chip, the active
  pregnancy card and the ANC contact 4 action**. A payload of `HELLO` was
  refused with "That is not a Swasthya Card QR" and the dialog stayed open so a
  typo can be corrected.
- **Scanner in release mode.** The camera preview opens, with the green privacy
  dot, from a release build — so the plugin, the permission and the surface all
  work. **No QR has been read through the lens**, which is the one thing still
  needing a human.

## Defects found on the device this run

**D5 — the provider role did not survive an app relaunch.** Activation persisted
the user, but a relaunch built a fresh in-memory `MockApi` that had never heard
of it, and the background `GET /me` overwrote the stored role with the seeded
patient. The mock now reports activations to `AppConfig`
(`mock_activated_role`) and the next instance is handed the role back. Verified:
force-stop → relaunch → still "Ghorahi Health Post"
(`qr_10_role_survives_restart.png`).

**D6 — mock mode could not be taken offline.** `connectivityProvider` returned
`AlwaysOnline` on the mock transport, so airplane mode did nothing on a demo
build and §17 item 3 could not be shown at all. Both transports now use the
device's own connectivity. **Not yet verified on hardware** — the phone was lost
before this could be run, and it is the first thing to retest.

**D7 — the allergy seeds were empty**, so S21's red chip row always rendered
"No known allergies". Sita is now seeded `sulpha` and Ram `penicillin`
(`qr_11_sita_allergy_chip.png`, `qr_12_ram_allergy_chip.png`).

## Also observed

The share sheet's countdown was left to run out: at zero it showed **"QR
expired, ask for a new one"** with Revoke disabled and Regenerate still live
(`qr_09_countdown_expired.png`) — the patient-side half of A.6 case 15, without
having to shorten the TTL.

## Still open after this run

- **Airplane-mode round trip (§17 item 3)** — never observed on hardware, and
  the D6 fix that makes it possible is itself unverified.
- **Expired grant and Revoke on the redeem side** — unit-tested only.
- **One real camera scan** — see above.
- **Settings: mock toggle and Test connection** on the phone.
- **The database is unencrypted** — unchanged.
- **Tier 2 untouched by design** — unchanged.

The phone disconnected from USB at this point and no replacement appeared; see
the Devices section at the top.

---

# Session 2, third run — POCO X3 Pro

Serial `483a08e5`, Android 13 / MIUI V140, arm64-v8a. Release APK
(`--split-per-abi --dart-define=MOCK_API=true`), `adb install -r` + `pm clear`,
fresh first run. Screenshots in `docs/screens/newphone_*.png`.

Everything the two earlier runs had established was re-verified here, because
this is a different phone, a different Android version and a different OEM skin.
**Two things were seen working for the first time anywhere: the airplane-mode
round trip, and a grant expiring on the redeem side.**

## Results

| # | §17 item | Result | Evidence |
|---|---|---|---|
| 1 | Rules unit tests (A.6, all 16) | **PASS** | suite, 343 tests |
| 2 | Fresh install → OTP → PIN → family without network | **PASS** | `newphone_01_family_fresh.png` |
| 3 | Airplane mode → visit → pending → online → synced | **PASS** | `newphone_12` … `newphone_19` |
| 4 | QR generate → redeem → summary; expired QR message | **PASS** | `newphone_10`, `newphone_11`, `newphone_34` |
| 5 | BP 150/95 + severe headache → red + referral + call | **PASS** | `newphone_28`, `newphone_29`, `newphone_30` |
| 6 | Document capture → thumbnail → uploaded | **BLOCKED (device fault)** | `newphone_33_camera_crash.png` |
| 7 | Timeline in correct BS-month groups | **PASS** | `newphone_04_ram_timeline.png` |
| 8 | Audit shows the provider's redeem | **PASS** | `newphone_31_audit.png` |
| 9 | Language toggle switches every string | **PASS** | `newphone_22_nepali.png` |
| 10 | Release APK installs; camera + scanner in release | **PASS (scanner)**, item 6 blocked | `newphone_08`, `newphone_35` |

## The airplane-mode round trip, in full

This is §17 item 3, and it had never run on hardware before.

1. Redeemed Sita's grant, landed on S21 with the red `sulpha` chip and the
   active pregnancy card.
2. `adb shell cmd connectivity airplane-mode enable` → the sync chip went grey
   and S21 showed **"Offline — showing the record from 00:28"**. This is the D6
   fix working; before it, mock mode reported a permanent online.
3. Added a visit offline (Antenatal check, BP 118/76, 58.0 kg). It saved, and
   **"Last vitals — BP 118/76 · 58.0 kg"** appeared on S21.
4. S17 showed **"1 waiting to sync"** with the offline cloud.
5. Airplane mode off → within seconds, **"Everything is synced · just now"**
   with the green cloud.
6. The visit is in Sita's timeline, under 2083 Ashoj, now carrying the server's
   title.

## Defect found on the device this run

**D8 — an unsynced entry vanished from the timeline.**
Step 3 above should have put the visit straight into the timeline and did not.
`timelineProvider` follows spec S09 literally — "when online, replace with the
server list" — and the in-process mock answers a `/timeline` call even with the
radio off, so the server's list (which cannot contain a row still sitting in the
outbox) replaced the local union and the visit disappeared. In the field that is
a health worker watching the visit she just recorded vanish from the patient's
record. `mergeTimeline` now keeps the server authoritative for every row it
knows about and appends anything only this device has. Four tests in
`test/features/local_timeline_test.dart`. Re-verified on the phone: the visit
shows while offline, and after the sync it is still there wearing the server's
title.

## Item 6 — blocked by the phone, not the app

`Capture paper` fires the capture intent correctly and MIUI's camera opens, then
**`com.android.camera` crashes**: `IllegalArgumentException:
getCameraCharacteristics:791: Unable to retrieve camera characteristics for
unknown device -1`, thrown from Xiaomi's own
`VirtualCameraReprocessor.openVTCamera`. The dialog is MIUI's "Camera keeps
stopping". **Mero Swasthya does not crash** — logcat has no `FATAL` for
`com.meroswasthya.app` — and the cancelled result is handled cleanly: no bogus
document row is written. Item 6 **passed on the Nothing Phone**
(`device_45_thumbnail_real.png`), so the app path is proven; this phone's system
camera is broken.

Worth noting the in-app scanner is unaffected: it uses `mobile_scanner`
(CameraX, in-process), and its preview opened normally with the green camera
indicator (`newphone_08_scanner_preview.png`).

## Also verified here

- **Provider role survives a relaunch** (D5): force-stop → relaunch → still
  "Ghorahi Health Post" (`newphone_06`).
- **Allergy seeds** (D7): Sita `sulpha`, Ram `penicillin` (`newphone_02`,
  `newphone_03`).
- **Manual-code fallback**: `HELLO` → "That is not a Swasthya Card QR", dialog
  stays open (`newphone_09`); full `SWC1:` payload → S21 (`newphone_10/11`).
- **Revoke**: the QR is replaced by a padlock and "Access revoked"
  (`newphone_24`), and redeeming the revoked token is refused with "QR expired,
  ask for a new one" (`newphone_25`).
- **Expired grant**: with the mock TTL temporarily cut to 5 s, redeeming after
  expiry gave the same message (`newphone_34`). **The TTL was restored to
  `ttlMinutes` afterwards** and the shipped APK was rebuilt from the restored
  source.
- **Settings** (item 4 of the session plan): Test connection against the mock →
  green tick (`newphone_20`); against `http://10.255.255.1:9/api/v1` → red error
  after the connect timeout (`newphone_21`). Toggling the switch off enables the
  address field and changes the subtitle to "Talking to the server address
  below"; toggling back on makes it inert again.

## Still open after this run

- **One real camera scan through the lens** — the scanner previews but has never
  read a QR optically. Needs a human, and a phone whose camera works.
- **Document capture on a working camera** — passed on the Nothing Phone, cannot
  be re-run here.
- **The database is unencrypted** — unchanged.
- **Tier 2 untouched by design** — unchanged.
