# Spec audit — app vs `docs/FRONTEND_SPEC.md`

Audited 2026-09-18 against contract version 2026-09-18.1, before any code changed.

`COMPLIANT` — matches the spec. `PARTIAL` — present but deviates or incomplete.
`MISSING` — not built.

Tier is from §2.2. **Only Tier 1 gaps are in scope for the fix pass**; Tier 2
rows are recorded and deliberately left alone.

---

## Part A.2 — Entities

Every field name and every enum wire value was diffed mechanically against the
spec tables, not read by eye.

| Entity | Status | Reason |
|---|---|---|
| User, Patient, AccessGrant, Visit, Prescription, Document, Pregnancy, BirthPlan, AncContact, Findings, Delivery, Reminder, Facility, AuditEntry, CodeListItem, TimelineItem | COMPLIANT | `lib/domain/models/models.dart` — all field names match 1:1 |
| PatientSummary / ActiveProblem / LastVitals | COMPLIANT | `models.dart:392-430` — `activeProblems`, `currentMedicines`, `allergies`, `lastVitals`, `activePregnancy`, `lastVisitAt`, `visitCount` all present |
| All 25 enums | COMPLIANT | `lib/domain/models/enums.dart` — every `@JsonValue` matches, incl. `birthing_centre`, `on_the_way`, `live_birth`, `record_viewed`, `dangerSign`/`riskFactor` camelCase |
| `Pregnancy.gestationalAgeDays` / `nextContact` | COMPLIANT | Computed-on-read, correctly nullable and never persisted (`mappers.dart:196`) |
| `AncContact.id` determinism | COMPLIANT | `core/ids/ids.dart` — uuid v5 per A.8.15, tested in `test/rules/anc_schedule_test.dart` |

## Part A.4 — Endpoints

| Item | Status | Reason |
|---|---|---|
| All 35 endpoints typed and reachable | COMPLIANT | `lib/data/remote/api/` — mechanical diff of spec headings vs `MockApi` routes returned 35/35 |
| Response wrapper keys (`items`, `patient`, `visit`, `document`, `grant`, `pregnancy`, `ancContact`, `delivery`) | COMPLIANT | `api/json.dart` helpers; each call site uses the spec's key |
| Error codes A.3 | COMPLIANT | `core/errors/app_error.dart` — all 10 codes plus a client-only `NETWORK` |

## §6 — Drift tables

| Item | Status | Reason |
|---|---|---|
| 13 tables, snake_case columns | COMPLIANT | `data/local/app_database.dart`; asserted column-by-column in `test/local/app_database_test.dart` |
| `version` / `updated_at` / `deleted` on syncables | COMPLIANT | Present on all six |
| Device-only `access_until`, `local_path`, `upload_attempts` | COMPLIANT | Preserved across server writes (tested) |
| `outbox`, `sync_meta` keys | COMPLIANT | All seven `sync_meta` keys defined |
| §6.1 encryption | PARTIAL (allowed) | Plain sqlite; spec explicitly permits the fallback, `KeyDerivation` retained |
| §6.2 repositories are the only write path | COMPLIANT | `SyncableRepo.writeAndEnqueue` — row + op in one transaction |

## §7 — Sync engine

| Item | Status | Reason |
|---|---|---|
| `applied` / `duplicate` → upsert + delete op | COMPLIANT | `sync_engine.dart:_pushOutbox` |
| `conflict` → server row wins, op removed, user told | COMPLIANT | `onConflict` callback |
| `rejected` → op kept with message, not retried | COMPLIANT | `outbox.take()` filters `last_error` |
| Batches of 50, `created_at` asc | COMPLIANT | Ordering enforced at enqueue; tested |
| Pull cursor persisted per page, loops on `hasMore` | COMPLIANT | `_pull()` |
| Pull skips rows with a pending outbox op | COMPLIANT | `pendingRowIds()` per page |
| `server_time_offset_ms` | COMPLIANT | `_recordServerTime` |
| Mutex, one cycle at a time | COMPLIANT | Claimed before first `await` |
| Triggers: connectivity, manual kick, 60 s timer | COMPLIANT | `start()` |
| **Trigger: app resume** | **MISSING** | `onResume()` exists but no `AppLifecycleListener` ever calls it — **Tier 1** |
| Upload worker presign→PUT→complete, give up at 5 | COMPLIANT | `upload_worker.dart` |

