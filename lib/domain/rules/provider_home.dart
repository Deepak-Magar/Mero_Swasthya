/// The provider Home tab — what a health worker sees first.
///
/// One pure function over everything this device has cached, the same shape as
/// `provider_dashboard.dart` and for the same reason: the screen has to answer
/// "who do I see first, and what is still owed today" with the radio off, so
/// nothing here may depend on a request.
///
/// Every list carries its rows rather than a count. The tiles on the screen
/// each open the list behind them, and a number that cannot be opened is a
/// number nobody trusts.
library;

import '../models/enums.dart';
import '../models/models.dart';
import 'edd.dart';

/// Why somebody is on the needs-attention list, most urgent first.
///
/// The order of the values is the sort order: a red triage outranks an amber
/// one, and both outrank a contact that is merely late.
enum AttentionKind { redTriage, amberTriage, overdueContact }

/// One row of the needs-attention list. One per patient, never two: a woman
/// who was triaged red *and* has missed a contact is one person to chase.
class AttentionItem {
  const AttentionItem({
    required this.patient,
    required this.kind,
    required this.contact,
  });

  final Patient patient;
  final AttentionKind kind;

  /// The contact that was flagged, or the one that is overdue.
  final AncContact contact;

  @override
  String toString() => 'AttentionItem(${patient.name}, ${kind.name})';
}

/// An ANC contact that has not been recorded, with the woman it belongs to.
class DueContact {
  const DueContact({
    required this.patient,
    required this.pregnancy,
    required this.contact,
    required this.dueOn,
  });

  final Patient patient;
  final Pregnancy pregnancy;
  final AncContact contact;

  /// [AncContact.dueAt] as a calendar date.
  final DateTime dueOn;

  @override
  String toString() => 'DueContact(${patient.name}, #${contact.contactNo})';
}

/// A visit recorded today, with the patient it was recorded for.
class VisitToday {
  const VisitToday({required this.patient, required this.visit});

  final Patient patient;
  final Visit visit;
}

/// Everything the provider Home tab and the Reminders tab draw.
class ProviderHome {
  const ProviderHome({
    this.patients = const [],
    this.pregnantPatientIds = const {},
    this.seenToday = const [],
    this.visitsToday = const [],
    this.dueToday = const [],
    this.upcoming = const [],
    this.overdue = const [],
    this.attention = const [],
    this.recentPatients = const [],
    this.pendingSync = 0,
  });

  /// How many rows Home shows under "Needs attention", "Due this week" and
  /// "Recent patients". The lists themselves are complete; the screens that
  /// open from them show the rest.
  static const int homeRowLimit = 5;

  /// Every patient this device may still look at.
  final List<Patient> patients;

  /// Patients with a pregnancy that is still open.
  final Set<String> pregnantPatientIds;

  /// Patients with a visit or an ANC contact recorded today.
  final List<Patient> seenToday;

  /// Visits recorded today, newest first.
  final List<VisitToday> visitsToday;

  /// Contacts due today and not yet recorded.
  final List<DueContact> dueToday;

  /// Contacts due tomorrow through seven days from now.
  final List<DueContact> upcoming;

  /// Contacts whose date has passed with nothing recorded, oldest first.
  final List<DueContact> overdue;

  /// Red or amber in the last 30 days, or an overdue contact. Most urgent
  /// first, one row per patient.
  final List<AttentionItem> attention;

  /// The last patients opened on this phone, topped up from the cache.
  final List<Patient> recentPatients;

  /// Outbox rows that have not reached the server, rejected ones included.
  final int pendingSync;

  /// "Due this week" on Home: today and the seven days after it.
  List<DueContact> get dueThisWeek => [...dueToday, ...upcoming];

  /// The same records with this phone's own state laid over them.
  ///
  /// The recently-opened list and the outbox change far more often than the
  /// clinical tables do, so they arrive on their own stream and are applied
  /// here rather than forcing every count to be recomputed for a tap.
  ProviderHome withDeviceState({
    required List<String> recentPatientIds,
    required int pendingSync,
  }) {
    return ProviderHome(
      patients: patients,
      pregnantPatientIds: pregnantPatientIds,
      seenToday: seenToday,
      visitsToday: visitsToday,
      dueToday: dueToday,
      upcoming: upcoming,
      overdue: overdue,
      attention: attention,
      recentPatients: recentPatientsFrom(patients, recentPatientIds),
      pendingSync: pendingSync,
    );
  }
}

