/// Tier 3 — Nepal's national immunisation (EPI) schedule.
///
/// The table lives in `assets/epi_schedule.json` so it can be corrected without
/// a code change, in the same spirit as `assets/rules.json`. **It has not been
/// verified against a current Ministry publication** — the asset says so at the
/// top and so does the screen.
///
/// Generating the schedule is a pure function of the child's date of birth, and
/// deliberately so: both this app and the backend must produce the same rows,
/// with the same deterministic ids, or a child registered offline ends up with
/// two of every vaccine.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/ids/ids.dart';
import '../models/models.dart';

/// Where a dose stands today.
enum DoseStatus {
  /// Administered — `givenAt` is set.
  given,

  /// Due now or in the past few days, not yet given.
  due,

  /// Past due with nothing recorded. This is the one a health worker is
  /// looking for.
  overdue,

  /// Due in the future.
  upcoming,
}

/// How long after its due date a dose is still merely "due" rather than
/// "overdue".
///
/// Two weeks, because a village clinic runs on a monthly immunisation day and
/// calling a child overdue the morning after their due date would turn the
/// whole list red for no useful reason.
const Duration overdueGrace = Duration(days: 14);

/// One vaccine and its doses, as read from the asset.
class Vaccine {
  const Vaccine({
    required this.code,
    required this.labelEn,
    required this.labelNp,
    required this.protectsEn,
    required this.protectsNp,
    required this.doses,
  });

  final String code;
  final String labelEn;
  final String labelNp;
  final String protectsEn;
  final String protectsNp;
  final List<VaccineDose> doses;

  factory Vaccine.fromJson(Map<String, dynamic> json) => Vaccine(
        code: '${json['code']}',
        labelEn: '${json['labelEn']}',
        labelNp: '${json['labelNp']}',
        protectsEn: '${json['protectsEn'] ?? ''}',
        protectsNp: '${json['protectsNp'] ?? ''}',
        doses: [
          for (final d in (json['doses'] as List? ?? const []))
            VaccineDose.fromJson((d as Map).cast<String, dynamic>()),
        ],
      );
}

/// One dose of one vaccine, expressed as an age.
class VaccineDose {
  const VaccineDose({
    required this.doseNo,
    this.ageWeeks,
    this.ageMonths,
  });

  final int doseNo;
  final int? ageWeeks;
  final int? ageMonths;

  factory VaccineDose.fromJson(Map<String, dynamic> json) => VaccineDose(
        doseNo: json['doseNo'] as int,
        ageWeeks: json['ageWeeks'] as int?,
        ageMonths: json['ageMonths'] as int?,
      );

  /// The date this dose falls due for a child born on [dob].
  ///
  /// Weeks are exact; months are calendar months, because "nine months" on an
  /// immunisation card means the same day of the month, not 270 days.
  DateTime dueFor(DateTime dob) {
    final birth = DateTime.utc(dob.year, dob.month, dob.day);
    final weeks = ageWeeks;
    if (weeks != null) return birth.add(Duration(days: weeks * 7));

    final months = ageMonths ?? 0;
    final year = birth.year + (birth.month - 1 + months) ~/ 12;
    final month = (birth.month - 1 + months) % 12 + 1;
    // Clamp the day so "born on the 31st, due in a 30-day month" lands on the
    // 30th rather than rolling into the next month.
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, birth.day > lastDay ? lastDay : birth.day);
  }
}

/// The whole table.
class EpiSchedule {
  const EpiSchedule({required this.version, required this.vaccines});

  final String version;
  final List<Vaccine> vaccines;

  /// Only ever read from the asset; there is no network copy yet.
  static Future<EpiSchedule> loadFromAsset() async {
    final raw = await rootBundle.loadString('assets/epi_schedule.json');
    return EpiSchedule.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  }

  factory EpiSchedule.fromJson(Map<String, dynamic> json) => EpiSchedule(
        version: '${json['version'] ?? ''}',
        vaccines: [
          for (final v in (json['vaccines'] as List? ?? const []))
            Vaccine.fromJson((v as Map).cast<String, dynamic>()),
        ],
      );

  Vaccine? vaccine(String code) {
    for (final v in vaccines) {
      if (v.code == code) return v;
    }
    return null;
  }

  /// Every dose a child born on [dob] should receive, as unsaved rows with
  /// deterministic ids and `version: 0`.
  ///
  /// Ordered by due date, then vaccine code, then dose — the same order the DAO
  /// reads them back in, so the list does not reshuffle once it is saved.
  List<Immunisation> generateFor({
    required String patientId,
    required DateTime dob,
  }) {
    final rows = <Immunisation>[
      for (final vaccine in vaccines)
        for (final dose in vaccine.doses)
          Immunisation(
            id: immunisationId(patientId, vaccine.code, dose.doseNo),
            patientId: patientId,
            vaccineCode: vaccine.code,
            doseNo: dose.doseNo,
            dueAt: _isoDate(dose.dueFor(dob)),
          ),
    ]..sort((a, b) {
        final byDate = a.dueAt.compareTo(b.dueAt);
        if (byDate != 0) return byDate;
        final byCode = a.vaccineCode.compareTo(b.vaccineCode);
        return byCode != 0 ? byCode : a.doseNo.compareTo(b.doseNo);
      });

    return rows;
  }
}

/// Where [dose] stands as of [asOf].
DoseStatus statusOf(Immunisation dose, {DateTime? asOf}) {
  if (dose.givenAt != null && dose.givenAt!.isNotEmpty) return DoseStatus.given;

  final today = _dateOnly(asOf ?? DateTime.now());
  final due = DateTime.tryParse(dose.dueAt);
  if (due == null) return DoseStatus.upcoming;

  final dueDay = _dateOnly(due);
  if (dueDay.isAfter(today)) return DoseStatus.upcoming;
  return today.isAfter(dueDay.add(overdueGrace))
      ? DoseStatus.overdue
      : DoseStatus.due;
}

/// The doses somebody needs to chase, oldest first.
List<Immunisation> overdueDoses(
  List<Immunisation> schedule, {
  DateTime? asOf,
}) {
  return schedule
      .where((d) => statusOf(d, asOf: asOf) == DoseStatus.overdue)
      .toList(growable: false);
}

/// `(given, total)` for the progress line.
///
/// Named for immunisations rather than "schedule" because `anc_schedule.dart`
/// already owns that word, and a screen that imports both should not have to
/// guess which one it got.
({int given, int total}) immunisationProgress(List<Immunisation> schedule) {
  final live = schedule.where((d) => !d.deleted);
  return (
    given: live.where((d) => d.givenAt != null).length,
    total: live.length,
  );
}

/// The child's age in whole months at [asOf] — the x axis of the growth chart.
int ageInMonths(DateTime dob, DateTime asOf) {
  var months = (asOf.year - dob.year) * 12 + (asOf.month - dob.month);
  if (asOf.day < dob.day) months -= 1;
  return months < 0 ? 0 : months;
}

/// Spec-wide definition of "a child" for the purposes of this module.
///
/// Five years, because that is where the EPI schedule and under-five growth
/// monitoring both stop.
bool isUnderFive(DateTime dob, {DateTime? asOf}) =>
    ageInMonths(dob, asOf ?? DateTime.now()) < 60;

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

String _isoDate(DateTime d) => _dateOnly(d).toIso8601String().substring(0, 10);