## §8 — Interceptors

| Item | Status | Reason |
|---|---|---|
| Auth + single-flight refresh + replay once | COMPLIANT | `interceptors.dart`; tested incl. concurrent 401s |
| Envelope unwrap / `AppError` | COMPLIANT | |
| Retry 2× (1 s, 3 s), GET only | COMPLIANT | |
| Debug log | COMPLIANT | |
| Base URL read per request | COMPLIANT | |

## §9 — Providers

| Item | Status | Reason |
|---|---|---|
| auth, config, rules, codelist, family, patient, pregnancy, syncStatus, providerPatients | COMPLIANT | `core/providers.dart` |
| **`patientSummaryProvider`** | **MISSING** | Spec: "GET /patients/:id, fallback: computed locally from visits" — **Tier 1** |
| **`timelineProvider` server refresh** | **PARTIAL** | Local union only; spec wants the server list when online — **Tier 1** |
| `grantProvider` | PARTIAL (accepted) | Implemented as widget state in `share_sheet.dart`; behaviour identical |
| `triagePreviewProvider` | PARTIAL (accepted) | Pure function called inline in S13; behaviour identical |

## §10 — Routes and redirect

| Item | Status | Reason |
|---|---|---|
| All 23 routes | COMPLIANT | `lib/router.dart` |
| Role redirect (no session → S02, locked → S04, `/` → role home) | COMPLIANT | |
| Patient blocked from `/provider/*` | COMPLIANT | |

## §11 — Screens

| Screen | Status | Reason |
|---|---|---|
| S01 Splash | PARTIAL | Bootstrap + gear present; **"refresh accessToken silently if < 1 h remaining" MISSING** — Tier 1 |
| S02 Phone | PARTIAL | **429 shows the generic message, not "Try again in N minutes"** — Tier 1 |
| S03 OTP | COMPLIANT | 6-box, 60 s resend, routes by `hasPin` |
| S04 PIN unlock | PARTIAL | Offline PBKDF2 unlock correct, but **the verifier is not persisted in mock mode** so a restart falls back to phone entry — Tier 1 |
| S05 Set PIN | COMPLIANT | |
| S06 Family | COMPLIANT | Cards, badge, FAB, chip, settings, activate |
| S07 Add/edit patient | COMPLIANT | All fields + the three validations |
| S08 Patient home | PARTIAL | Header/QR/tabs correct; **no summary refresh** (see `patientSummaryProvider`) — Tier 1 |
| S09 Timeline | PARTIAL | **Titles are raw codes, not pre-formatted; `badge: 'pending'` is not a legal value (A.2 allows green/amber/red/null); no server list when online** — Tier 1 |
| S10 Documents | PARTIAL | Capture + compression correct; **grid shows a type icon, not the thumbnail from `local_path`; no pinch-zoom detail** — Tier 1 |
| S11 Register pregnancy | COMPLIANT | LMP/EDD live, steppers, risk checklist, 8 contacts generated locally |
| S12 Pregnancy dashboard | PARTIAL | Header/stepper/birth plan correct; **`nearestReferral` not shown on red contacts** — Tier 1 |
| S13 ANC checklist | PARTIAL | Live triage, danger tiles, referral + call correct; **no warning when the server's triage differs from the local one** — Tier 1 |
| S14 Delivery | PARTIAL | **Tier 2 — not in scope.** Complications chips absent |
| S15 Reminders | COMPLIANT | Kind icon, BS date, recipient, status, demo hint |
| S16 Audit | COMPLIANT | Actor, facility, localised action, cached |
| S17 Sync status | COMPLIANT | Pending count, last sync, Sync now, retry/discard |
| S18 Provider activation | COMPLIANT | |
| S19 Provider home | COMPLIANT | Scan button, granted list, expiry filter |
| S20 Scanner | COMPLIANT | `SWC1:` filter, torch, offline message, caches bundle |
| S21 Provider summary | COMPLIANT | Allergies-first, problems, medicines, vitals, pregnancy, actions |
| S22 Add visit | COMPLIANT | Picklists, vitals, prescriptions, referral, FCHV hides medicines |
| S23 Settings | COMPLIANT | Language, URL + test, versions, refresh, logout |

## §12 — Rules