/// Build the Home tab's data.
///
/// [now] is the device's local time: "today" on this screen is the day the
/// health worker is living through, not the UTC date, which in Nepal is still
/// yesterday until a quarter to six in the morning.
///
/// [recentPatientIds] is most-recent-first, as recorded when a summary is
/// opened.
ProviderHome buildProviderHome({
  required List<Patient> patients,
  required List<Pregnancy> pregnancies,
  required List<AncContact> contacts,
  required List<Visit> visits,
  required DateTime now,
  List<String> recentPatientIds = const [],
  int pendingSync = 0,
  Duration triageWindow = const Duration(days: 30),
  int weekDays = 7,
}) {
  final localNow = now.toLocal();
  final today = dateOnly(localNow);
  final weekEnd = today.add(Duration(days: weekDays));

  final byId = {for (final p in patients) p.id: p};
  final pregnancyById = {
    for (final p in pregnancies)
      if (!p.deleted && byId.containsKey(p.patientId)) p.id: p,
  };

  Patient? patientOf(AncContact contact) {
    final pregnancy = pregnancyById[contact.pregnancyId];
    return pregnancy == null ? null : byId[pregnancy.patientId];
  }

  bool isToday(String? instant) {
    final at = DateTime.tryParse(instant ?? '')?.toLocal();
    return at != null && dateOnly(at) == today;
  }

  // --- Today ---------------------------------------------------------------
  final visitsToday = <VisitToday>[
    for (final visit in visits)
      if (!visit.deleted && isToday(visit.visitAt) && byId[visit.patientId] != null)
        VisitToday(patient: byId[visit.patientId]!, visit: visit),
  ]..sort((a, b) => b.visit.visitAt.compareTo(a.visit.visitAt));

  final seenIds = <String>{for (final v in visitsToday) v.patient.id};
  for (final contact in contacts) {
    if (contact.deleted || !isToday(contact.doneAt)) continue;
    final patient = patientOf(contact);
    if (patient != null) seenIds.add(patient.id);
  }
  final seenToday = [
    for (final p in patients)
      if (seenIds.contains(p.id)) p,
  ];

  // --- Contacts still owed ---------------------------------------------------
  //
  // Only for pregnancies that are still open, as on the health-post dashboard:
  // a contact that came due after the baby arrived is nobody to chase.
  final dueToday = <DueContact>[];
  final upcoming = <DueContact>[];
  final overdue = <DueContact>[];

  for (final contact in contacts) {
    if (contact.deleted || contact.doneAt != null) continue;

    final pregnancy = pregnancyById[contact.pregnancyId];
    if (pregnancy == null || pregnancy.status != PregnancyStatus.active) continue;
    final patient = byId[pregnancy.patientId];
    final dueOn = parseIsoDate(contact.dueAt);
    if (patient == null || dueOn == null) continue;

    final row = DueContact(
      patient: patient,
      pregnancy: pregnancy,
      contact: contact,
      dueOn: dueOn,
    );

    if (dueOn.isBefore(today)) {
      overdue.add(row);
    } else if (dueOn == today) {
      dueToday.add(row);
    } else if (!dueOn.isAfter(weekEnd)) {
      upcoming.add(row);
    }
  }

  int byDueThenName(DueContact a, DueContact b) {
    final byDate = a.dueOn.compareTo(b.dueOn);
    return byDate != 0 ? byDate : a.patient.name.compareTo(b.patient.name);
  }

  dueToday.sort(byDueThenName);
  upcoming.sort(byDueThenName);
  overdue.sort(byDueThenName);

  // --- Needs attention -------------------------------------------------------
  final attention = <String, AttentionItem>{};

  void flag(AttentionItem item) {
    final current = attention[item.patient.id];
    if (current == null || item.kind.index < current.kind.index) {
      attention[item.patient.id] = item;
    }
  }

  // Newest flagged contact first, so that when one woman has two ambers the
  // row shows the one a health worker would be asked about.
  final since = localNow.subtract(triageWindow);
  final flagged = [
    for (final contact in contacts)
      if (!contact.deleted &&
          (contact.triageLevel == TriageLevel.red ||
              contact.triageLevel == TriageLevel.amber))
        contact,
  ]..sort((a, b) => '${b.doneAt}'.compareTo('${a.doneAt}'));

  for (final contact in flagged) {
    final doneAt = DateTime.tryParse(contact.doneAt ?? '')?.toLocal();
    if (doneAt == null || doneAt.isBefore(since) || doneAt.isAfter(localNow)) {
      continue;
    }
    final patient = patientOf(contact);
    if (patient == null) continue;

    flag(
      AttentionItem(
        patient: patient,
        kind: contact.triageLevel == TriageLevel.red
            ? AttentionKind.redTriage
            : AttentionKind.amberTriage,
        contact: contact,
      ),
    );
  }

  // `overdue` is oldest first and `flag` only replaces a row with a more
  // urgent one, so the contact kept per patient is the one that has been
  // waiting longest.
  for (final row in overdue) {
    flag(
      AttentionItem(
        patient: row.patient,
        kind: AttentionKind.overdueContact,
        contact: row.contact,
      ),
    );
  }

  final attentionRows = attention.values.toList()
    ..sort((a, b) {
      if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
      if (a.kind == AttentionKind.overdueContact) {
        final byDue = a.contact.dueAt.compareTo(b.contact.dueAt);
        if (byDue != 0) return byDue;
      } else {
        final byDone = '${b.contact.doneAt}'.compareTo('${a.contact.doneAt}');
        if (byDone != 0) return byDone;
      }
      return a.patient.name.compareTo(b.patient.name);
    });

  return ProviderHome(
    patients: patients,
    pregnantPatientIds: {
      for (final p in pregnancyById.values)
        if (p.status == PregnancyStatus.active) p.patientId,
    },
    seenToday: seenToday,
    visitsToday: visitsToday,
    dueToday: dueToday,
    upcoming: upcoming,
    overdue: overdue,
    attention: attentionRows,
    recentPatients: recentPatientsFrom(patients, recentPatientIds),
    pendingSync: pendingSync,
  );
}

