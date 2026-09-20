import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/medicine_schedule.dart';

/// Tier 2 medicine reminders. The schedule is a pure function on purpose: the
/// hours are the part a pharmacist would argue about, and they should be
/// arguable here rather than by watching a phone for a week.
void main() {
  Prescription rx(
    PrescriptionFrequency frequency, {
    String id = 'rx1',
    String drugName = 'Metformin 500 mg',
    int durationDays = 30,
    String? instructionsNp = 'खाना पछि',
  }) {
    return Prescription(
      id: id,
      drugCode: 'METFORMIN_500',
      drugName: drugName,
      dose: '1 tab',
      frequency: frequency,
      durationDays: durationDays,
      instructionsNp: instructionsNp,
    );
  }

  // Before the first slot of the day, so a whole day's doses are ahead.
  final monday5am = DateTime(2026, 9, 21, 5);

  List<int> hoursOn(List<DateTime> times, DateTime day) => times
      .where((t) => t.day == day.day)
      .map((t) => t.hour)
      .toList(growable: false);

  group('the hours for each frequency', () {
    test('OD is 08:00', () {
      final times = doseTimes(rx(PrescriptionFrequency.od), from: monday5am);
      expect(hoursOn(times, monday5am), [8]);
    });

    test('BD is 08:00 and 20:00', () {
      final times = doseTimes(rx(PrescriptionFrequency.bd), from: monday5am);
      expect(hoursOn(times, monday5am), [8, 20]);
    });

    test('TDS is 08:00, 14:00 and 20:00', () {
      final times = doseTimes(rx(PrescriptionFrequency.tds), from: monday5am);
      expect(hoursOn(times, monday5am), [8, 14, 20]);
    });

    test('QID is 06:00, 12:00, 18:00 and 22:00', () {
      final times = doseTimes(rx(PrescriptionFrequency.qid), from: monday5am);
      expect(hoursOn(times, monday5am), [6, 12, 18, 22]);
    });

    test('HS is 21:00', () {
      final times = doseTimes(rx(PrescriptionFrequency.hs), from: monday5am);
      expect(hoursOn(times, monday5am), [21]);
    });

    test('SOS schedules nothing at all', () {
      // "When needed" has no hour. Reminding somebody at a fixed time to take a
      // painkiller they may not need is how every reminder gets turned off.
      expect(
        doseTimes(rx(PrescriptionFrequency.sos), from: monday5am),
        isEmpty,
      );
    });
  });

  group('the seven-day horizon', () {
    test('BD over a 30-day course gives 14 doses, not 60', () {
      final times = doseTimes(rx(PrescriptionFrequency.bd), from: monday5am);
      expect(times, hasLength(14));
      expect(times.first, DateTime(2026, 9, 21, 8));
      expect(times.last, DateTime(2026, 9, 27, 20));
    });

    test('a course shorter than a week stops when the course does', () {
      final times = doseTimes(
        rx(PrescriptionFrequency.tds, durationDays: 3),
        from: monday5am,
      );
      expect(times, hasLength(9));
      expect(times.last, DateTime(2026, 9, 23, 20));
    });

    test('a course with no stated duration still stops at seven days', () {
      final times = doseTimes(
        rx(PrescriptionFrequency.od, durationDays: 0),
        from: monday5am,
      );
      expect(times, hasLength(7));
    });

    test('the times come back in order', () {
      final times = doseTimes(rx(PrescriptionFrequency.qid), from: monday5am);
      for (var i = 1; i < times.length; i++) {
        expect(times[i].isAfter(times[i - 1]), isTrue);
      }
    });
  });

  group('slots that have already passed today', () {
    test('an afternoon start skips this morning and keeps this evening', () {
      // Scheduling 08:00 when it is already 15:00 fires immediately on some
      // Android versions and never on others; neither is a reminder.
      final times = doseTimes(
        rx(PrescriptionFrequency.bd),
        from: DateTime(2026, 9, 21, 15),
      );

      expect(hoursOn(times, monday5am), [20]);
      expect(times.first, DateTime(2026, 9, 21, 20));
      expect(times, hasLength(13));
    });

    test('a start after the last slot begins tomorrow', () {
      final times = doseTimes(
        rx(PrescriptionFrequency.od),
        from: DateTime(2026, 9, 21, 23),
      );

      expect(times.first, DateTime(2026, 9, 22, 8));
      expect(times, hasLength(6));
    });
  });

  group('a whole visit', () {
    test('merges every prescription into one list, in firing order', () {
      final doses = scheduleForPrescriptions(
        [
          rx(PrescriptionFrequency.hs, id: 'rx-hs', drugName: 'Amitriptyline'),
          rx(PrescriptionFrequency.od, id: 'rx-od', drugName: 'Amlodipine'),
        ],
        from: monday5am,
      );

      expect(doses, hasLength(14));
      expect(doses.first.drugName, 'Amlodipine');
      expect(doses.first.at, DateTime(2026, 9, 21, 8));
      expect(doses[1].drugName, 'Amitriptyline');
      expect(doses[1].at, DateTime(2026, 9, 21, 21));
    });

    test('carries the Nepali instruction, which is the notification body', () {
      final doses = scheduleForPrescriptions(
        [rx(PrescriptionFrequency.od)],
        from: monday5am,
      );

      expect(doses.first.instructionsNp, 'खाना पछि');
      expect(doses.first.drugName, 'Metformin 500 mg');
    });

    test('falls back to the drug code when there is no name', () {
      final doses = scheduleForPrescriptions(
        [rx(PrescriptionFrequency.od, drugName: '')],
        from: monday5am,
      );

      expect(doses.first.drugName, 'METFORMIN_500');
    });

    test('an all-SOS visit produces nothing', () {
      expect(
        scheduleForPrescriptions(
          [rx(PrescriptionFrequency.sos)],
          from: monday5am,
        ),
        isEmpty,
      );
    });
  });

  group('notification ids', () {
    test('are stable, so re-scheduling replaces rather than doubles', () {
      final at = DateTime(2026, 9, 21, 8);
      expect(notificationIdFor('rx1', at), notificationIdFor('rx1', at));
    });

    test('differ per prescription and per time', () {
      final at = DateTime(2026, 9, 21, 8);
      expect(
        notificationIdFor('rx1', at),
        isNot(notificationIdFor('rx2', at)),
      );
      expect(
        notificationIdFor('rx1', at),
        isNot(notificationIdFor('rx1', at.add(const Duration(hours: 12)))),
      );
    });

    test('fit in a 32-bit signed int, which is all Android accepts', () {
      for (final dose in scheduleForPrescriptions(
        [rx(PrescriptionFrequency.qid)],
        from: monday5am,
      )) {
        final id = notificationIdFor(dose.prescriptionId, dose.at);
        expect(id, greaterThanOrEqualTo(0));
        expect(id, lessThanOrEqualTo(0x7FFFFFFF));
      }
    });
  });
}