| Item | Status | Reason |
|---|---|---|
| `eddFromLmp` / `lmpFromEdd` / `gestationalAgeDays` | COMPLIANT | A.6 cases 1–2 pass |
| `generateContacts` | COMPLIANT | A.6 case 1 due dates pass |
| `triage` incl. ordering and red-suppresses-amber | COMPLIANT | A.6 cases 3–11 pass (79 tests) |
| Rules loaded from asset, overridden by newer server version | COMPLIANT | `rules.dart` |

## §13 — BS dates and l10n

| Item | Status | Reason |
|---|---|---|
| BS primary / AD secondary, Nepali numerals | COMPLIANT | `BsDate`, `BsDateText` |
| BS picker on every date field | COMPLIANT | `BsDateField` |
| Full ne/en coverage | COMPLIANT | 305 keys, exact parity, nothing untranslated |

## §14 — QR

| Item | Status | Reason |
|---|---|---|
| `SWC1:` prefix on create and scan-filter | COMPLIANT | `GrantsApi.qrPrefix`, `scan_screen.dart` |
| 10-min countdown, regenerate, revoke | COMPLIANT | `share_sheet.dart` |
| Redeem caches bundle with `access_until` | COMPLIANT | `scan_screen.dart` → `cacheGranted` |

## §15 — Mock API

| Item | Status | Reason |
|---|---|---|
| All 35 endpoints | COMPLIANT | 35/35 by mechanical diff |
| OTP 123456, any 4-digit PIN, 10-min grants, redeem bundle, push `version+1`, pull empty | COMPLIANT | 41 tests |
| Seeded Sita + Ram | COMPLIANT | |
| `AncContact.dueAt` format | PARTIAL | Mock emits full ISO; A.2 says `YYYY-MM-DD` — Tier 1 (contract shape) |

## §16 — UX conventions

| Item | Status | Reason |
|---|---|---|
| Skeleton → content / empty state | COMPLIANT | `asyncView`, `LoadingList`, `EmptyState` |
| **"Saved · synced" when the push lands within 2 s** | **PARTIAL** | Always shows "will sync" — Tier 1 |
| OfflineBanner on provider screens | COMPLIANT | S06, S12, S19, S21 |
| Red banner uses colour AND icon AND text | COMPLIANT | Widget-tested |
| 48 dp tap targets, steppers not typing | COMPLIANT | Widget-tested |
| Allergies always shown, even when empty | COMPLIANT | |

---

## Tier 1 fix list (in spec order)

1. §7 — wire the app-resume sync trigger
2. §9/§11 S08 — `patientSummaryProvider` with local fallback
3. §11 S01 — silent access-token refresh on bootstrap
4. §11 S02 — 429 shows "Try again in N minutes"
5. §11 S04 — persist tokens and PIN verifier in mock mode
6. §11 S09 — pre-formatted titles, legal `badge`, server list when online
7. §11 S10 — real thumbnails + pinch-zoom detail
8. §11 S12 — nearest referral on red contacts
9. §11 S13 — warn when server triage differs from local
10. §15 — mock `dueAt` as `YYYY-MM-DD`
11. §16 — "Saved · synced" when the push lands within 2 s

Explicitly out of scope (Tier 2, §2.2): S14 delivery record, AI summary view,
printed static QR, medicine notifications, facility map.

---

# Final status

All eleven Tier 1 gaps above are **fixed**, plus four more defects found by
running on the Nothing Phone (see `docs/DEVICE_RUN_REPORT.md`).

`flutter analyze` clean · **294 tests passing** · release APK builds and runs on
Android 15 with no exception in logcat.

## Resolved

