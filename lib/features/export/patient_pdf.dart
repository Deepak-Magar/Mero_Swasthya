import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates/bs_date.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/edd.dart';
import '../../domain/rules/epi_schedule.dart';

/// Tier 3 — the patient's record as a PDF they can keep, print or hand over.
///
/// This is the offline-first premise taken to its conclusion: a record that
/// belongs to the patient should be able to leave the app entirely. A printed
/// sheet works in a referral hospital with no network, no account and no
/// version of this software.
///
/// Everything here is a pure function of data already on the device, so the
/// builder can be tested without a screen, a printer or a phone.
class PatientPdfData {
  const PatientPdfData({
    required this.patient,
    this.summary,
    this.visits = const [],
    this.timeline = const [],
    this.pregnancy,
    this.ancContacts = const [],
    this.immunisations = const [],
    this.generatedAt,
  });

  final Patient patient;
  final PatientSummary? summary;
  final List<Visit> visits;
  final List<TimelineItem> timeline;
  final Pregnancy? pregnancy;
  final List<AncContact> ancContacts;
  final List<Immunisation> immunisations;

  /// Injectable so a test produces a byte-identical document twice.
  final DateTime? generatedAt;
}

/// The Devanagari faces the document falls back to.
///
/// They are a **fallback**, not the base, and that is not an accident. The
/// shipped Noto Sans Devanagari is the script-only build: it covers Devanagari
/// and digits but has no Latin alphabet at all. Used as the base font it
/// rendered every English word in the document as a solid black box — found on
/// the phone, in the print preview, which is the only place it is visible.
///
/// So the base is the `pdf` package's built-in Helvetica, which costs no bytes
/// and has proper Latin regular and bold, and anything Helvetica cannot draw —
/// every Nepali string — falls through to these.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold, this.logo});

  final pw.Font regular;
  final pw.Font bold;

  /// The brand lock-up, as PNG bytes.
  ///
  /// Passed in for the same reason the fonts are: `rootBundle` is not reachable
  /// from the pure-Dart tests that build a document, so the asset is loaded by
  /// the caller and the builder only draws it. Null simply falls back to the
  /// typeset name.
  final Uint8List? logo;
}

/// How many timeline rows the sheet carries.
const int pdfTimelineLimit = 20;

/// Build the document.
///
/// Returns the PDF bytes. Throws nothing the caller has to catch beyond what
/// the `pdf` package itself raises; missing sections are simply absent.
Future<Uint8List> buildPatientPdf({
  required PatientPdfData data,
  required PdfFonts fonts,
}) async {
  final doc = pw.Document(
    title: 'Mero Swasthya — ${data.patient.name}',
    author: 'Mero Swasthya',
  );

  final theme = pw.ThemeData.withFont(
    base: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    // Bold first: a bold Devanagari heading should reach the bold face before
    // the regular one.
    fontFallback: [fonts.bold, fonts.regular],
  );

  final at = data.generatedAt ?? DateTime.now();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      footer: (context) => _footer(context, at),
      build: (context) => [
        _header(data.patient, fonts.logo),
        pw.SizedBox(height: 12),
        _identity(data.patient),
        pw.SizedBox(height: 10),
        // Allergies first and boxed, for the same reason S08 and S21 put them
        // first: on paper nobody scrolls, but they do skim.
        _allergies(data.patient),
        if (data.summary != null) ...[
          ..._activeProblems(data.summary!),
          ..._medicines(data.summary!, data.visits),
        ],
        ..._pregnancySection(data.pregnancy, data.ancContacts),
        ..._immunisationSection(data.immunisations),
        ..._timelineSection(data.timeline),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _header(Patient patient, Uint8List? logo) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null)
            pw.Image(pw.MemoryImage(logo), height: 56)
          else
            pw.Text(
              'Mero Swasthya',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 2),
          pw.Text(
            'मेरो स्वास्थ्य — स्वास्थ्य कार्ड',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ],
      ),
      pw.Text(
        patient.name,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

pw.Widget _identity(Patient patient) {
  final dob = BsDate.parseAd(patient.dob);

  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Wrap(
      spacing: 24,
      runSpacing: 4,
      children: [
        if (dob != null)
          _field('Date of birth / जन्म मिति', BsDate.formatBoth(dob)),
        if (dob != null) _field('Age', '${BsDate.ageInYears(dob)}'),
        _field('Sex', patient.sex.wire),
        if (patient.bloodGroup != null)
          _field('Blood group / रक्त समूह', patient.bloodGroup!),
        if (patient.municipality != null)
          _field('Municipality', patient.municipality!),
        if (patient.ward != null) _field('Ward', '${patient.ward}'),
      ],
    ),
  );
}

pw.Widget _allergies(Patient patient) {
  final none = patient.allergies.isEmpty;

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: none ? PdfColors.green50 : PdfColors.red50,
      border: pw.Border.all(
        color: none ? PdfColors.green700 : PdfColors.red700,
        width: 1.5,
      ),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ALLERGIES / एलर्जी',
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: none ? PdfColors.green700 : PdfColors.red700,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          none ? 'No known allergies' : patient.allergies.join(', '),
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: none ? PdfColors.green900 : PdfColors.red900,
          ),
        ),
      ],
    ),
  );
}

