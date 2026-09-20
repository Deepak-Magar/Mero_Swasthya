import 'models/models.dart';

/// Builds the summary block (spec A.2 / `GET /patients/:id`) from what the
/// device already holds.
///
/// Spec §9 makes this the fallback for `patientSummaryProvider`: when the
/// request fails, S08 and S21 must still show allergies, problems, medicines
/// and last vitals from the cached record. A provider standing in a house with
/// no signal needs the allergy row more than they need an error.
///
/// Pure, so it can be tested without a database or a server.
PatientSummary summaryFromLocal({
  required Patient? patient,
  required List<Visit> visits,
  Pregnancy? pregnancy,
  List<CodeListItem> codes = const [],
}) {
  if (patient == null) return const PatientSummary();

  // Visits arrive newest-first from the DAO, but the caller may not guarantee
  // it, so sort rather than assume.
  final ordered = [...visits.where((v) => !v.deleted)]
    ..sort((a, b) => b.visitAt.compareTo(a.visitAt));
  final latest = ordered.isEmpty ? null : ordered.first;

  final labels = {for (final code in codes) code.code: code};

  return PatientSummary(
    activeProblems: [
      for (final code in patient.chronicConditions)
        ActiveProblem(
          code: code,
          labelEn: labels[code]?.labelEn ?? code,
          labelNp: labels[code]?.labelNp ?? code,
        ),
    ],
    // The most recent visit's prescriptions are the best local answer: the
    // server tracks what is still in date, the device cannot.
    currentMedicines: latest?.prescriptions ?? const [],
    allergies: patient.allergies,
    lastVitals: _lastVitals(ordered),
    activePregnancy: pregnancy,
    lastVisitAt: latest?.visitAt,
    visitCount: ordered.length,
  );
}

/// The newest visit that actually recorded vitals — not simply the newest
/// visit, which may have been a paperwork-only encounter.
LastVitals? _lastVitals(List<Visit> ordered) {
  for (final visit in ordered) {
    final vitals = visit.vitals;
    if (vitals == null) continue;
    if (vitals.bpSys == null &&
        vitals.bpDia == null &&
        vitals.pulse == null &&
        vitals.tempC == null &&
        vitals.weightKg == null &&
        vitals.spo2 == null) {
      continue;
    }

    // A.2's summary block carries only these three plus the timestamp; the
    // rest of the vitals stay on the Visit itself.
    return LastVitals(
      bpSys: vitals.bpSys,
      bpDia: vitals.bpDia,
      weightKg: vitals.weightKg,
      at: visit.visitAt,
    );
  }
  return null;
}
