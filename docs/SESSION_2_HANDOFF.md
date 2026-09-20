# Session 2 — handoff

Flutter app **Mero Swasthya** (spec: "Swasthya Card"), Tier 1, mock-backed.
Written at the end of session 2, which resumed an interrupted session 2 run.

---

## 1. Status at a glance

| | |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test` | **+343, all passing** (306 at the start of this session) |
| Release build | `flutter build apk --release --split-per-abi --dart-define=MOCK_API=true` — all three ABIs build |
| Demo APKs | `build/MeroSwasthya-demo-arm64.apk` and `-arm64-v8a.apk` **28.6 MB** (29,973,759 bytes); `-armeabi-v7a.apk` 25.0 MB; `-x86_64.apk` 30.9 MB. All three ABIs were copied out under their own names because no phone was attached to read `ro.product.cpu.abi` from — install whichever matches. arm64-v8a is the one to reach for first. |
| Device verification | **Complete bar one item — see §2.** |

### Devices used

| Phase | Device | Result |
|---|---|---|
| Session 1 and most of session 2 | **Nothing Phone (A063, "Spacewar")**, serial `P21297002263`, Android 15 (API 35), 1080x2400, arm64-v8a | Most device work; then it disconnected from USB mid-session and never re-enumerated (Windows saw no Android device at all, so a physical disconnection) |
| End of session 2 | **POCO X3 Pro**, serial `483a08e5`, model `M2102J20SI`, Android 13 (API 33) / MIUI V140, 1080x2400 @ 440 dpi, **arm64-v8a** | The whole suite re-run and finished here |

**On a Xiaomi/MIUI phone, two Developer options must be on before anything can
be driven over adb**: "USB debugging (Security settings)" (else `input` and
`settings put` are refused) and "Install via USB" (else `adb install` and
`pm install` fail with `INSTALL_FAILED_USER_RESTRICTED`). Both need a Mi account.

---

## 2. What was verified on hardware

Everything below was re-run on the **POCO X3 Pro** at the end of the session
unless marked otherwise, so it reflects one phone, one build, one pass.

### Verified ✅

| What | Evidence |
|---|---|
| Fresh install → OTP `123456` → PIN → family list, no network needed | `newphone_01_family_fresh.png` |
| First pull brings the whole record down — Sita "Pregnant · week 30", contacts 1–3 green, contact 4 due **2083 Ashoj 2** | `newphone_02`, `newphone_26` |
| Ram's visit and document in two different BS months | `newphone_04_ram_timeline.png` |
| Allergy seeds — Sita **sulpha**, Ram **penicillin**, red chip | `newphone_02`, `newphone_03` |
| S18 activation `HA-GHORAHI-01` → Ghorahi Health Post | `newphone_05` |
| **Provider role survives a force-stop and relaunch** (D5) | `newphone_06` |
| S20 scanner opens with a live camera preview in release | `newphone_08` |
| Manual entry: `HELLO` → rejection toast, dialog stays open | `newphone_09` |
| Manual entry: full `SWC1:` payload → **S21 with red sulpha chip, active pregnancy, last vitals** | `newphone_10`, `newphone_11` |
| **Airplane mode → offline banner + grey chip** (D6) | `newphone_12` |
| Visit saved offline; "Last vitals" appears | `newphone_14` |
| **"1 waiting to sync"** pending state | `newphone_17` |
| Airplane off → **"Everything is synced · just now"**, green | `newphone_18` |
| The offline visit is in the timeline, before and after the sync (D8) | `newphone_16`, `newphone_19` |
| Test connection: mock → green tick; unreachable URL → red error | `newphone_20`, `newphone_21` |
| Language toggle switches every visible string | `newphone_22` |
| Audit shows "Opened the record — Ghorahi Health Post" | `newphone_31` |
| **Revoke** → padlock + "Access revoked"; revoked token refused | `newphone_24`, `newphone_25` |
| **Expired grant** (mock TTL cut to 5 s, then restored) → "QR expired, ask for a new one" | `newphone_34` |
| ANC BP 150/95 + severe headache → **red** with both A.6 case-3 reasons, referral card, red Call, red dot + 4/8 on the dashboard | `newphone_28`, `newphone_29`, `newphone_30` |
| Final release APK installs and runs with no `FATAL` for the app | `newphone_35` |
| *(Nothing Phone only)* Document capture with the real camera → real thumbnail | `device_45_thumbnail_real.png` |

### Not verified ❌

1. **A QR read optically, through the lens.** The scanner opens and previews,
   and every redeem so far went through the manual-code fallback. This needs one
   human rehearsal — and a phone whose camera works.
2. **Document capture on this phone.** MIUI's `com.android.camera` crashes
   (`getCameraCharacteristics: unknown device -1`, inside Xiaomi's
   `VirtualCameraReprocessor`). The app fires the intent correctly, does not
   crash, and handles the cancelled result cleanly. It **passed on the Nothing
   Phone**, so the app path is proven; this device's system camera is broken.

---

## 3. Spec §17 acceptance checklist

Run on the POCO X3 Pro against the shipped build, except where noted.

| # | Item | Result | Where |
|---|---|---|---|
| 1 | Rules unit tests: all 16 cases in A.6 | **PASS** | `test/domain/rules_test.dart` |
| 2 | Fresh install → OTP → PIN → family member visible without network | **PASS** | `newphone_01` |
| 3 | Airplane mode → visit → pending icon → online → synced | **PASS** | `newphone_12`–`newphone_19` |
| 4 | QR generate → scan → summary shows allergies and pregnancy; expired QR message | **PASS** | `newphone_10`, `newphone_11`, `newphone_34` — redeemed via the manual fallback, not the lens |
| 5 | ANC BP 150/95 + severe headache → red + referral + call; red dot | **PASS** | `newphone_28`–`newphone_30` |
| 6 | Document capture → thumbnail → uploaded | **PASS** on the Nothing Phone; **BLOCKED** on the POCO by a MIUI camera crash | `device_45`, `newphone_33` |
| 7 | Timeline in correct BS-month groups | **PASS** | `newphone_04` |
| 8 | Audit shows the provider's redeem and visit | **PASS (redeem)** | `newphone_31` — see the note below |
| 9 | Language toggle switches every visible string | **PASS** | `newphone_22` |
| 10 | Release APK installs; camera + scanner work in release | **PASS (scanner, install)**; camera per item 6 | `newphone_08`, `newphone_35` |

**No item is a FAIL.** Item 6 is blocked by a device fault, and item 8 shows the
redeem but not the visit — because the visit reached the server through
`POST /sync/push`, and the mock only writes an audit entry for
`POST /patients/:id/visits`. **The backend should write an audit entry for a
visit that arrives via sync push too**, or the patient's "who touched my record"
list will have a hole in exactly the offline case the app is built for.

---

## 4. Defects found and fixed this session

**D5 — the provider role did not survive an app relaunch.**
S18 activation persisted the health-worker user to the local DB, but `MockApi`
keeps everything in memory, so the next launch built a fresh one that had never
heard of the activation. `unlock()` then calls `GET /me` in the background,
which handed back the *seeded patient* and overwrote the stored role: the app
bar fell back to "I am a health worker" and the provider screens disappeared.
Found on the phone. The mock now reports an activation through an `onActivated`
callback, `AppConfig` persists it under `mock_activated_role`, and
`apiTransportProvider` hands it back to the next `MockApi`. `signOut()` clears
it so the next account on the phone does not inherit a facility.
Tests: three in `test/net/mock_api_test.dart`. Verified on the phone.

**D6 — mock mode could not be taken offline, so §17 item 3 was undemonstrable.**
`connectivityProvider` returned `AlwaysOnline` whenever the mock transport was
selected, on the reasoning that an in-process mock cannot be unreachable. True,
and it meant airplane mode did nothing on a demo build: no grey chip, no pending
icon, no offline banner — and the demo runs on the mock. The provider now
returns `PluginConnectivityMonitor` on both transports; what is being
demonstrated is the outbox queue, not a socket, so the phone's own connectivity
is the right input. `AlwaysOnline` stays for tests, which have no platform
channel. **Verified on the POCO X3 Pro**: airplane mode now produces the grey
chip and the "Offline — showing the record from HH:MM" banner, and §17 item 3
runs end to end for the first time.

**D7 — the allergy seeds were empty.**
Both seeded patients had `allergies: []`, so S21's red chip row — the headline
of spec §16 and of §17 item 4 — always rendered the green "No known allergies".
Sita is now seeded `["sulpha"]` and Ram `["penicillin"]`, matching the backend
spec §10 seed. **The backend must seed the same values** (see §6).

**D8 — an unsynced entry vanished from the timeline.**
Spec S09 says the server list replaces the local union "when online", because
the server is authoritative for wording. Taken literally it hides work the device
has not pushed: a visit recorded in airplane mode disappeared from the timeline,
because the in-process mock answered the `/timeline` call even with the radio
off and its list could not contain a row still in the outbox. Against a real
backend the same thing happens the moment the network returns and the fetch beats
the push. `mergeTimeline` now keeps the server authoritative for rows it knows
and appends anything only this device has, newest first. Four tests in
`test/features/local_timeline_test.dart`. Found and fixed on the POCO, then
re-verified there both offline and after the sync.

Carried over from the interrupted part of session 2: the sync-pull gap (the
mock's `/sync/pull` returned nothing, so a fresh install showed Sita with no
pregnancy and Ram with no visits) and the S06 → S18 redirect that bounced "I am
a health worker" straight back to the family list. Both fixed and verified.

---

## 5. Endpoints the app calls — for the backend smoke test

**Envelope (A.1).** Every response is `{"ok": true, "data": {…}}` or
`{"ok": false, "error": {"code": "...", "message": "...", "details": {...}}}`.
The client unwraps `data` in an interceptor, so **every shape below is what goes
inside `data`**. A `200` carrying `ok:false` is still treated as a failure.
Auth is `Authorization: Bearer <accessToken>` except where noted.

### Auth

| Call | Request body | `data` the app expects |
|---|---|---|
| `POST /auth/otp/request` | `{phone}` | `{otpSentTo, expiresInSec?, demoOtp?}` |
| `POST /auth/otp/verify` | `{phone, otp}` | `{tempToken, hasPin, isNewUser}` — **`hasPin:false` for a phone that has never called `/auth/pin/set`**, or a fresh install can never reach S05 |
| `POST /auth/pin/set` | `{pin, name}`, bearer = **`tempToken`**, not the access token | `{accessToken, refreshToken, user}` |
| `POST /auth/pin/login` | `{phone, pin}` | `{accessToken, refreshToken, user}` |
| `POST /auth/refresh` | `{refreshToken}` | `{accessToken, refreshToken}` |
| `POST /auth/provider/activate` | `{inviteCode}` | `{user}` with `role`, `facilityId`, `facilityName` |
| `GET /me` | — | `{user}` — **must keep the activated role**; the app overwrites its local user with this |

`user`: `{id, phone, name, role: patient|provider|fchv, facilityId?, facilityName?}`.

### Patients

| Call | Request | `data` |
|---|---|---|
| `GET /patients` | — | `{items: [Patient]}` |
| `POST /patients` | Patient fields incl. client-generated `id` | `{patient}` |
| `PATCH /patients/:id` | changed fields | `{patient}` |
| `GET /patients/:id` | — | `{patient}` |
| `GET /patients/:id/timeline` | — | `{items: [{kind: visit\|document\|anc_contact\|delivery, at, payload}]}` — `payload` is the **whole entity**, which the app caches |
| `GET /patients/:id/audit` | — | `{items: [AuditEntry]}` |
| `GET /patients/:id/visits` | — | `{items: [Visit]}` |
| `POST /patients/:id/visits` | Visit incl. client `id` and `prescriptions[]` ids | `{visit}` |
| `GET /patients/:id/reminders` | — | `{items: [Reminder]}` |

`Patient`: `{id, ownerUserId, name, sex, dob, bloodGroup?, ward?, municipality?, allergies: [string], chronicConditions: [string], emergencyContactPhone?, version, updatedAt, deleted}`.

### Pregnancy / ANC

| Call | Request | `data` |
|---|---|---|
| `POST /patients/:id/pregnancies` | `{id, lmp?  \| edd?, gravida?, para?, riskFactors[]}` | `{pregnancy, ancContacts: [AncContact]}` |
| `GET /pregnancies/:id` | — | `{pregnancy, ancContacts}` |
| `PATCH /pregnancies/:id` | changed fields | `{pregnancy}` |
| `PUT /pregnancies/:id/contacts/:contactNo` | `{findings, dangerSigns[], doneAt, …}` | `{ancContact, triage: {level, reasons[]}}` |
| `POST /pregnancies/:id/delivery` | delivery fields | `{delivery}` |

**ANC contact ids are deterministic on both sides** (A.8.15):
`uuidv5(ns 6ba7b810-9dad-11d1-80b4-00c04fd430c8, pregnancyId + ":" + contactNo)`.
The app generates the same eight ids offline; if the server generates its own
the demo will show sixteen contacts.

### Grants (QR)

| Call | Request | `data` |
|---|---|---|
| `POST /grants` | `{patientId, scope: "read"\|"append", ttlMinutes: 10}` | `{grant, token, qrPayload}` — `qrPayload` **must** be `"SWC1:" + token` |
| `POST /grants/redeem` | `{qrPayload}` | `{grant, patient, summary, timeline[], pregnancy?, ancContacts[]}` |
| `POST /grants/:id/revoke` | — | `{grant}` |

`grant`: `{id, patientId, scope, expiresAt, redeemedByUserId?, redeemedAt?, revokedAt?, accessUntil?}`.
Errors the app handles by code: `GRANT_EXPIRED` (403, also for a revoked grant),
`ALREADY_REDEEMED` (409), `NOT_FOUND` (404).

**The app never parses the token.** It checks the `SWC1:` prefix and posts the
whole string back, so the real HS256 JWT of A.7 works unchanged — the mock's
opaque `mock_grant_<uuid>` is only a mock convenience.

### Sync

| Call | Request | `data` |
|---|---|---|
| `POST /sync/push` | `{deviceId, changes: [{opId, table, op, rowId, baseVersion, payload}]}` (≤50, in `createdAt` order) | `{results: [{opId, status: applied\|duplicate\|conflict\|rejected, row?, error?}], serverTime}` |
| `GET /sync/pull?since=<cursor>&deviceId=<id>` | — | `{changes: [{table, row}], cursor, hasMore}` |

`/sync/pull` must return **every table for every patient the account can see** —
`patients`, `pregnancies`, `anc_contacts`, `visits`, `documents`, `deliveries`.
This is the single biggest thing to get right: the bug that opened this session
was a pull that returned patients only, which made a fresh install show a
week-30 pregnancy as "Register pregnancy". The app upserts by `id` where
`incoming.version > local.version`, and a row it cannot parse is skipped without
stalling the cursor.

### Documents

| Call | Request | `data` |
|---|---|---|
| `POST /documents/presign` | `{id, patientId, type, title, takenAt, contentType, sizeBytes}` | `{document, uploadUrl, uploadMethod: "PUT", uploadHeaders: {}, expiresInSec}` |
| *(the upload itself)* | raw bytes to `uploadUrl` — **no envelope, no bearer** | — |
| `POST /documents/:id/complete` | — | `{document}` |
| `GET /documents/:id` | — | `{document}` with a fresh download URL |
| `POST /documents/:id/summarize` | — | Tier 2; may answer `501` |

### Reference

| Call | `data` |
|---|---|
| `GET /config` | `{…, codelistVersion, aiSummaryEnabled}` — also what S23's **Test connection** button calls |
| `GET /rules` | the rule table (same shape as `assets/rules.json`) |
| `GET /codelists` | `{version, items: {…}}` — enum keys are **camelCase** (`dangerSign`, not `danger_sign`) |

---

## 6. What the backend must seed to match this build

- **Sita Chaudhary** — `allergies: ["sulpha"]`, female, active pregnancy at
  **week 30**, ANC contacts 1–3 done with findings, 4–8 pending.
- **Ram Bahadur Chaudhary** — `allergies: ["penicillin"]` (this matches backend
  spec §10 already), `chronicConditions: ["E11"]`, one visit and one lab
  document, dated in two different BS months so the timeline grouping shows.
- Invite codes `HA-GHORAHI-01` → provider at "Ghorahi Health Post", and
  `FCHV-W5-01` → fchv.
- Demo OTP `123456`.

If Sita's allergy is left empty the demo's headline S21 moment — the red chip
row — shows nothing.

---

## 7. Known issues

1. **No QR has ever been read optically.** The scanner opens and previews on
   both phones, but every redeem went through the manual-code fallback. One
   human rehearsal before the demo, please — the fallback is there if it
   misbehaves.
2. **MIUI's system camera crashes on the POCO X3 Pro**, so document capture
   cannot be exercised there. Xiaomi's bug, not this app's (see §2). It works on
   the Nothing Phone.
3. **A revoked grant is reported as expired.** The mock answers `GRANT_EXPIRED`
   for both, so the user sees "QR expired, ask for a new one" after a deliberate
   revoke. Harmless but imprecise; the backend may want a distinct code and
   message, and the app would then need one more string.
4. **A visit that arrives via `/sync/push` writes no audit entry** in the mock,
   so §17 item 8 shows the redeem but not the visit. The backend should audit
   pushed writes too.
5. **"Last vitals" on S21 reads only the latest `Visit`.** A pregnant patient
   whose only recent measurements are in an ANC contact (Sita: BP 124/80 at
   contact 3) shows no vitals card until a visit is recorded. Spec S21 lists
   "Last vitals" without saying where from; falling back to the latest ANC
   contact would be the better reading. Not changed — it alters what a clinician
   sees, and it deserves a decision rather than a quiet edit.
6. **The share sheet can only revoke the grant it is currently showing.** Open
   the sheet, dismiss it, open it again and the first grant is unreachable from
   the UI until it expires on its own. Low impact at a 10-minute TTL.
7. **The local database is unencrypted** — the §6.1 fallback. `KeyDerivation` is
   written and `openAppDatabase()` is the single call site to change.
8. **No widget tests for the 23 screens themselves**, only for shared widgets,
   the timeline builder, the manual-code dialog and the router redirect.
9. **`GET /me` overwrites the local role on every unlock.** Correct against a
   real server, and the reason D5 bit. Worth remembering if the backend ever
   answers a stale role.
10. **Rotation.** The app is portrait-only by design, but nothing in the manifest
   pins it; a phone with auto-rotate on will render landscape layouts that were
   never designed. Consider locking the orientation in `main()`.
11. The mock's grant token is opaque, not the A.7 JWT. Harmless (see §5) but it
   means the app has never parsed a real grant JWT.

---

## 8. Tier 2 — deliberately not built (spec §2.2)

S14 delivery record UI, the AI document summary view, the printed static QR
fallback card, medicine notifications, and the facility map. `POST
/documents/:id/summarize` and `POST /pregnancies/:id/delivery` exist in the API
layer but have no screen behind them.

---

## 9. Files changed across session 2 (both parts)

No git in this project, so this is by modification time. Session 1 finished at
about 17:46; everything below was touched after that.

### Application code

| File | Why |
|---|---|
| `lib/core/net/mock_api.dart` | `/sync/pull` now returns every table for the account's patients; correct ANC schedule; `hasPin` tracking; **allergy seeds**; **`activatedRole`/`onActivated` role persistence** |
| `lib/core/config/app_config.dart` | `use_mock_server` flag; **`mock_activated_role` get/set/clear** |
| `lib/core/providers.dart` | transport routing on `useMockServerProvider`; passes the remembered role to `MockApi`; **connectivity is now the device's own on both transports (D6)** |
| `lib/router.dart` | `/provider/activate` exempted from the role redirect, so S06's "I am a health worker" stops bouncing back |
| `lib/features/auth/auth_controller.dart` | `signOut()` clears the remembered mock role |
| `lib/features/provider/scan_screen.dart` | **`_redeem()` extracted as the one redeem path; "Enter code instead" + `ManualCodeDialog`** |
| `lib/features/timeline/local_timeline.dart` | **`mergeTimeline()` — the server wins for rows it knows, local-only rows are kept (D8)** |
| `lib/features/timeline/timeline_screen.dart` | `timelineProvider` merges instead of replacing (D8) |
| `lib/features/settings/settings_screen.dart` | "Use mock server" switch, server URL field (inert on mock), Test connection → `GET /config` |
| `lib/features/family/family_screen.dart` | the provider/health-worker action moved into the app bar, out of the gesture-navigation exclusion zone |
| `lib/core/l10n/app_en.arb`, `app_ne.arb` | four new strings for the manual-code dialog |
| `lib/core/l10n/gen/*.dart` | regenerated |
| `lib/data/sync/sync_engine.dart` | pull upserts every table it receives |
| `lib/data/repositories/patient_repo.dart` | `refreshFromServer()`, skipping rows with a pending outbox op |
| `lib/data/repositories/reference_repo.dart` | codelist refresh |
| `lib/data/local/daos/documents_dao.dart` | `markUploaded` keeps `local_path` (D4) |
| `lib/features/shared/widgets/app_widgets.dart` | `NumberStepper` snapped to the step grid + tap-to-type dialog (D3) |
| `lib/features/maternal/*`, `lib/features/documents/*`, `lib/features/family/patient_form_screen.dart`, `lib/features/provider/visit_form_screen.dart` | knock-on fixes from the device run |

### Tests

`test/sync/first_pull_test.dart` (new), `test/features/manual_code_test.dart`
(new, 8 tests), `test/features/local_timeline_test.dart` (+4 for D8),
`test/features/transport_switch_test.dart` (new, then reworked for D6),
`test/features/router_redirect_test.dart`, `test/net/mock_api_test.dart`,
`test/sync/sync_engine_test.dart`, `test/repositories/repositories_test.dart`,
`test/features/widgets_test.dart`, `test/features/summary_test.dart`,
`test/features/jwt_expiry_test.dart`.

### Docs and artefacts

`docs/FLAKY_TEST.md`, `docs/DEMO_SCRIPT.md` (new), `docs/SESSION_2_HANDOFF.md`
(new), `docs/SPEC_AUDIT.md`, `docs/DEVICE_RUN_REPORT.md`,
`docs/screens/pull_*.png`, `qr_*.png`, `device_*.png`, **`newphone_*.png`**,
`final_02_fresh_install_family.png`, and the demo APKs
`build/MeroSwasthya-demo-{arm64,arm64-v8a,armeabi-v7a,x86_64}.apk`.

---

## 10. What is left

Only two things, and both need a phone with a working camera:

1. **One real QR scan through the lens.** Everything downstream is proven; the
   optical read is not.
2. **Document capture** re-run somewhere other than the POCO, whose system
   camera is broken. It passed on the Nothing Phone.

Then the decisions in §7 that are deliberately left open: whether "Last vitals"
should fall back to the latest ANC contact, whether a revoked grant deserves its
own error code, and whether the backend audits writes that arrive by sync push.
