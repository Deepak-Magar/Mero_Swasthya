/// When each dose of a prescription is due (Tier 2, S22 prescriptions).
///
/// A pure function of the frequency code and a starting instant: no plugin, no
/// clock of its own, no notification ids. That matters because the times are
/// the part a pharmacist would argue about, and they should be arguable in a
/// test rather than by watching a phone for a week.
///
/// The hours come from the standard Nepali outpatient card: OD in the morning,
/// BD morning and evening, TDS with the three meals, QID every six hours, HS at
/// bedtime. SOS — "when needed" — deliberately produces nothing: reminding
/// somebody at a fixed hour to take a painkiller they may not need is how a
/// reminder becomes noise, and noise is how every reminder gets turned off.
library;

import '../models/enums.dart';
import '../models/models.dart';

/// The hour-of-day slots for each frequency.
const Map<PrescriptionFrequency, List<int>> doseHours = {
  PrescriptionFrequency.od: [8],
  PrescriptionFrequency.bd: [8, 20],
  PrescriptionFrequency.tds: [8, 14, 20],
  PrescriptionFrequency.qid: [6, 12, 18, 22],
  PrescriptionFrequency.hs: [21],
  PrescriptionFrequency.sos: [],
};

/// How many days ahead reminders are scheduled.
///
/// Seven, not the whole course: Android caps how many alarms one app may hold,
/// a course can run ninety days, and somebody who stops taking the medicine
/// should stop being reminded within the week rather than in three months.
const int reminderHorizonDays = 7;

/// One notification to schedule.
class ScheduledDose {
  const ScheduledDose({
    required this.prescriptionId,
    required this.at,
    required this.drugName,
    this.instructionsNp,
  });

  final String prescriptionId;
  final DateTime at;
  final String drugName;

  /// The Nepali instruction goes in the notification body, because it is what
  /// the person holding the phone actually reads — "खाना पछि" beats "take
  /// after food" in a house where the phone's language was set by a grandchild.
  final String? instructionsNp;

  @override
  String toString() => 'ScheduledDose($drugName at $at)';
}

/// Every dose time for [prescription] in the [days] after [from].
///
/// Times already past on the first day are skipped — scheduling 08:00 when it
/// is already noon fires immediately on some Android versions and never on
/// others, and neither is a reminder.
///
/// The schedule is also capped by `durationDays`: a three-day course must not
/// go on reminding somebody for a week.
List<DateTime> doseTimes(
  Prescription prescription, {
  required DateTime from,
  int days = reminderHorizonDays,
}) {
  final hours = doseHours[prescription.frequency] ?? const <int>[];
  if (hours.isEmpty) return const [];

  final horizon = prescription.durationDays > 0
      ? (prescription.durationDays < days ? prescription.durationDays : days)
      : days;

  final startOfDay = DateTime(from.year, from.month, from.day);
  final times = <DateTime>[];

  for (var day = 0; day < horizon; day++) {
    for (final hour in hours) {
      final at = startOfDay.add(Duration(days: day)).copyWith(hour: hour);
      if (at.isAfter(from)) times.add(at);
    }
  }

  times.sort();
  return times;
}

/// Everything to schedule for one visit's prescriptions.
///
/// Flattened and sorted so the caller can hand it straight to the plugin and
/// so a test can read the sequence in the order it will actually fire.
List<ScheduledDose> scheduleForPrescriptions(
  List<Prescription> prescriptions, {
  required DateTime from,
  int days = reminderHorizonDays,
}) {
  final doses = <ScheduledDose>[
    for (final prescription in prescriptions)
      for (final at in doseTimes(prescription, from: from, days: days))
        ScheduledDose(
          prescriptionId: prescription.id,
          at: at,
          drugName: prescription.drugName.isEmpty
              ? prescription.drugCode
              : prescription.drugName,
          instructionsNp: prescription.instructionsNp,
        ),
  ]..sort((a, b) => a.at.compareTo(b.at));

  return doses;
}

/// A stable notification id for a dose.
///
/// Derived from the prescription id and the instant rather than from a counter,
/// so scheduling the same course twice replaces the same alarms instead of
/// doubling them. Android ids are 32-bit signed, hence the mask.
int notificationIdFor(String prescriptionId, DateTime at) {
  final hash = Object.hash(prescriptionId, at.millisecondsSinceEpoch);
  return hash & 0x7FFFFFFF;
}
