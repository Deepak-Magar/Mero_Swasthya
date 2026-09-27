import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import '../data/remote/api/api.dart';
import '../data/repositories/child_health_repo.dart';
import '../data/repositories/document_repo.dart';
import '../data/repositories/patient_repo.dart';
import '../data/repositories/pregnancy_repo.dart';
import '../data/repositories/reference_repo.dart';
import '../data/repositories/visit_repo.dart';
import '../data/sync/connectivity.dart';
import '../data/sync/sync_engine.dart';
import '../data/sync/sync_status.dart';
import 'dates/bs_date.dart';
import 'streams/combine_latest.dart';
import '../domain/models/enums.dart';
import '../domain/models/models.dart';
import '../domain/rules/epi_schedule.dart';
import '../domain/rules/growth_reference.dart';
import '../domain/rules/provider_dashboard.dart';
import '../domain/rules/rules.dart';
import '../domain/summary.dart';
import '../features/export/patient_pdf_service.dart';
import '../features/reminders/medicine_notifications.dart';
import '../features/reminders/medicine_speech.dart';
import 'errors/app_error.dart';
import 'config/app_config.dart';
import 'net/api_client.dart';
import 'net/api_transport.dart';
import 'net/mock_api.dart';
import 'net/token_store.dart';

/// The composition root (spec §9).
///
/// Everything below this file is constructed here and nowhere else, so there is
/// exactly one database, one sync engine and one transport in the process. The
/// screens only ever see providers.

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

/// Overridden in `main()` once the database has been opened after PIN unlock.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Always the real secure storage, mock mode included.
///
/// An in-memory store here meant a restart lost the PIN verifier, so the app
/// fell back to phone entry instead of the S04 unlock — which is precisely the
/// offline path spec S04 exists to demonstrate. `flutter_secure_storage` works
/// on device regardless of which transport is behind the API.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Set when the refresh token is refused, so the router can send the user back
/// to S04 from wherever they are.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// Which transport S23's switch has selected.
///
/// A separate provider so flipping the switch rebuilds
/// [apiTransportProvider] — and everything downstream of it — rather than
/// leaving a stale client behind.
final useMockServerProvider = StateProvider<bool>(
  (ref) => ref.watch(appConfigProvider).useMockServer,
);

final apiTransportProvider = Provider<ApiTransport>((ref) {
  // The mock takes no rule table here on purpose: loading one can go over the
  // wire, and reading `rulesProvider` from the thing that serves it would be a
  // cycle. `mockRulesBinderProvider` hands it over once it has loaded.
  final config = ref.watch(appConfigProvider);

  if (ref.watch(useMockServerProvider)) {
    return MockApi(
      activatedRole: config.mockActivatedRole,
      activatedName: config.mockUserName,
      onActivated: config.setMockActivatedRole,
      onNamed: config.setMockUserName,
    );
  }

  return ApiClient(
    baseUrl: () => config.baseUrl,
    tokens: ref.watch(tokenStoreProvider),
    onSessionExpired: () =>
        ref.read(sessionExpiredProvider.notifier).state = true,
  );
});

final apiProvider = Provider<Api>((ref) => Api(ref.watch(apiTransportProvider)));

/// Gives [MockApi] the real rule table once it is available, so a demo running
/// on the mock computes triage with the same code the backend will.
///
/// Watched by the bootstrap screen; a no-op against a real server.
final mockRulesBinderProvider = Provider<void>((ref) {
  final transport = ref.watch(apiTransportProvider);
  final rules = ref.watch(rulesProvider).valueOrNull;
  if (transport is MockApi && rules != null) transport.rules = rules;
});

final connectivityProvider = Provider<ConnectivityMonitor>((ref) {
  // The device's own answer, on both transports.
  //
  // Mock mode used to report a permanent `AlwaysOnline`, on the reasoning that
  // an in-process mock cannot be unreachable. True, and it made spec §17 item 3
  // — airplane mode, add a visit, pending icon, network back, synced —
  // impossible to demonstrate at all, because the demo runs on the mock. The
  // queue is what is being shown, not the socket, so the phone's own
  // connectivity is the right input for the chip and for the sync gate either
  // way. `AlwaysOnline` remains for tests, which have no platform channel.
  return PluginConnectivityMonitor();
});

