import '../../core/streams/combine_latest.dart';
import '../../data/local/app_database.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/models.dart';

/// Spec S09: "Local DB builds the same TimelineItem list so the screen works
/// offline; when online, replace with the server list (it is authoritative for
/// titles)."
///
/// This is the local half — a union over visits, documents, pregnancies and ANC
/// contacts, sorted newest first, in the same [TimelineItem] shape the server
/// returns. The screen cannot tell which one it is showing.
Stream<List<TimelineItem>> watchLocalTimeline(
  AppDatabase db,
  String patientId,
) {
  final visits = db.visitsDao.watchByPatient(patientId);
  final documents = db.documentsDao.watchByPatient(patientId);
  final pregnancy = db.pregnanciesDao.watchActiveForPatient(patientId);

  // ANC contacts hang off the pregnancy rather than the patient, so they are
  // folded in from whichever pregnancy is current.
  final contacts = pregnancy.asyncExpand<List<AncContact>>((value) {
    if (value == null) return Stream.value(const <AncContact>[]);
    return db.pregnanciesDao.watchContacts(value.id);
  });

  // Tier 3 added two more sources than `combineLatest4` has slots, so the four
  // clinical streams combine into one and the two child-health streams into
  // another.
  final clinical = combineLatest4<List<Visit>, List<Document>, Pregnancy?,
      List<AncContact>, _Clinical>(
    visits,
    documents,
    pregnancy,
    contacts,
    (v, d, p, c) => _Clinical(v, d, p, c),
  );

  final child = combineLatest2<List<Immunisation>, List<GrowthMeasurement>,
      _Child>(
    db.childHealthDao.watchSchedule(patientId),
    db.childHealthDao.watchGrowth(patientId),
    (i, g) => _Child(i, g),
  );

  return combineLatest2<_Clinical, _Child, List<TimelineItem>>(
    clinical,
    child,
    (c, k) => buildTimeline(
      c.visits,
      c.documents,
      c.pregnancy,
      c.contacts,
      immunisations: k.immunisations,
      growth: k.growth,
    ),
  );
}

class _Clinical {
  const _Clinical(this.visits, this.documents, this.pregnancy, this.contacts);

  final List<Visit> visits;
  final List<Document> documents;
  final Pregnancy? pregnancy;
  final List<AncContact> contacts;
}

class _Child {
  const _Child(this.immunisations, this.growth);

  final List<Immunisation> immunisations;
  final List<GrowthMeasurement> growth;
}