/// The "Recent patients" row: opened ones first, in the order they were
/// opened.
///
/// A phone that has synced but not opened anybody yet still has people on it,
/// so the list is topped up from the cache — most recently changed first —
/// rather than left empty.
List<Patient> recentPatientsFrom(
  List<Patient> patients,
  List<String> recentPatientIds,
) {
  final byId = {for (final p in patients) p.id: p};

  final recent = <Patient>[];
  for (final id in recentPatientIds) {
    final patient = byId[id];
    if (patient != null && !recent.contains(patient)) recent.add(patient);
  }

  final rest = patients.where((p) => !recent.contains(p)).toList()
    ..sort((a, b) {
      final byChange = (b.updatedAt ?? '').compareTo(a.updatedAt ?? '');
      return byChange != 0 ? byChange : a.name.compareTo(b.name);
    });

  return [...recent, ...rest].take(ProviderHome.homeRowLimit).toList();
}

/// The stand-in reasons the mock writes when no rule table has been bound yet.
///
/// Part A says a triage reason is human-readable English, and against a real
/// server it always is. A demo phone that synced before the rules loaded holds
/// these three codes instead, and "bp_high" on the first screen of the app
/// reads as a bug.
const Map<String, String> _standInReasons = {
  'bp_high': 'Raised BP (≥140/90)',
  'severe_anaemia': 'Severe anaemia (Hb < 7)',
};

/// The first reason worth showing for a flagged contact, in English, or null
/// when there is none a person could read.
///
/// The caller translates it — this layer knows nothing about locales.
String? firstReadableReason(AncContact contact) {
  for (final raw in contact.triageReasons) {
    final reason = _standInReasons[raw] ?? raw;
    // Anything still shaped like an identifier is a code, not a sentence.
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(reason)) return reason;
  }
  return null;
}