// ---------------------------------------------------------------------------
// Sync
// ---------------------------------------------------------------------------

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: ref.watch(databaseProvider),
    api: ref.watch(apiProvider),
    connectivity: ref.watch(connectivityProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Spec §9 `syncStatusProvider`: the S17 panel and the app-bar chip.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  return ref.watch(syncEngineProvider).status;
});

// ---------------------------------------------------------------------------
// Repositories — the only write path (spec §6.2)
// ---------------------------------------------------------------------------

final patientRepoProvider = Provider<PatientRepo>(
  (ref) => PatientRepo(
    ref.watch(databaseProvider),
    ref.watch(syncEngineProvider),
    ref.watch(apiProvider),
  ),
);

final visitRepoProvider = Provider<VisitRepo>(
  (ref) => VisitRepo(ref.watch(databaseProvider), ref.watch(syncEngineProvider)),
);

final documentRepoProvider = Provider<DocumentRepo>(
  (ref) =>
      DocumentRepo(ref.watch(databaseProvider), ref.watch(syncEngineProvider)),
);

final pregnancyRepoProvider = Provider<PregnancyRepo>(
  (ref) =>
      PregnancyRepo(ref.watch(databaseProvider), ref.watch(syncEngineProvider)),
);

final childHealthRepoProvider = Provider<ChildHealthRepo>(
  (ref) =>
      ChildHealthRepo(ref.watch(databaseProvider), ref.watch(syncEngineProvider)),
);

final referenceRepoProvider = Provider<ReferenceRepo>(
  (ref) => ReferenceRepo(ref.watch(databaseProvider), ref.watch(apiProvider)),
);

// ---------------------------------------------------------------------------
// Reference data
// ---------------------------------------------------------------------------

/// The shipped rule table, replaced by the server's when that one is newer.
///
/// Kept alive for the life of the app: triage runs on every keystroke in S13,
/// and re-reading a JSON asset for each one would be absurd.
final rulesProvider = FutureProvider<Rules>((ref) async {
  ref.keepAlive();
  final shipped = await Rules.loadFromAsset();
  // Nothing newer can exist in mock mode, and asking would be pointless.
  if (ref.watch(useMockServerProvider)) return shipped;

  try {
    final fromServer =
        Rules.fromJson(await ref.read(apiProvider).reference.rules());
    return shipped.preferNewer(fromServer);
  } on Object {
    // A protocol table that is a version behind beats no protocol table.
    return shipped;
  }
});

/// Feature flags, with the cached copy as a fallback (spec §5).
final configFlagsProvider = FutureProvider<AppConfigFlags>((ref) async {
  try {
    return await ref.read(apiProvider).reference.config();
  } on Object {
    return const AppConfigFlags();
  }
});

final codelistProvider =
    StreamProvider.family<List<CodeListItem>, CodeListKind>((ref, kind) {
  return ref.watch(referenceRepoProvider).watchCodelist(kind);
});

final facilitiesProvider = StreamProvider<List<Facility>>((ref) {
  return ref.watch(referenceRepoProvider).watchFacilities();
});

// ---------------------------------------------------------------------------
// Patients
// ---------------------------------------------------------------------------

/// S06: the profiles this account owns.
final familyProvider =
    StreamProvider.family<List<Patient>, String>((ref, ownerUserId) {
  return ref.watch(patientRepoProvider).watchFamily(ownerUserId);
});

/// S19: patients cached through a QR grant that has not expired.
///
/// `autoDispose` is load-bearing. The cut-off is bound into the query when the
/// stream is subscribed, so a provider kept alive for the life of the app went
/// on listing records whose window had closed hours earlier — found on the
/// handset with the clock moved forward a day. Disposing it when S19 goes away
/// means the list is re-asked with the current time every time it is opened.
final grantedPatientsProvider =
    StreamProvider.autoDispose<List<Patient>>((ref) {
  return ref.watch(patientRepoProvider).watchGranted();
});

/// Whether this device's grant for [patientId] has run out.
///
/// False for an owned record, which has no window at all. `autoDispose` for
/// the same reason as [grantedPatientsProvider]: "now" has to be read when the
/// screen is opened, not once per launch.
final grantExpiredProvider =
    StreamProvider.autoDispose.family<bool, String>((ref, patientId) {
  return ref
      .watch(patientRepoProvider)
      .watchAccessUntil(patientId)
      .map((until) => until != null && !until.isAfter(DateTime.now().toUtc()));
});

