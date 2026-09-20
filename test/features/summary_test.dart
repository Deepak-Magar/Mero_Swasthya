import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/summary.dart';

/// Spec §9 `patientSummaryProvider`: "GET /patients/:id, fallback: computed
/// locally from visits". This is the fallback — S08 and S21 must still show
/// allergies and problems with no signal.
void main() {
  const patient = Patient(
    id: 'p1',
    ownerUserId: 'u1',
    name: 'Ram Bahadur',
    sex: Sex.male,
    dob: '1968-01-15',
    allergies: ['penicillin'],
    chronicConditions: ['E11'],
  );

  Visit visit({
    String id = 'v1',
    String at = '2026-09-18T04:05:00.000Z',
    Vitals? vitals,
    List<Prescription> prescriptions = const [],
    bool deleted = false,
  }) =>
      Visit(
        id: id,
        patientId: 'p1',
        visitAt: at,
        chiefComplaintCode: 'FEVER',
        vitals: vitals,
        prescriptions: prescriptions,
        deleted: deleted,
      );

  test('an empty record yields an empty summary, not a crash', () {
    expect(summaryFromLocal(patient: null, visits: const []),
        const PatientSummary());
  });

  test('allergies and chronic conditions come straight off the patient', () {
    final summary = summaryFromLocal(patient: patient, visits: const []);

    expect(summary.allergies, ['penicillin']);
    expect(summary.activeProblems.single.code, 'E11');
  });

  test('a problem gets its label from the codelist when one is cached', () {
    final summary = summaryFromLocal(
      patient: patient,
      visits: const [],
      codes: const [
        CodeListItem(
          kind: CodeListKind.diagnosis,
          code: 'E11',
          labelEn: 'Type 2 diabetes',
          labelNp: 'मधुमेह',
        ),
      ],
    );

    expect(summary.activeProblems.single.labelEn, 'Type 2 diabetes');
    expect(summary.activeProblems.single.labelNp, 'मधुमेह');
  });

  test('an uncached code falls back to the code itself', () {
    // Better a bare "E11" than a blank row.
    final summary = summaryFromLocal(patient: patient, visits: const []);
    expect(summary.activeProblems.single.labelEn, 'E11');
  });

  test('current medicines come from the most recent visit', () {
    const rx = Prescription(
      id: 'rx1',
      drugCode: 'METFORMIN_500',
      dose: '1 tab',
      frequency: PrescriptionFrequency.bd,
      durationDays: 30,
    );

    final summary = summaryFromLocal(
      patient: patient,
      visits: [
        visit(id: 'old', at: '2026-01-01T00:00:00.000Z'),
        visit(id: 'new', at: '2026-09-18T04:05:00.000Z', prescriptions: [rx]),
      ],
    );

    expect(summary.currentMedicines.single.drugCode, 'METFORMIN_500');
    expect(summary.lastVisitAt, '2026-09-18T04:05:00.000Z');
    expect(summary.visitCount, 2);
  });

  test('last vitals skip a visit that recorded none', () {
    // A paperwork-only encounter must not blank out the last real reading.
    final summary = summaryFromLocal(
      patient: patient,
      visits: [
        visit(id: 'newest', at: '2026-09-18T06:00:00.000Z'),
        visit(
          id: 'withVitals',
          at: '2026-09-17T04:05:00.000Z',
          vitals: const Vitals(bpSys: 138, bpDia: 88, weightKg: 71.5),
        ),
      ],
    );

    expect(summary.lastVitals!.bpSys, 138);
    expect(summary.lastVitals!.weightKg, 71.5);
    expect(summary.lastVitals!.at, '2026-09-17T04:05:00.000Z');
  });

  test('an all-null vitals object counts as no vitals', () {
    final summary = summaryFromLocal(
      patient: patient,
      visits: [visit(vitals: const Vitals())],
    );

    expect(summary.lastVitals, isNull);
  });

  test('deleted visits are ignored everywhere', () {
    final summary = summaryFromLocal(
      patient: patient,
      visits: [
        visit(id: 'gone', deleted: true, vitals: const Vitals(bpSys: 200)),
      ],
    );

    expect(summary.visitCount, 0);
    expect(summary.lastVitals, isNull);
    expect(summary.lastVisitAt, isNull);
  });

  test('visits in any order still give the newest first', () {
    final summary = summaryFromLocal(
      patient: patient,
      visits: [
        visit(id: 'a', at: '2026-01-01T00:00:00.000Z'),
        visit(id: 'c', at: '2026-12-01T00:00:00.000Z'),
        visit(id: 'b', at: '2026-06-01T00:00:00.000Z'),
      ],
    );

    expect(summary.lastVisitAt, '2026-12-01T00:00:00.000Z');
  });

  test('an active pregnancy is carried through', () {
    const pregnancy = Pregnancy(id: 'pg1', patientId: 'p1', edd: '2026-11-27');

    final summary = summaryFromLocal(
      patient: patient,
      visits: const [],
      pregnancy: pregnancy,
    );

    expect(summary.activePregnancy?.id, 'pg1');
  });
}