/// Pure, so it can be tested without a database.
///
/// Titles are **pre-formatted here**, matching A.2 ("title: Pre-formatted, e.g.
/// 'Visit — Ghorahi HP — E11 Diabetes'"). The screen renders `item.title`
/// verbatim, so the same widget draws a local row and a server row and the
/// server stays authoritative for wording when it is reachable.
List<TimelineItem> buildTimeline(
  List<Visit> visits,
  List<Document> documents,
  Pregnancy? pregnancy,
  List<AncContact> contacts, {
  List<Immunisation> immunisations = const [],
  List<GrowthMeasurement> growth = const [],
}) {
  final items = <TimelineItem>[
    for (final visit in visits)
      TimelineItem(
        kind: TimelineKind.visit,
        at: visit.visitAt,
        title: _visitTitle(visit),
        subtitle: _visitSubtitle(visit),
        refId: visit.id,
        payload: visit.toJson(),
      ),
    for (final document in documents)
      TimelineItem(
        kind: TimelineKind.document,
        at: document.takenAt,
        title: document.title,
        subtitle: document.type.wire,
        // A.2 allows only green/amber/red or null here. The upload state has
        // its own indicator on S10 and its own row on S17; overloading the
        // triage badge with it would put a fourth colour in a field the rest
        // of the app reads as clinical severity.
        refId: document.id,
        payload: document.toJson(),
      ),
    if (pregnancy != null)
      TimelineItem(
        kind: TimelineKind.pregnancyRegistered,
        at: pregnancy.updatedAt ?? pregnancy.edd,
        title: 'Pregnancy registered',
        subtitle: 'EDD ${pregnancy.edd}',
        refId: pregnancy.id,
        payload: pregnancy.toJson(),
      ),
    // Only contacts that actually happened; the other six are a schedule, not
    // history, and would bury the real entries.
    for (final contact in contacts.where((c) => c.doneAt != null))
      TimelineItem(
        kind: TimelineKind.ancContact,
        at: contact.doneAt!,
        title: 'ANC contact ${contact.contactNo} (week ${contact.weekTarget})',
        subtitle: _contactSubtitle(contact),
        badge: contact.triageLevel?.wire,
        refId: contact.id,
        payload: contact.toJson(),
      ),
    // Tier 3. Only doses actually given: the rest is a schedule, and the
    // child-health screen is where a plan belongs. Same reasoning as the six
    // pending ANC contacts above.
    for (final dose in immunisations.where((d) => d.givenAt != null))
      TimelineItem(
        kind: TimelineKind.immunisation,
        at: dose.givenAt!,
        title: '${dose.vaccineCode} dose ${dose.doseNo}',
        subtitle: dose.batchNo == null ? null : 'Batch ${dose.batchNo}',
        refId: dose.id,
        payload: dose.toJson(),
      ),
    for (final measurement in growth.where((m) => !m.deleted))
      TimelineItem(
        kind: TimelineKind.growth,
        at: measurement.measuredAt,
        title: 'Weight ${measurement.weightKg} kg',
        subtitle: measurement.heightCm == null
            ? null
            : 'Height ${measurement.heightCm} cm',
        refId: measurement.id,
        payload: measurement.toJson(),
      ),
  ];

  items.sort((a, b) => b.at.compareTo(a.at));
  return items;
}

/// Spec S09 replaces the local union with the server's list "when online",
/// because the server is authoritative for wording. Taken literally that hides
/// work this device has not pushed yet: record a visit in airplane mode, let
/// the timeline fetch succeed before the outbox drains, and the visit the
/// health worker just entered disappears from the patient's record in front of
/// her. Found on the phone, where the in-process mock answers a `/timeline`
/// call even with the radio off.
///
/// So the server wins for every row it knows about — its titles carry facility
/// and diagnosis labels the device cannot resolve — and anything only this
/// device has is kept rather than dropped.
List<TimelineItem> mergeTimeline({
  required List<TimelineItem> server,
  required List<TimelineItem> local,
}) {
  final known = server.map((item) => item.refId).toSet();
  final merged = [
    ...server,
    ...local.where((item) => !known.contains(item.refId)),
  ]..sort((a, b) => b.at.compareTo(a.at));

  return merged;
}

/// "Visit — Ghorahi HP — E11", degrading gracefully when the denormalised
/// facility name or the diagnosis is missing.
String _visitTitle(Visit visit) {
  final parts = <String>[
    'Visit',
    if (visit.facilityName != null && visit.facilityName!.isNotEmpty)
      visit.facilityName!,
    if (visit.diagnosisCodes.isNotEmpty)
      visit.diagnosisCodes.join(', ')
    else
      visit.chiefComplaintCode,
  ];
  return parts.join(' — ');
}

String? _visitSubtitle(Visit visit) {
  final parts = <String>[
    if (visit.vitals?.bpSys != null && visit.vitals?.bpDia != null)
      'BP ${visit.vitals!.bpSys}/${visit.vitals!.bpDia}',
    ...visit.diagnosisCodes,
    if (visit.prescriptions.isNotEmpty) '${visit.prescriptions.length} Rx',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String? _contactSubtitle(AncContact contact) {
  final findings = contact.findings;
  final parts = <String>[
    if (findings?.bpSys != null && findings?.bpDia != null)
      'BP ${findings!.bpSys}/${findings.bpDia}',
    if (findings?.hbGdl != null) 'Hb ${findings!.hbGdl}',
    if (contact.referral != null) 'referred',
  ];
  return parts.join(' · ');
}