| # | Gap | Now | How it was verified |
|---|---|---|---|
| 1 | §7 app-resume trigger missing | COMPLIANT | `AppLifecycleListener` in `app.dart`; `kick()` ignored until `start()` so it cannot sync a locked database |
| 2 | §9 `patientSummaryProvider` missing | COMPLIANT | Provider + `summaryFromLocal` fallback, 10 tests |
| 3 | S01 silent token refresh missing | COMPLIANT | `refreshTokenIfExpiringSoon` + `jwtExpiry`, 9 tests |
| 4 | S02 429 message generic | COMPLIANT | Reads `details.retryAfterSec`, falls back to 10 min |
| 5 | S04 PIN not persisted in mock mode | COMPLIANT | `SecureTokenStore` always; **verified on device** — reinstall goes straight to PIN unlock |
| 6 | S09 titles/badge/server list | COMPLIANT | Pre-formatted titles, `badge` restricted to green/amber/red/null, server list when online; 10 tests |
| 7 | S10 no thumbnails or zoom | COMPLIANT | `DocumentThumbnail` + `InteractiveViewer` detail; **verified on device** |
| 8 | S12 no referral on red contacts | COMPLIANT | `_ReferralStrip` + `FacilityCallButton`; **verified on device** |
| 9 | S13 no triage-mismatch warning | COMPLIANT | `onTriageMismatch` + log, 2 tests |
| 10 | §15 mock `dueAt` was a timestamp | COMPLIANT | Now `YYYY-MM-DD` per A.2 |
| 11 | §16 never said "Saved · synced" | COMPLIANT | `showSaveResult` watches the outbox for 2 s |
| D1 | Mock always `hasPin: true` → S05 unreachable | COMPLIANT | 2 tests; **found and verified on device** |
| D2 | S06 never called `GET /patients` | COMPLIANT | `refreshFromServer`, 3 tests; **found and verified on device** |
| D3 | BP steppers could not reach 140/150/160/90/110 | COMPLIANT | Grid-snapped start + tap-to-type, 4 tests; **found and verified on device** |
| D4 | Uploaded document lost its offline thumbnail | COMPLIANT | `local_path` kept; 1 test; **found and verified on device** |

## Still PARTIAL, deliberately

| Item | Why |
|---|---|
| §6.1 database unencrypted | Spec explicitly permits the fallback; `KeyDerivation` written, one call site to change |
| §9 `grantProvider`, `triagePreviewProvider` | Implemented as widget state / a pure call; behaviour identical to the spec's description |
| S21 "current medicines" | Taken from the latest visit offline; the server's summary is authoritative when reachable |
| S14 delivery, AI summary, printed QR, notifications, map | Tier 2 — out of scope by instruction |

## Files changed

**Added**
- `lib/domain/summary.dart`
- `lib/features/documents/document_detail_screen.dart`
- `docs/SPEC_AUDIT.md`, `docs/DEVICE_RUN_REPORT.md`
- `test/features/summary_test.dart`, `test/features/jwt_expiry_test.dart`

**Changed — lib**
- `app.dart` — lifecycle listener
- `router.dart` — unchanged route table, reused
- `core/providers.dart` — `patientSummaryProvider`, `documentRowsProvider`, `SecureTokenStore`, `PatientRepo` gains `Api`
- `core/net/mock_api.dart` — `hasPin` tracking, `dueAt` format
- `features/auth/auth_controller.dart` — `refreshTokenIfExpiringSoon`, `jwtExpiry`
- `features/auth/phone_screen.dart` — 429 message
- `features/splash/splash_screen.dart` — silent refresh call
- `features/family/family_screen.dart` — `GET /patients` on init and refresh
- `features/family/patient_form_screen.dart` — `showSaveResult`
- `features/timeline/local_timeline.dart` — titles, badge
- `features/timeline/timeline_screen.dart` — server list, renders `item.title`
- `features/documents/documents_screen.dart` — rows, thumbnails, detail route
- `features/maternal/pregnancy_dashboard_screen.dart` — referral strip
- `features/maternal/anc_contact_screen.dart` — `showSaveResult`
- `features/maternal/register_pregnancy_screen.dart` — `showSaveResult`
- `features/provider/visit_form_screen.dart` — `showSaveResult`, `ReferralUrgency`
- `features/shared/widgets/app_widgets.dart` — `FacilityCallButton`, stepper grid snap + tap-to-type, `showSaveResult`
- `data/sync/sync_engine.dart` — `kick()` guard, `onTriageMismatch`
- `data/repositories/patient_repo.dart` — `refreshFromServer`
- `data/repositories/reference_repo.dart` — `codelist()`
- `data/local/daos/documents_dao.dart` — `watchRowsByPatient`, `markUploaded` keeps the path

**Changed — test**
- `test/sync/sync_engine_test.dart`, `test/repositories/repositories_test.dart`,
  `test/net/mock_api_test.dart`, `test/features/widgets_test.dart`,
  `test/features/local_timeline_test.dart`
