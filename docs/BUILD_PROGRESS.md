# Build progress — Session 1

Tracks where the build is against `docs/FRONTEND_SPEC.md`. Update this file at
the end of every step; it is the only record of the plan.

Gate for every step: `flutter analyze` clean **and** `flutter test` green.

| # | Step | Spec | State |
|---|------|------|-------|
| 1 | Project scaffold, dependencies, `analysis_options.yaml`, asset seeds (`rules.json`, `codelists.json`, `facilities.json`) | §3, §4 | done |
| 2 | Theme (`core/theme/app_theme.dart`) | §11 | done |
| 3 | Localisation — `app_en.arb`, `app_ne.arb`, generated delegates, `locale_controller.dart` | §13 | done |
| 4 | Core utilities — `config/app_config.dart`, `ids/ids.dart`, `errors/app_error.dart`, `errors/error_messages.dart`, `dates/bs_date.dart`, `crypto/key_derivation.dart` | §5, §6.1, §8 | done |
| 5 | Domain models — freezed/json_serializable mirrors of every Part A entity plus the API envelopes, and the 25 wire enums | A.2 | done |
| 6 | App shell — `main.dart`, `app.dart`, placeholder `router.dart` | §4 | done |
| 7 | **Local database (Drift)** — tables, converters, connection, schema test | §6 | **done** |
| 8 | **DAOs + outbox + repositories (the only write path)** | §6.2 | **done** |
| 9 | **Networking — `net/api_client.dart` (auth / envelope / retry interceptors), `net/mock_api.dart`** | §8, §15 | **done** |
| 10 | **Sync engine + upload worker, `test/sync/sync_engine_test.dart`** | §7 | **done** |
| 11 | **Rules engine — `edd.dart`, `anc_schedule.dart`, `triage.dart`, `rules.dart`; tests from Part A.6** | A.5, A.6 | **done** |
| 12 | **Router S01–S23 with role redirect, providers, and the feature screens** | §10, §11 | **done** |

## Step 7 — what landed

- `lib/data/local/app_database.dart` — all 13 tables from §6 with the exact
  snake_case column names the backend contract uses. Drift row classes are
  suffixed `Row` (`PatientRow`, `VisitRow`, …) so they never collide with the
  freezed domain models of the same name.
- `lib/data/local/converters.dart` — enum columns store the Part A **wire**
  string (`pending_upload`, not `pendingUpload`); nested objects and arrays
  store the same JSON the network layer sends. An unknown enum value from a
  newer server falls back to a known member instead of throwing, so one new
  server code cannot brick the timeline.
- `lib/data/local/connection.dart` — the single place that opens the file.
- `test/local/app_database_test.dart` — 13 tests covering the table list, the
  `patients`/`outbox` column lists, the composite `(kind, code)` key, converter
  round-trips and `clearAll`.

## Step 8 — what landed

- `lib/data/local/mappers.dart` — row ↔ model extensions for all eleven
  entities. Device-only columns (`access_until`, `local_path`,
  `upload_attempts`) are left `Value.absent()`, so a row arriving from the
  server cannot wipe them; there is a test for exactly that.
- `lib/data/local/daos/` — `PatientsDao`, `VisitsDao`, `DocumentsDao`,
  `PregnanciesDao`, `CacheDao`, `SyncMetaDao`. Each syncable DAO has
  `upsertFromServer` (unconditional, for a push result) and `upsertIfNewer`
  (version compare, for a pull).
- `lib/data/local/outbox.dart` — `enqueue`, `take(50)`, `remove`, `markError`,
  `markAttempt`, `retry`, `watchFailed`, `watchPendingCount`, `hasPendingOp`.
- `lib/data/repositories/` — `PatientRepo`, `VisitRepo`, `DocumentRepo`,
  `PregnancyRepo` over a shared `SyncableRepo.writeAndEnqueue`, plus the
  `SyncKicker` seam the sync engine implements in step 10.
- `lib/data/sync/sync_payload.dart` — `toSyncJson()` per entity.
- `lib/core/streams/combine_latest.dart` — `combineLatest4`, used by
  `watchBundle`.
