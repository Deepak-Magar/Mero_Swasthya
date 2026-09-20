/// Tier 2 — the health-post dashboard (S19 → `/provider/dashboard`).
///
/// One pure function over everything this device has cached. Local only: a
/// health post with no signal still has to be able to answer "who have we lost
/// track of", and that question is about the records already in the bag, not
/// about a report the server would run.
///
/// Every tile carries its rows rather than just a number, because a count
/// nobody can open is a number nobody trusts.
library;

import '../models/enums.dart';
import '../models/models.dart';
import 'anc_schedule.dart';
import 'edd.dart';

/// The tiles, in the order a health worker would read them: who is pregnant and
/// how far along, who has been missed, who was flagged, and what happened.
enum DashboardBucket {
  trimester1,
  trimester2,
  trimester3,
  overdueContacts,
  recentTriage,
  deliveriesThisMonth,
}

/// One row behind a tile.
class DashboardEntry {
  const DashboardEntry({
    required this.patient,
    this.pregnancy,
    this.contact,
    this.delivery,
  });

  final Patient patient;
  final Pregnancy? pregnancy;
  final AncContact? contact;
  final Delivery? delivery;

  @override
  String toString() => 'DashboardEntry(${patient.name})';
}

/// What the dashboard shows, tile by tile.
class ProviderDashboard {
  const ProviderDashboard(this.entries);

  const ProviderDashboard.empty() : entries = const {};

  final Map<DashboardBucket, List<DashboardEntry>> entries;

  List<DashboardEntry> of(DashboardBucket bucket) =>
      entries[bucket] ?? const [];

  int count(DashboardBucket bucket) => of(bucket).length;

  /// True when there is nothing at all to show, which deserves an empty state
  /// rather than six zeroes.
  bool get isEmpty => entries.values.every((rows) => rows.isEmpty);
}

/// Trimester boundaries, the WHO ones the ANC schedule already assumes:
/// first to the end of week 13, second to the end of week 27, third after.
DashboardBucket? trimesterOf(Pregnancy pregnancy, DateTime now) {
  if (pregnancy.status != PregnancyStatus.active) return null;

  final edd = parseIsoDate(pregnancy.edd);
  if (edd == null) return null;

  final weeks = gestationalAgeWeeks(edd, now);
  // A pregnancy past term or with a nonsense EDD is still somebody's
  // pregnancy; clamping it into the third trimester beats dropping it.
  if (weeks < 14) return DashboardBucket.trimester1;
  if (weeks < 28) return DashboardBucket.trimester2;
  return DashboardBucket.trimester3;
}

/// Build the dashboard.
///
/// [monthStart] and [monthEnd] bound "deliveries this month". They are passed
/// in rather than derived because the month a Nepali health post reports on is
/// a Bikram Sambat month, and this layer deliberately knows nothing about
/// calendars.
ProviderDashboard buildProviderDashboard({
  required List<Patient> patients,
  required List<Pregnancy> pregnancies,
  required List<AncContact> contacts,
  required List<Delivery> deliveries,
  required DateTime now,
  required DateTime monthStart,
  required DateTime monthEnd,
  Duration triageWindow = const Duration(days: 7),
}) {
  final byId = {for (final p in patients) p.id: p};
  final livePregnancies =
      pregnancies.where((p) => !p.deleted && byId.containsKey(p.patientId));
  final pregnancyById = {for (final p in pregnancies) p.id: p};

  final result = <DashboardBucket, List<DashboardEntry>>{
    for (final bucket in DashboardBucket.values) bucket: <DashboardEntry>[],
  };

  // --- Pregnancies by trimester ---------------------------------------------
  for (final pregnancy in livePregnancies) {
    final bucket = trimesterOf(pregnancy, now);
    if (bucket == null) continue;
    result[bucket]!.add(
      DashboardEntry(
        patient: byId[pregnancy.patientId]!,
        pregnancy: pregnancy,
      ),
    );
  }

  // --- Overdue contacts ------------------------------------------------------
  //
  // Only for pregnancies that are still open: a contact that came due after the
  // baby arrived is not a woman anybody needs to chase.
  final openPregnancyIds = livePregnancies
      .where((p) => p.status == PregnancyStatus.active)
      .map((p) => p.id)
      .toSet();

  for (final contact in overdueContacts(
    contacts.where((c) => openPregnancyIds.contains(c.pregnancyId)).toList(),
    asOf: now,
  )) {
    final pregnancy = pregnancyById[contact.pregnancyId];
    final patient = pregnancy == null ? null : byId[pregnancy.patientId];
    if (patient == null) continue;

    result[DashboardBucket.overdueContacts]!.add(
      DashboardEntry(
        patient: patient,
        pregnancy: pregnancy,
        contact: contact,
      ),
    );
  }

  // --- Red or amber triage in the window ------------------------------------
  final since = now.subtract(triageWindow);
  for (final contact in contacts) {
    if (contact.deleted) continue;
    final level = contact.triageLevel;
    if (level != TriageLevel.red && level != TriageLevel.amber) continue;

    final doneAt = DateTime.tryParse(contact.doneAt ?? '');
    if (doneAt == null || doneAt.isBefore(since) || doneAt.isAfter(now)) {
      continue;
    }

    final pregnancy = pregnancyById[contact.pregnancyId];
    final patient = pregnancy == null ? null : byId[pregnancy.patientId];
    if (patient == null) continue;

    result[DashboardBucket.recentTriage]!.add(
      DashboardEntry(
        patient: patient,
        pregnancy: pregnancy,
        contact: contact,
      ),
    );
  }

  // --- Deliveries this month -------------------------------------------------
  for (final delivery in deliveries) {
    if (delivery.deleted) continue;

    final at = DateTime.tryParse(delivery.deliveredAt);
    if (at == null || at.isBefore(monthStart) || at.isAfter(monthEnd)) continue;

    final pregnancy = pregnancyById[delivery.pregnancyId];
    final patient = pregnancy == null ? null : byId[pregnancy.patientId];
    if (patient == null) continue;

    result[DashboardBucket.deliveriesThisMonth]!.add(
      DashboardEntry(
        patient: patient,
        pregnancy: pregnancy,
        delivery: delivery,
      ),
    );
  }

  // Red before amber, then most recent first; everything else by name, which is
  // how somebody reads down a list looking for a person they know.
  result[DashboardBucket.recentTriage]!.sort((a, b) {
    final levels = (a.contact!.triageLevel, b.contact!.triageLevel);
    if (levels.$1 != levels.$2) {
      return levels.$1 == TriageLevel.red ? -1 : 1;
    }
    return '${b.contact!.doneAt}'.compareTo('${a.contact!.doneAt}');
  });

  for (final bucket in DashboardBucket.values) {
    if (bucket == DashboardBucket.recentTriage) continue;
    result[bucket]!.sort((a, b) => a.patient.name.compareTo(b.patient.name));
  }

  return ProviderDashboard(result);
}
