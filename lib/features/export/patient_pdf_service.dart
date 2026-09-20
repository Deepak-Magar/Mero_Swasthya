import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates/bs_date.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/child_health_repo.dart';
import '../../data/repositories/patient_repo.dart';
import '../../data/repositories/pregnancy_repo.dart';
import '../../data/repositories/visit_repo.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/epi_schedule.dart';
import '../timeline/local_timeline.dart';
import 'patient_pdf.dart';

/// Gathers everything the PDF needs from the local database and builds it.
///
/// Local only, and deliberately: a record the patient can print has to be
/// printable in a room with no signal. Nothing here calls the network.
class PatientPdfService {
  const PatientPdfService({
    required this.db,
    required this.patients,
    required this.visits,
    required this.pregnancies,
    required this.childHealth,
  });

  final AppDatabase db;
  final PatientRepo patients;
  final VisitRepo visits;
  final PregnancyRepo pregnancies;
  final ChildHealthRepo childHealth;

  /// Cached: parsing a 240 kB font on every export would be a visible pause,
  /// and the bytes never change.
  static PdfFonts? _fonts;

  /// Load the embedded Devanagari faces.
  ///
  /// The `pdf` package ships Helvetica and nothing else, so without these every
  /// Nepali string in the document renders as empty boxes.
  static Future<PdfFonts> loadFonts() async {
    final cached = _fonts;
    if (cached != null) return cached;

    final regular = await rootBundle
        .load('assets/fonts/NotoSansDevanagari-Regular.ttf');
    final bold =
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf');
    final logo = await rootBundle.load('assets/brand/logo_full.png');

    return _fonts = PdfFonts(
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      logo: logo.buffer.asUint8List(),
    );
  }

  /// Everything about [patientId] that belongs on a printed sheet.
  Future<PatientPdfData> gather(String patientId, {DateTime? generatedAt}) async {
    final patient = await db.patientsDao.findById(patientId);
    if (patient == null) {
      throw StateError('No patient $patientId to export');
    }

    final visitRows = await visits.watchByPatient(patientId).first;
    final documentRows = await db.documentsDao.watchByPatient(patientId).first;
    final pregnancy = await pregnancies.watchLatestForPatient(patientId).first;

    final contacts = pregnancy == null
        ? const <AncContact>[]
        : await pregnancies.watchContacts(pregnancy.id).first;

    // Only for children: an adult with no schedule simply has no such section.
    final dob = BsDate.parseAd(patient.dob);
    final doses = dob != null && isUnderFive(dob)
        ? await childHealth.schedule(patientId)
        : const <Immunisation>[];

    final growth = await childHealth.watchGrowth(patientId).first;

    return PatientPdfData(
      patient: patient,
      // Built locally rather than fetched: the whole point is that this works
      // with the radio off, and S08 already falls back this way.
      summary: null,
      visits: visitRows,
      timeline: buildTimeline(
        visitRows,
        documentRows,
        pregnancy,
        contacts,
        immunisations: doses,
        growth: growth,
      ),
      pregnancy: pregnancy,
      ancContacts: contacts,
      immunisations: doses,
      generatedAt: generatedAt,
    );
  }

  Future<Uint8List> build(String patientId, {DateTime? generatedAt}) async {
    final data = await gather(patientId, generatedAt: generatedAt);
    return buildPatientPdf(data: data, fonts: await loadFonts());
  }

  /// A filename somebody will recognise in a downloads folder six months later.
  static String fileNameFor(Patient patient, {DateTime? at}) {
    final when = at ?? DateTime.now();
    final safe = patient.name
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final stamp = when.toIso8601String().substring(0, 10);
    return '${safe.isEmpty ? 'record' : safe}-$stamp.pdf';
  }
}