final patientProvider = StreamProvider.family<Patient?, String>((ref, id) {
  return ref.watch(patientRepoProvider).watchById(id);
});

/// Which family member the patient-side Home tab is showing.
///
/// Session state, not a preference: it is "who am I looking at right now",
/// which the avatar strip sets and the four tabs all read. Null means "not
/// chosen yet", and Home then falls back to the first member — otherwise a
/// fresh install would open on an empty record with a full family behind it.
///
/// It lives here rather than inside the shell because the Records, Documents
/// and More tabs need the same answer and must not be able to disagree with
/// Home about it.
final selectedMemberProvider = StateProvider<String?>((ref) => null);

/// Spec §9: "GET /patients/:id, fallback: computed locally from visits".
///
/// The fallback is the point — S08 and S21 must render a usable summary from
/// the cached record when the request fails, not an error state.
final patientSummaryProvider =
    FutureProvider.family<PatientSummary, String>((ref, patientId) async {
  // Rebuild when the local record changes, so an offline summary is not stale
  // after the provider records a visit.
  final patient = await ref.watch(patientProvider(patientId).future);
  final visits = await ref.watch(visitsProvider(patientId).future);
  final pregnancy = await ref.watch(activePregnancyProvider(patientId).future);

  try {
    return (await ref.read(apiProvider).patients.detail(patientId)).summary;
  } on AppError {
    return summaryFromLocal(
      patient: patient,
      visits: visits,
      pregnancy: pregnancy,
      codes: await ref.read(referenceRepoProvider).codelist(
            CodeListKind.diagnosis,
          ),
    );
  }
});

final visitsProvider =
    StreamProvider.family<List<Visit>, String>((ref, patientId) {
  return ref.watch(visitRepoProvider).watchByPatient(patientId);
});

final documentsProvider =
    StreamProvider.family<List<Document>, String>((ref, patientId) {
  return ref.watch(documentRepoProvider).watchByPatient(patientId);
});

/// Rows, not models: S10 draws the thumbnail from the device-only `local_path`
/// and shows the upload-attempt state.
final documentRowsProvider =
    StreamProvider.family<List<DocumentRow>, String>((ref, patientId) {
  return ref.watch(databaseProvider).documentsDao.watchRowsByPatient(patientId);
});

final remindersProvider =
    StreamProvider.family<List<Reminder>, String>((ref, patientId) {
  return ref.watch(referenceRepoProvider).watchReminders(patientId);
});

final auditProvider =
    StreamProvider.family<List<AuditEntry>, String>((ref, patientId) {
  return ref.watch(referenceRepoProvider).watchAudit(patientId);
});

// ---------------------------------------------------------------------------
// Maternal
// ---------------------------------------------------------------------------

final activePregnancyProvider =
    StreamProvider.family<Pregnancy?, String>((ref, patientId) {
  return ref.watch(pregnancyRepoProvider).watchActiveForPatient(patientId);
});

/// The newest pregnancy for a patient, delivered ones included.
///
/// S06's badge uses this so a closed pregnancy reads "Delivered" instead of
/// vanishing; anything that must only act on an open one keeps using
/// [activePregnancyProvider].
final latestPregnancyProvider =
    StreamProvider.family<Pregnancy?, String>((ref, patientId) {
  return ref.watch(pregnancyRepoProvider).watchLatestForPatient(patientId);
});

final pregnancyBundleProvider =
    StreamProvider.family<PregnancyBundle, String>((ref, pregnancyId) {
  return ref.watch(pregnancyRepoProvider).watchBundle(pregnancyId);
});

/// Whether this device's access to [patientId] is read-only.
///
/// Set by the redeem in S20 from the grant's scope, and true for A.7's printed
/// card. A patient's own record is never read-only, so an absent key is false.
/// When this device's copy of [patientId] came off a patient's phone as an
/// offline snapshot, or null when it arrived the ordinary way.
final offlineSnapshotAtProvider =
    StreamProvider.family<DateTime?, String>((ref, patientId) {
  return ref
      .watch(databaseProvider)
      .syncMetaDao
      .watchOfflineSnapshotAt(patientId);
});