- `test/local/outbox_test.dart` (11) and `test/repositories/repositories_test.dart`
  (29).

## Step 9 — what landed

- `lib/core/net/api_transport.dart` — the seam. Four verbs plus `uploadBytes`,
  each returning the envelope's **unwrapped** `data`, or throwing `AppError`.
- `lib/core/net/api_client.dart` + `interceptors.dart` — Dio with the four
  interceptors from §8 in order: auth/refresh, envelope, GET retry, debug log.
- `lib/core/net/token_store.dart` — `SecureTokenStore` over
  `flutter_secure_storage` plus an `InMemoryTokenStore` for tests and mock mode.
- `lib/data/remote/api/` — `AuthApi`, `PatientsApi`, `GrantsApi`,
  `DocumentsApi`, `PregnanciesApi`, `ReferenceApi`, `SyncApi`, bundled behind
  `Api`. All 35 Part A endpoints, returning freezed models.
- `lib/core/net/mock_api.dart` — every endpoint against in-memory maps, seeded
  with Sita (week-30 pregnancy) and Ram (diabetes, one visit).
- `lib/data/repositories/reference_repo.dart` — the `ReminderRepo` /
  `AuditRepo` / `CodelistRepo` trio deferred in step 8, now that they have a
  refresh to wrap. Also seeds codelists and facilities from the shipped assets.
- `test/net/api_client_test.dart` (17), `test/net/mock_api_test.dart` (41),
  `test/repositories/reference_repo_test.dart` (14).

## Step 10 — what landed

- `lib/data/sync/sync_engine.dart` — the §7 cycle: push, upload, pull, under a
  mutex, with connectivity / resume / kick / 60-second-timer triggers. Also the
  S17 actions `retry` and `discard`.
- `lib/data/sync/upload_worker.dart` — presign → PUT → complete, counting
  attempts and giving up at five.
- `lib/data/sync/connectivity.dart` — `ConnectivityMonitor` over
  `connectivity_plus`, plus `AlwaysOnline` for mock mode and tests.
- `lib/data/sync/sync_status.dart` — `SyncStatus` (the S17 panel and the app-bar
  chip) and `SyncOutcome` (what one cycle did).
- `test/support/transports.dart` — `FlakyTransport`, `FakeSyncTransport`,
  `FakeConnectivity`, shared across test files.
- `test/sync/sync_engine_test.dart` (31) and `test/sync/upload_worker_test.dart`
  (9).

## Step 11 — what landed

- `lib/domain/rules/rules.dart` — the RULES loader: shipped asset, replaced by
  the server's table when its version is newer.
- `edd.dart`, `anc_schedule.dart`, `triage.dart`, `reminders_preview.dart`.
- `test/rules/` — 79 tests, including every case in A.6 that the app can hold
  (3–11 for triage, 1–2 for dates; 12–16 are server-side and are covered in
  `mock_api_test.dart`).

## Step 12 — what landed

- `lib/core/providers.dart` — the composition root, spec §9's provider table.
- `lib/features/auth/auth_controller.dart` — `AuthState{user, unlocked, hasPin}`.
- `lib/router.dart` — all of S01–S23 with the §10 role redirect.
- `lib/features/shared/widgets/` — `BsDateText`, `TriageBanner`, `TriageDot`,
  `SyncChip`, `OfflineBanner`, `PendingDot`, `NumberStepper`, `PicklistField`,
  `BsDateField`, `EmptyState`, `LoadingList`, `ErrorState`.
- All 23 screens, under `lib/features/`.
- 200 more localisation keys, in English and Nepali.
- `test/features/` — 22 tests over the local timeline builder and the shared
  widgets.
- `flutter build apk --debug --dart-define=MOCK_API=true` succeeds.

## Decisions worth remembering

- **Database is unencrypted.** Spec §6.1 allows shipping without SQLCipher.
  `core/crypto/key_derivation.dart` already implements the PBKDF2 derivation, and
  `openAppDatabase()` is the only call site to change later.
- **No `applyWorkaroundToOpenSqlite3OnOldAndroidVersions()`.** `sqlite3` 3.x
  bundles its own native library, which is why `sqlite3_flutter_libs` is pinned
  at the no-op `0.6.0+eol` release. Calling it does not compile.