List<pw.Widget> _activeProblems(PatientSummary summary) {
  if (summary.activeProblems.isEmpty) return const [];

  return [
    _sectionTitle('Active problems / मुख्य समस्या'),
    pw.Bullet(
      text: summary.activeProblems
          .map((p) => p.labelEn.isEmpty ? p.code : p.labelEn)
          .join(', '),
      style: const pw.TextStyle(fontSize: 11),
    ),
  ];
}

List<pw.Widget> _medicines(PatientSummary summary, List<Visit> visits) {
  // Prefer the summary; fall back to the latest visit's prescriptions, which is
  // what S21 does when the server is unreachable.
  var medicines = summary.currentMedicines;
  if (medicines.isEmpty && visits.isNotEmpty) {
    medicines = visits.first.prescriptions;
  }
  if (medicines.isEmpty) return const [];

  return [
    _sectionTitle('Current medicines / चलिरहेका औषधि'),
    pw.TableHelper.fromTextArray(
      cellStyle: const pw.TextStyle(fontSize: 10),
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignment: pw.Alignment.centerLeft,
      headers: const ['Medicine', 'Dose', 'Frequency', 'Days', 'निर्देशन'],
      data: [
        for (final rx in medicines)
          [
            rx.drugName.isEmpty ? rx.drugCode : rx.drugName,
            rx.dose,
            rx.frequency.wire,
            '${rx.durationDays}',
            rx.instructionsNp ?? '',
          ],
      ],
    ),
  ];
}

List<pw.Widget> _pregnancySection(
  Pregnancy? pregnancy,
  List<AncContact> contacts,
) {
  if (pregnancy == null) return const [];

  final edd = parseIsoDate(pregnancy.edd);
  final week = edd == null
      ? null
      : gestationalAgeWeeks(edd, DateTime.now().toUtc());

  return [
    _sectionTitle('Pregnancy / गर्भावस्था'),
    pw.Text(
      [
        if (week != null) 'Week $week of 40',
        if (edd != null) 'EDD ${BsDate.formatBoth(edd)}',
        'Status: ${pregnancy.status.wire}',
      ].join('   ·   '),
      style: const pw.TextStyle(fontSize: 11),
    ),
    pw.SizedBox(height: 6),
    if (contacts.isNotEmpty)
      pw.TableHelper.fromTextArray(
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellAlignment: pw.Alignment.centerLeft,
        headers: const ['Contact', 'Week', 'Due', 'Done', 'Triage'],
        data: [
          for (final c in (contacts.toList()
            ..sort((a, b) => a.contactNo.compareTo(b.contactNo))))
            [
              '${c.contactNo}',
              '${c.weekTarget}',
              _bs(c.dueAt),
              c.doneAt == null ? '—' : _bs(c.doneAt!),
              c.triageLevel?.wire ?? '—',
            ],
        ],
      ),
  ];
}

List<pw.Widget> _immunisationSection(List<Immunisation> doses) {
  if (doses.isEmpty) return const [];

  final progress = immunisationProgress(doses);
  final overdue = overdueDoses(doses);

  return [
    _sectionTitle('Immunisation / खोप'),
    pw.Text(
      '${progress.given} of ${progress.total} doses given'
      '${overdue.isEmpty ? '' : '   ·   ${overdue.length} overdue'}',
      style: pw.TextStyle(
        fontSize: 11,
        fontWeight: overdue.isEmpty ? pw.FontWeight.normal : pw.FontWeight.bold,
        color: overdue.isEmpty ? PdfColors.black : PdfColors.red900,
      ),
    ),
    pw.SizedBox(height: 6),
    pw.TableHelper.fromTextArray(
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignment: pw.Alignment.centerLeft,
      headers: const ['Vaccine', 'Dose', 'Due', 'Given', 'Batch'],
      data: [
        for (final d in doses)
          [
            d.vaccineCode,
            '${d.doseNo}',
            _bs(d.dueAt),
            d.givenAt == null ? '—' : _bs(d.givenAt!),
            d.batchNo ?? '',
          ],
      ],
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      'Schedule cross-checked against published sources on 19 Sep 2026. '
      'Not confirmed against the official Ministry schedule.',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    ),
  ];
}

List<pw.Widget> _timelineSection(List<TimelineItem> timeline) {
  if (timeline.isEmpty) return const [];

  final rows = timeline.take(pdfTimelineLimit).toList();

  return [
    _sectionTitle('Recent history / पछिल्लो विवरण'),
    pw.TableHelper.fromTextArray(
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(5),
      },
      headers: const ['Date', 'Type', 'Detail'],
      data: [
        for (final item in rows)
          [
            _bs(item.at),
            item.kind.wire,
            [item.title, if (item.subtitle != null) item.subtitle!].join(' — '),
          ],
      ],
    ),
    if (timeline.length > pdfTimelineLimit) ...[
      pw.SizedBox(height: 4),
      pw.Text(
        'Showing the most recent $pdfTimelineLimit of ${timeline.length} '
        'entries. The full record is in the app.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
    ],
  ];
}

pw.Widget _footer(pw.Context context, DateTime at) {
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Generated by Mero Swasthya on ${BsDate.formatBoth(at)}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

pw.Widget _sectionTitle(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _field(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
        ),
        pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
      ],
    );

/// A wire date as "2083 Ashoj 3 (2026-09-19)", or the raw string if it will not
/// parse — a date nobody can read beats a date nobody can see.
String _bs(String iso) {
  final parsed = BsDate.parseAd(iso.length > 10 ? iso.substring(0, 10) : iso);
  return parsed == null ? iso : BsDate.formatBs(parsed, nepaliDigits: false);
}
