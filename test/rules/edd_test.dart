import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/rules/edd.dart';

/// Spec A.6 cases 1 and 2. The backend computes the same numbers in TypeScript;
/// if these two implementations disagree, an EDD moves by a day and every
/// contact in the schedule moves with it.
void main() {
  group('A.6 case 1 — edd from lmp', () {
    test('lmp 2026-02-20 gives edd 2026-11-27', () {
      expect(
        toIsoDate(eddFromLmp(DateTime.utc(2026, 2, 20))),
        '2026-11-27',
      );
    });
  });

  group('A.6 case 2 — lmp from edd, and gestational age', () {
    test('edd 2026-11-27 implies lmp 2026-02-20', () {
      expect(
        toIsoDate(lmpFromEdd(DateTime.utc(2026, 11, 27))),
        '2026-02-20',
      );
    });

    test('on 2026-09-18 that pregnancy is 210 days along', () {
      expect(
        gestationalAgeDays(
          DateTime.utc(2026, 11, 27),
          DateTime.utc(2026, 9, 18),
        ),
        210,
      );
    });
  });

  group('round trips', () {
    test('lmp to edd and back is the identity', () {
      final lmp = DateTime.utc(2026, 2, 20);
      expect(lmpFromEdd(eddFromLmp(lmp)), lmp);
    });

    test('gestational age on the derived lmp is zero', () {
      final edd = DateTime.utc(2026, 11, 27);
      expect(gestationalAgeDays(edd, lmpFromEdd(edd)), 0);
    });

    test('gestational age on the edd is the full 280 days', () {
      final edd = DateTime.utc(2026, 11, 27);
      expect(gestationalAgeDays(edd, edd), 280);
    });
  });

  group('calendar hazards', () {
    test('a local-midnight DateTime does not shift the result', () {
      // Nepal is UTC+05:45. Naive arithmetic on a local DateTime lands a day
      // out often enough to break the shared cases, so every date is reduced
      // to a UTC calendar date first.
      final localMidnight = DateTime(2026, 2, 20);
      expect(toIsoDate(eddFromLmp(localMidnight)), '2026-11-27');
    });

    test('a timestamp late in the day is treated as that calendar date', () {
      expect(
        toIsoDate(eddFromLmp(DateTime.utc(2026, 2, 20, 23, 59, 59))),
        '2026-11-27',
      );
    });

    test('it crosses a leap day correctly', () {
      // 2028 is a leap year; 2026 is not.
      expect(
        toIsoDate(eddFromLmp(DateTime.utc(2027, 12, 1))),
        '2028-09-06',
      );
    });
  });

  group('weeks and days', () {
    test('210 days reads as 30 weeks exactly', () {
      final edd = DateTime.utc(2026, 11, 27);
      expect(gestationalAgeWeeks(edd, DateTime.utc(2026, 9, 18)), 30);
      expect(
        gestationalAgeRemainderDays(edd, DateTime.utc(2026, 9, 18)),
        0,
      );
    });

    test('two days later reads as 30 weeks 2 days', () {
      final edd = DateTime.utc(2026, 11, 27);
      expect(gestationalAgeWeeks(edd, DateTime.utc(2026, 9, 20)), 30);
      expect(gestationalAgeRemainderDays(edd, DateTime.utc(2026, 9, 20)), 2);
    });

    test('it keeps counting past the due date', () {
      // Post-dates is exactly when the number matters most.
      final edd = DateTime.utc(2026, 11, 27);
      expect(gestationalAgeDays(edd, DateTime.utc(2026, 12, 4)), 287);
      expect(gestationalAgeWeeks(edd, DateTime.utc(2026, 12, 4)), 41);
    });
  });

  group('parsing', () {
    test('a YYYY-MM-DD string becomes a UTC calendar date', () {
      expect(parseIsoDate('2026-02-20'), DateTime.utc(2026, 2, 20));
    });

    test('a full ISO timestamp is reduced to its date', () {
      expect(
        parseIsoDate('2026-02-20T18:30:00.000Z'),
        DateTime.utc(2026, 2, 20),
      );
    });

    test('null, empty and nonsense all parse to null', () {
      expect(parseIsoDate(null), isNull);
      expect(parseIsoDate(''), isNull);
      expect(parseIsoDate('not a date'), isNull);
    });
  });
}