final readOnlyAccessProvider =
    StreamProvider.family<bool, String>((ref, patientId) {
  return ref.watch(databaseProvider).syncMetaDao.watchReadOnlyAccess(patientId);
});

// ---------------------------------------------------------------------------
// Tier 3 — PDF export
// ---------------------------------------------------------------------------

/// Builds a printable record entirely from the local database.
final patientPdfServiceProvider = Provider<PatientPdfService>((ref) {
  return PatientPdfService(
    db: ref.watch(databaseProvider),
    patients: ref.watch(patientRepoProvider),
    visits: ref.watch(visitRepoProvider),
    pregnancies: ref.watch(pregnancyRepoProvider),
    childHealth: ref.watch(childHealthRepoProvider),
  );
});

// ---------------------------------------------------------------------------
// Tier 3 — child health
// ---------------------------------------------------------------------------

/// The national EPI schedule, from the shipped asset.
///
/// Kept alive: it is read every time a child screen opens and whenever a new
/// under-five is registered, and it is a few kilobytes of JSON.
final epiScheduleProvider = FutureProvider<EpiSchedule>((ref) async {
  ref.keepAlive();
  return EpiSchedule.loadFromAsset();
});

/// The WHO weight-for-age band, birth to five years. See the asset's
/// `source` block for where every number came from.
final growthReferenceProvider = FutureProvider<GrowthReference>((ref) async {
  ref.keepAlive();
  return GrowthReference.loadFromAsset();
});

final immunisationScheduleProvider =
    StreamProvider.family<List<Immunisation>, String>((ref, patientId) {
  return ref.watch(childHealthRepoProvider).watchSchedule(patientId);
});

final growthMeasurementsProvider =
    StreamProvider.family<List<GrowthMeasurement>, String>((ref, patientId) {
  return ref.watch(childHealthRepoProvider).watchGrowth(patientId);
});

// ---------------------------------------------------------------------------
// Tier 2 — the health-post dashboard
// ---------------------------------------------------------------------------

/// Everything cached on this device, aggregated into S19's dashboard tiles.
///
/// Four Drift streams behind one provider, so the screen repaints when a visit
/// is recorded or a delivery arrives on a sync without anybody refreshing.
/// Entirely local: a health post with no signal still has to be able to answer
/// "who have we lost track of".
final providerDashboardProvider = StreamProvider<ProviderDashboard>((ref) {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();

  return combineLatest4<List<Patient>, List<Pregnancy>, List<AncContact>,
      List<Delivery>, ProviderDashboard>(
    db.patientsDao.watchCachedForProvider(now.toUtc().toIso8601String()),
    db.pregnanciesDao.watchAllPregnancies(),
    db.pregnanciesDao.watchAllContacts(),
    db.pregnanciesDao.watchAllDeliveries(),
    (patients, pregnancies, contacts, deliveries) {
      final month = currentBsMonth(now);
      return buildProviderDashboard(
        patients: patients,
        pregnancies: pregnancies,
        contacts: contacts,
        deliveries: deliveries,
        now: now,
        monthStart: month.start,
        monthEnd: month.end,
      );
    },
  );
});

// ---------------------------------------------------------------------------
// Tier 2 — medicine reminders and speech
// ---------------------------------------------------------------------------

/// One plugin instance for the process. Initialised by the bootstrap screen.
final medicineNotificationsProvider = Provider<MedicineNotifications>((ref) {
  return MedicineNotifications();
});

/// One engine, kept alive: creating a `FlutterTts` per row means the first tap
/// on each prescription is silent while the platform warms up.
final medicineSpeechProvider = Provider<MedicineSpeech>((ref) {
  final speech = MedicineSpeech();
  ref.onDispose(speech.stop);
  return speech;
});

/// Tier 3 — the sections the grant for [patientId] covers.
///
/// Empty means the whole record, which is what a grant meant before
/// fine-grained consent existed and what an owned record always means.
final grantSectionsProvider =
    StreamProvider.family<List<GrantSection>, String>((ref, patientId) {
  return ref
      .watch(databaseProvider)
      .syncMetaDao
      .watchGrantSections(patientId)
      .map(
        (raw) =>
            raw.map(GrantSection.fromWire).whereType<GrantSection>().toList(),
      );
});

/// Rows with a queued op, for the "pending" cloud icon (spec §7).
final pendingRowIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(databaseProvider).outboxDao.watchPendingRowIds();
});