- **Dates are `String` everywhere** — ISO-8601 in the DB and in the models,
  exactly as Part A sends them. BS is a display concern (`core/dates/bs_date.dart`).
- **`outbox.table_name`** is declared as the Dart getter `targetTable` because
  drift's `Table` already has a `tableName` member; the SQL column name is
  unchanged.

### From step 8

- **Outbox ordering is enforced, not assumed.** `enqueue` reads
  `MAX(created_at)` and, if the clock has not moved, adds a millisecond. Ties
  would let `ORDER BY created_at` send a child row before its parent — a
  delivery before the pregnancy it ends, for instance.
- **Rejected ops are not retried automatically.** `take()` skips rows with a
  `last_error`; S17 offers retry (clears the message) or discard. They still
  count as pending for `hasPendingOp`, so a pull cannot overwrite the local row
  behind the user's back.
- **`baseVersion` is read from the database, never from the caller**, so a
  screen holding a stale object cannot claim to be editing version 0.
- **Registering a pregnancy queues only the pregnancy.** Its eight ANC contacts
  are written locally for the checklist and pushed individually as they are
  filled in; the deterministic uuid v5 ids (A.8.15) make the server's own eight
  converge onto the same rows.
- **No rxdart.** It is not in the lock file and adding it needs network, so
  `combineLatest4` is written out in `core/streams/`.

### From step 9

- **The mock sits at the transport seam, not above it.** `MockApi` implements
  `ApiTransport`, so there is one copy of each endpoint method in the app and
  mock mode cannot drift out of shape. `Api(MockApi())` versus
  `Api(ApiClient(...))` is the entire switch.
- **`validateStatus` is left at Dio's default, deliberately.** A non-2xx must
  arrive as a `DioException` so it enters the *error* chain at interceptor 1,
  where the auth interceptor can see the 401 and refresh. Accepting every status
  instead makes the envelope interceptor reject from the *response* chain, which
  resumes after it and skips the refresh entirely. There is a test for the
  refresh-and-replay path.
- **Refresh is single-flight.** Several requests failing at once share one
  `/auth/refresh`; a replayed request is marked so one expired token cannot
  start a loop.
- **Only GETs are retried.** Replaying a POST that may already have been applied
  turns one consultation into two visits. Writes go through the outbox, which is
  idempotent by `opId`.
- **`ApiClient` takes `String Function() baseUrl`, not `AppConfig`** — the net
  layer should not know about shared_preferences, and it keeps the client
  testable without a Flutter binding. Still read per request, per §5.
- **A refresh may fail; a cache may not be emptied.** Every `ReferenceRepo`
  refresh returns a bool and swallows `AppError`, leaving the cached rows the
  user is looking at in place.

### Bug found by these tests

`MockApi` seeded a codelist with `kind: 'danger_sign'`. Spec line 1560 and
`assets/codelists.json` both use **camelCase** `dangerSign`, and so does the
`CodeListKind` enum. The models were right and the mock was wrong; fixed, and
`reference_repo_test.dart` now asserts every `CodeListKind` value parses out of
the shipped asset.

### From step 10

- **The mutex is claimed before the first `await`.** Checking `_running` and
  then awaiting the connectivity probe let two near-simultaneous kicks both pass
  the test and run overlapping cycles. Caught by
  `test/sync/sync_engine_test.dart`, "a second cycle is skipped while one is
  running".
- **A kick that arrives mid-cycle is remembered, not dropped.** The mutex makes
  it a no-op per §7, but silently discarding it leaves a health worker looking at
  a pending icon until the next 60-second tick.
- **Cycle order is push → upload → pull, and it is not arbitrary.** Push first so
  the user's own work leaves soonest and the following pull already contains it;
  uploads next because a document's metadata row must exist server-side before
  its bytes are presigned; pull last so the cycle ends with the device whole.
- **`duplicate` is success.** It means the previous attempt landed and only the
  response was lost.
- **A rejected op is never retried automatically**, but it still counts as
  pending for `hasPendingOp`, so a pull cannot overwrite the local row behind the
  user's back.
