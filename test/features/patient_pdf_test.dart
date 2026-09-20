import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/features/export/patient_pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Tier 3 — the printable record.
///
/// The builder is a pure function of data already on the device, so it is
/// tested with the real embedded fonts and no screen, printer or phone. What
/// matters is that it produces a document for every shape of patient the demo
/// has — including the awkward ones — rather than throwing halfway through.
void main() {
  late PdfFonts fonts;

  setUpAll(() {
    // The real faces, not a stand-in: a font that fails to parse is exactly the
    // failure this test exists to catch.
    fonts = PdfFonts(
      regular: pw.Font.ttf(
        File('assets/fonts/NotoSansDevanagari-Regular.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
      bold: pw.Font.ttf(
        File('assets/fonts/NotoSansDevanagari-Bold.ttf')
            .readAsBytesSync()
            .buffer
            .asByteData(),
      ),
    );
  });

  final generatedAt = DateTime.utc(2026, 9, 19, 12);

  const sita = Patient(
    id: 'p_sita',
    ownerUserId: 'u1',
    name: 'Sita Chaudhary',
    sex: Sex.female,
    dob: '2002-04-11',
    bloodGroup: 'B+',
    ward: 5,
    municipality: 'Ghorahi',
    allergies: ['sulpha'],
  );

  const ram = Patient(
    id: 'p_ram',
    ownerUserId: 'u1',
    name: 'Ram Bahadur Chaudhary',
    sex: Sex.male,
    dob: '1968-01-15',
    bloodGroup: 'O+',
    allergies: ['penicillin'],
    chronicConditions: ['E11'],
  );

  const aarav = Patient(
    id: 'p_aarav',
    ownerUserId: 'u1',
    name: 'Aarav Chaudhary',
    sex: Sex.male,
    dob: '2023-07-14',
    bloodGroup: 'B+',
  );

  final ramVisit = Visit(
    id: 'v1',
    patientId: ram.id,
    visitAt: '2026-08-25T10:00:00.000Z',
    chiefComplaintCode: 'FOLLOW_UP',
    vitals: const Vitals(bpSys: 138, bpDia: 86, weightKg: 71.5),
    diagnosisCodes: const ['E11'],
    notes: 'Fasting sugar 168 mg/dl',
    advice: 'Diet, walk 30 min daily',
    prescriptions: const [
      Prescription(
        id: 'rx1',
        drugCode: 'METFORMIN_500',
        drugName: 'Metformin 500 mg',
        dose: '1 tab',
        frequency: PrescriptionFrequency.bd,
        durationDays: 30,
        // The whole reason the font is embedded.
        instructionsNp: 'खाना पछि',
      ),
    ],
  );

  final pregnancy = Pregnancy(
    id: 'pg1',
    patientId: sita.id,
    edd: '2026-11-25',
    status: PregnancyStatus.active,
  );

  final contacts = [
    for (var i = 1; i <= 8; i++)
      AncContact(
        id: ancContactId('pg1', i),
        pregnancyId: 'pg1',
        contactNo: i,
        weekTarget: [12, 20, 26, 30, 34, 36, 38, 40][i - 1],
        dueAt: '2026-0${i < 9 ? i : 9}-01',
        doneAt: i <= 3 ? '2026-0$i-02T10:00:00.000Z' : null,
        triageLevel: i <= 3 ? TriageLevel.green : null,
      ),
  ];

  final doses = [
    Immunisation(
      id: immunisationId(aarav.id, 'BCG', 1),
      patientId: aarav.id,
      vaccineCode: 'BCG',
      doseNo: 1,
      dueAt: '2023-07-14',
      givenAt: '2023-07-16T10:00:00.000Z',
      batchNo: 'B2023-1',
    ),
    const Immunisation(
      id: 'i-mr2',
      patientId: 'p_aarav',
      vaccineCode: 'MR',
      doseNo: 2,
      dueAt: '2024-10-14',
    ),
  ];

  Future<int> sizeOf(PatientPdfData data) async {
    final bytes = await buildPatientPdf(data: data, fonts: fonts);
    // A PDF always starts with %PDF; anything else means the package handed
    // back something that is not a document.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    return bytes.length;
  }

  group('it builds a document for every seeded patient', () {
    test('Sita — a pregnancy with eight contacts', () async {
      final size = await sizeOf(
        PatientPdfData(
          patient: sita,
          pregnancy: pregnancy,
          ancContacts: contacts,
          generatedAt: generatedAt,
        ),
      );
      expect(size, greaterThan(1000));
    });

    test('Ram — medicines with a Nepali instruction', () async {
      final size = await sizeOf(
        PatientPdfData(
          patient: ram,
          summary: PatientSummary(
            activeProblems: const [
              ActiveProblem(code: 'E11', labelEn: 'Type 2 diabetes'),
            ],
            currentMedicines: ramVisit.prescriptions,
            allergies: ram.allergies,
            visitCount: 1,
          ),
          visits: [ramVisit],
          generatedAt: generatedAt,
        ),
      );
      expect(size, greaterThan(1000));
    });

    test('Aarav — an immunisation schedule', () async {
      final size = await sizeOf(
        PatientPdfData(
          patient: aarav,
          immunisations: doses,
          generatedAt: generatedAt,
        ),
      );
      expect(size, greaterThan(1000));
    });
  });

  group('the awkward shapes', () {
    test('a patient with nothing at all still produces a sheet', () async {
      // A record created two minutes ago is still a record, and an export that
      // threw on it would be an export nobody could rely on.
      const bare = Patient(
        id: 'p_bare',
        ownerUserId: 'u1',
        name: 'New Patient',
        sex: Sex.other,
        dob: '1990-01-01',
      );

      expect(
        await sizeOf(PatientPdfData(patient: bare, generatedAt: generatedAt)),
        greaterThan(500),
      );
    });

    test('an unparseable date of birth does not throw', () async {
      const odd = Patient(
        id: 'p_odd',
        ownerUserId: 'u1',
        name: 'Odd Date',
        sex: Sex.female,
        dob: 'not-a-date',
      );

      expect(
        await sizeOf(PatientPdfData(patient: odd, generatedAt: generatedAt)),
        greaterThan(500),
      );
    });

    test('a long timeline is capped rather than running to twenty pages',
        () async {
      final long = [
        for (var i = 0; i < 60; i++)
          TimelineItem(
            kind: TimelineKind.visit,
            at: '2026-0${(i % 9) + 1}-0${(i % 9) + 1}T10:00:00.000Z',
            title: 'Visit $i',
            refId: 'v$i',
          ),
      ];

      final capped = await buildPatientPdf(
        data: PatientPdfData(
          patient: ram,
          timeline: long,
          generatedAt: generatedAt,
        ),
        fonts: fonts,
      );
      final short = await buildPatientPdf(
        data: PatientPdfData(
          patient: ram,
          timeline: long.take(pdfTimelineLimit).toList(),
          generatedAt: generatedAt,
        ),
        fonts: fonts,
      );

      // Both carry twenty rows; the capped one adds one line saying so, so it
      // is a little larger but nowhere near three times the size.
      expect(capped.length, lessThan(short.length * 2));
      expect(pdfTimelineLimit, 20);
    });

    test('a patient with everything at once builds one document', () async {
      final size = await sizeOf(
        PatientPdfData(
          patient: sita,
          summary: PatientSummary(
            activeProblems: const [
              ActiveProblem(code: 'E11', labelEn: 'Type 2 diabetes'),
            ],
            currentMedicines: ramVisit.prescriptions,
            allergies: sita.allergies,
            visitCount: 3,
          ),
          visits: [ramVisit],
          timeline: [
            TimelineItem(
              kind: TimelineKind.immunisation,
              at: '2026-09-01T10:00:00.000Z',
              title: 'BCG dose 1',
              refId: 'i1',
            ),
            const TimelineItem(
              kind: TimelineKind.growth,
              at: '2026-09-02T10:00:00.000Z',
              title: 'Weight 13.1 kg',
              refId: 'g1',
            ),
          ],
          pregnancy: pregnancy,
          ancContacts: contacts,
          immunisations: doses,
          generatedAt: generatedAt,
        ),
      );
      expect(size, greaterThan(2000));
    });
  });

  group('fonts', () {
    test('Latin comes from Helvetica and Devanagari from the embedded face',
        () async {
      // Found on the phone, in the print preview: the shipped Noto Sans
      // Devanagari is the script-only build with no Latin alphabet, so using
      // it as the base font drew every English word as a solid black box.
      // Helvetica is the base and Noto is the fallback; both must be present.
      final bytes = await buildPatientPdf(
        data: PatientPdfData(
          patient: ram,
          visits: [ramVisit],
          summary: PatientSummary(
            currentMedicines: ramVisit.prescriptions,
            allergies: ram.allergies,
          ),
          generatedAt: generatedAt,
        ),
        fonts: fonts,
      );

      final raw = String.fromCharCodes(bytes.where((b) => b < 128));
      expect(
        raw,
        contains('Helvetica'),
        reason: 'the Latin base font has to be referenced',
      );
      expect(
        raw.contains('NotoSansDevanagari') || raw.contains('FontFile2'),
        isTrue,
        reason: 'the Devanagari fallback has to be embedded',
      );
    });
  });

  group('determinism', () {
    test('the same data twice produces the same length', () async {
      // Not byte equality — the package stamps an id — but a stable size means
      // nothing random leaked into the layout.
      final data = PatientPdfData(
        patient: sita,
        pregnancy: pregnancy,
        ancContacts: contacts,
        generatedAt: generatedAt,
      );

      final a = await buildPatientPdf(data: data, fonts: fonts);
      final b = await buildPatientPdf(data: data, fonts: fonts);
      expect(a.length, b.length);
    });
  });
}