- **One bad row never strands the cursor.** An unknown table or an unparseable
  row is logged and skipped; the cursor still advances, or every later page is
  blocked for good.
- **A missing image file is abandoned immediately**, burning all five attempts in
  one pass. Retrying cannot bring back bytes the OS reclaimed.

### From step 11

- **Every date is reduced to a UTC calendar date first.** Kathmandu is UTC+05:45;
  naive arithmetic on a local `DateTime` lands a day out often enough to break
  the shared A.6 cases, and an EDD that moves by a day moves all eight contacts
  with it.
- **An unmeasured haemoglobin is not anaemia.** The `?? 99` fallback in triage is
  deliberate: reading "not taken" as zero would make every unmeasured contact
  red.
- **A danger-sign code this build has never heard of is ignored, not fatal**, so
  a newer rule table on the server cannot crash an older phone.
- **Red is evaluated fully before amber is considered**, per §12, so a red
  pregnancy is never also told it is amber.

### From step 12

- **`explicit_to_json: true` in `build.yaml`.** json_serializable's default
  emits `'vitals': instance.vitals` — a nested *object*. That survives a
  `jsonEncode` (the encoder calls `toJson` itself), so the outbox and the wire
  were fine, but handing a `toJson()` result straight back to a `fromJson`
  threw. The locally built timeline does exactly that with
  `TimelineItem.payload`. Caught by `test/features/local_timeline_test.dart`.
- **Shared widgets read the locale from `Localizations.localeOf(context)`**, not
  from `effectiveLocaleProvider`. `MaterialApp` has already resolved it, and the
  provider reaches into shared_preferences, which made every leaf widget
  untestable in isolation.
- **The sync engine is started in S04/S05, not in `main`.** It must not run
  before the PIN unlocks the database — and when SQLCipher replaces the plain
  build, that is where the key will be derived.
- **`MockApi` had the wrong ANC schedule** — `[12,16,20,24,…]` against the
  spec's and the asset's `[12,20,26,30,34,36,38,40]`. Found while writing the
  A.6 schedule tests; the weeks now come from the rule table.
- **`MockApi` runs the real triage when given the rule table**, so a demo on
  mock mode exercises the same code the backend will. `mockRulesBinderProvider`
  hands it over after load, which is also what keeps the provider graph acyclic.

## What is not done

Session 1 built the whole app end to end, but these are worth knowing before a
device rehearsal:

- **No widget tests for the screens themselves** — only for the shared widgets
  and the timeline builder. The 23 screens are covered by the analyzer and a
  successful APK build, not by tests.
- **Tier 2 items are untouched** by design (spec §2.2): AI summary view, printed
  static QR, medicine notifications, the facility map.
- **`S10` shows a type icon rather than the captured thumbnail**, and the
  document detail view with pinch-zoom is not built.
- **The database is unencrypted** (§6.1 fallback) — see above.
- **Nothing has run on a physical device yet.**

---

## Tier 2 — done

Superseded by `docs/TIER2_HANDOFF.md`, which is the authority on what Tier 2
built, how it was verified and what it left open. In short: all seven Tier 2
items (printed card + PIN, delivery record, AI draft summary, facility map,
medicine reminders with Nepali audio, health-post dashboard, regression and
packaging) are built and were verified on a physical phone. 435 tests, analyzer
clean, the Part A contract unchanged.

The "What is not done" list above is now out of date in three places: the Tier 2
items are built, `S10` has a real thumbnail and a pinch-zoom detail view, and the
app has been run on hardware extensively. The database is still unencrypted, and
there are still no widget tests for most of the 23 screens — Tier 2 added them
only for the screens it touched.

---

## Tier 3 — done

Superseded by `docs/TIER3_HANDOFF.md`, and by `docs/CONTRACT_ADDENDUM.md` for
everything the backend has to implement. In short: the child immunisation and
growth module, fine-grained consent on QR grants, Nepali voice notes, PDF export
and honest integration placeholders are all built and verified on a physical
phone. 533 tests, analyzer clean, **Part A unchanged** — every addition is a new
table, a new optional field or a new enum value an older client skips.
