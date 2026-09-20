import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/core/ids/ids.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/epi_schedule.dart';

/// Tier 3 — the national EPI schedule.
///
/// Generating it is a pure function of a date of birth, and it has to agree
/// with the backend byte for byte: same rows, same deterministic ids. These
/// tests read the shipped asset directly rather than through `rootBundle`, so
/// they fail if somebody edits the JSON into a shape the loader cannot take.
void main() {
  late EpiSchedule epi;

  setUpAll(() {
    final raw = File('assets/epi_schedule.json').readAsStringSync();
    epi = EpiSchedule.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  });

  // A Tuesday, chosen so the week arithmetic is easy to check by hand.
  final dob = DateTime.utc(2026, 1, 6);

  group('the shipped asset', () {
    test('carries every vaccine the national schedule names', () {
      expect(
        epi.vaccines.map((v) => v.code).toList(),
        containsAll(
          ['BCG', 'OPV', 'PENTA', 'PCV', 'ROTA', 'FIPV', 'MR', 'JE', 'TCV'],
        ),
      );
    });

    test('every vaccine has both labels, so the card reads in either language',
        () {
      for (final v in epi.vaccines) {
        expect(v.labelEn, isNotEmpty, reason: v.code);
        expect(v.labelNp, isNotEmpty, reason: v.code);
        expect(v.doses, isNotEmpty, reason: v.code);
      }
    });

    test('still says it is not an official sign-off', () {
      // The file was cross-checked against three published sources on
      // 2026-09-19 and one real error was found and fixed — but that is not the
      // same as somebody holding the Ministry publication. This must never be
      // quietly upgraded to "verified".
      final raw = File('assets/epi_schedule.json').readAsStringSync();
      expect(raw, contains('NOT a check against the official'));
      expect(raw, contains('verification'));
      expect(epi.version, isNotEmpty);
    });
  });

  group('the rows that were cross-checked on 2026-09-19', () {
    // Each of these is pinned because getting it wrong means a child is
    // recalled on the wrong day, or not recalled at all. Sources:
    //   publichealthupdate.com/national-immunization-schedule-nepal/
    //   epomedicine.com/medical-students/national-immunization-schedule-of-nepal-2019/
    // Both updated 2024, agreeing with each other and with a third summary.

    Map<String, List<String>> agesByVaccine() {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      final out = <String, List<String>>{};
      for (final r in rows) {
        (out[r.vaccineCode] ??= []).add(r.dueAt);
      }
      return out;
    }

    test('fIPV is at 14 weeks and 9 months, not 6 and 14 weeks', () {
      // The one error the 2026-09-19 check found. Nepal replaced the single
      // full IPV dose at 14 weeks (2014) with two fractional intradermal
      // doses; the second is at 9 months, alongside PCV3 and MR1 — not at
      // 6 weeks.
      final fipv = epi.vaccine('FIPV')!;
      expect(fipv.doses, hasLength(2));
      expect(fipv.doses[0].ageWeeks, 14);
      expect(fipv.doses[0].ageMonths, isNull);
      expect(fipv.doses[1].ageMonths, 9);
      expect(fipv.doses[1].ageWeeks, isNull);
    });

    test('every other vaccine is where all three sources put it', () {
      final ages = agesByVaccine();

      // Born 2026-01-06. Weeks are exact; months are calendar months.
      expect(ages['BCG'], ['2026-01-06']);
      expect(ages['OPV'], ['2026-02-17', '2026-03-17', '2026-04-14']);
      expect(ages['PENTA'], ['2026-02-17', '2026-03-17', '2026-04-14']);
      expect(ages['PCV'], ['2026-02-17', '2026-03-17', '2026-10-06']);
      expect(ages['ROTA'], ['2026-02-17', '2026-03-17']);
      expect(ages['FIPV'], ['2026-04-14', '2026-10-06']);
      expect(ages['MR'], ['2026-10-06', '2027-04-06']);
      expect(ages['JE'], ['2027-01-06']);
      expect(ages['TCV'], ['2027-04-06']);
    });

    test('a fully immunised child needs exactly seven visits', () {
      // The sources state it plainly: birth, 6, 10, 14 weeks, 9, 12, 15
      // months. This is the structural check that caught the fIPV error —
      // with fIPV at 6 weeks the visit count was still seven, but the
      // 9-month visit carried two antigens instead of three.
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      final visits = rows.map((r) => r.dueAt).toSet().toList()..sort();

      expect(visits, [
        '2026-01-06', // birth
        '2026-02-17', // 6 weeks
        '2026-03-17', // 10 weeks
        '2026-04-14', // 14 weeks
        '2026-10-06', // 9 months
        '2027-01-06', // 12 months
        '2027-04-06', // 15 months
      ]);
    });

    test('the 9-month visit carries PCV3, MR1 and fIPV2', () {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      final nineMonths = rows.where((r) => r.dueAt == '2026-10-06');

      expect(
        nineMonths.map((r) => '${r.vaccineCode}${r.doseNo}').toSet(),
        {'PCV3', 'MR1', 'FIPV2'},
      );
    });

    test('JE is a single universal dose, not a district-specific one', () {
      // Nationwide in routine immunisation since July 2016. If it ever goes
      // back to being endemic-districts-only this schedule is wrong for most
      // of the country.
      expect(epi.vaccine('JE')!.doses, hasLength(1));
      expect(epi.vaccine('JE')!.doses.single.ageMonths, 12);
    });

    test('eighteen doses in total before five years', () {
      expect(
        epi.vaccines.fold<int>(0, (n, v) => n + v.doses.length),
        18,
      );
    });
  });

  group('generating a schedule from a date of birth', () {
    test('produces one row per dose, in due-date order', () {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);

      final expected =
          epi.vaccines.fold<int>(0, (n, v) => n + v.doses.length);
      expect(rows, hasLength(expected));

      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i].dueAt.compareTo(rows[i - 1].dueAt),
          greaterThanOrEqualTo(0),
          reason: 'row $i is out of order',
        );
      }
    });

    test('BCG is due at birth', () {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      final bcg = rows.firstWhere((r) => r.vaccineCode == 'BCG');

      expect(bcg.dueAt, '2026-01-06');
      expect(bcg.doseNo, 1);
      expect(bcg.givenAt, isNull);
    });

    test('week-based doses are exact weeks after birth', () {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);

      final penta1 =
          rows.firstWhere((r) => r.vaccineCode == 'PENTA' && r.doseNo == 1);
      final penta3 =
          rows.firstWhere((r) => r.vaccineCode == 'PENTA' && r.doseNo == 3);

      expect(penta1.dueAt, '2026-02-17'); // 6 weeks = 42 days
      expect(penta3.dueAt, '2026-04-14'); // 14 weeks = 98 days
    });

    test('month-based doses land on the same day of the month', () {
      // "Nine months" on an immunisation card means the same date, not 270
      // days — a health worker counts months, not days.
      final rows = epi.generateFor(patientId: 'p1', dob: dob);

      final mr1 = rows.firstWhere((r) => r.vaccineCode == 'MR' && r.doseNo == 1);
      final mr2 = rows.firstWhere((r) => r.vaccineCode == 'MR' && r.doseNo == 2);

      expect(mr1.dueAt, '2026-10-06');
      expect(mr2.dueAt, '2027-04-06');
    });

    test('a month-based dose clamps rather than rolling into the next month',
        () {
      // Born on the 31st of August; five months later is January, but a child
      // born on the 31st of a 31-day month must not have a dose due on the
      // 31st of a 30-day one.
      final schedule = EpiSchedule.fromJson({
        'version': 't',
        'vaccines': [
          {
            'code': 'X',
            'labelEn': 'X',
            'labelNp': 'X',
            'doses': [
              {'doseNo': 1, 'ageMonths': 1},
            ],
          },
        ],
      });

      final rows = schedule.generateFor(
        patientId: 'p1',
        dob: DateTime.utc(2026, 1, 31),
      );
      expect(rows.single.dueAt, '2026-02-28');
    });

    test('it crosses a year boundary correctly', () {
      final rows = epi.generateFor(
        patientId: 'p1',
        dob: DateTime.utc(2026, 11, 20),
      );
      final tcv = rows.firstWhere((r) => r.vaccineCode == 'TCV');
      expect(tcv.dueAt, '2028-02-20'); // 15 months on
    });
  });

  group('deterministic ids', () {
    test('the same child and dose always produce the same id', () {
      final a = epi.generateFor(patientId: 'p1', dob: dob);
      final b = epi.generateFor(patientId: 'p1', dob: dob);

      expect(a.map((r) => r.id).toList(), b.map((r) => r.id).toList());
    });

    test('the id is uuidv5 over patientId:vaccineCode:doseNo', () {
      // Spelled out because the backend has to reproduce it exactly; a
      // mismatch means every child gets two of every vaccine.
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      final mr2 = rows.firstWhere((r) => r.vaccineCode == 'MR' && r.doseNo == 2);

      expect(mr2.id, immunisationId('p1', 'MR', 2));
      expect(mr2.id, isNot(immunisationId('p1', 'MR', 1)));
      expect(mr2.id, isNot(immunisationId('p2', 'MR', 2)));
    });

    test('the id does not depend on the date of birth', () {
      // So correcting a mistyped birth date moves the due dates without
      // orphaning every row the server already has.
      final early = epi.generateFor(patientId: 'p1', dob: dob);
      final late = epi.generateFor(
        patientId: 'p1',
        dob: dob.add(const Duration(days: 40)),
      );

      expect(early.map((r) => r.id).toSet(), late.map((r) => r.id).toSet());
      expect(early.first.dueAt, isNot(late.first.dueAt));
    });

    test('every id in one schedule is unique', () {
      final rows = epi.generateFor(patientId: 'p1', dob: dob);
      expect(rows.map((r) => r.id).toSet(), hasLength(rows.length));
    });
  });

  group('dose status', () {
    Immunisation dose({String? givenAt, required String dueAt}) => Immunisation(
          id: 'i1',
          patientId: 'p1',
          vaccineCode: 'MR',
          doseNo: 2,
          dueAt: dueAt,
          givenAt: givenAt,
        );

    final today = DateTime.utc(2026, 6, 15);

    test('a given dose is given, whatever its due date', () {
      expect(
        statusOf(
          dose(dueAt: '2026-01-01', givenAt: '2026-01-03T10:00:00.000Z'),
          asOf: today,
        ),
        DoseStatus.given,
      );
    });

    test('a future dose is upcoming', () {
      expect(
        statusOf(dose(dueAt: '2026-07-01'), asOf: today),
        DoseStatus.upcoming,
      );
    });

    test('due today is due, not overdue', () {
      expect(
        statusOf(dose(dueAt: '2026-06-15'), asOf: today),
        DoseStatus.due,
      );
    });

    test('inside the fortnight of grace it is still only due', () {
      // A village clinic runs a monthly immunisation day. Turning the whole
      // card red the morning after a due date would make the colour useless.
      expect(
        statusOf(dose(dueAt: '2026-06-02'), asOf: today),
        DoseStatus.due,
      );
    });

    test('past the grace period it is overdue', () {
      expect(
        statusOf(dose(dueAt: '2026-05-31'), asOf: today),
        DoseStatus.overdue,
      );
    });

    test('overdueDoses picks out exactly those', () {
      final schedule = [
        dose(dueAt: '2026-05-01'),
        dose(dueAt: '2026-06-14'),
        dose(dueAt: '2026-08-01'),
        dose(dueAt: '2026-01-01', givenAt: '2026-01-02T10:00:00.000Z'),
      ];

      final overdue = overdueDoses(schedule, asOf: today);
      expect(overdue, hasLength(1));
      expect(overdue.single.dueAt, '2026-05-01');
    });

    test('an unparseable due date does not throw', () {
      expect(
        statusOf(dose(dueAt: 'not a date'), asOf: today),
        DoseStatus.upcoming,
      );
    });
  });

  group('progress and age', () {
    test('counts given against total, ignoring deleted rows', () {
      final schedule = [
        Immunisation(
          id: 'a',
          patientId: 'p1',
          vaccineCode: 'BCG',
          doseNo: 1,
          dueAt: '2026-01-06',
          givenAt: '2026-01-06T10:00:00.000Z',
        ),
        const Immunisation(
          id: 'b',
          patientId: 'p1',
          vaccineCode: 'OPV',
          doseNo: 1,
          dueAt: '2026-02-17',
        ),
        const Immunisation(
          id: 'c',
          patientId: 'p1',
          vaccineCode: 'OPV',
          doseNo: 2,
          dueAt: '2026-03-17',
          deleted: true,
        ),
      ];

      final progress = immunisationProgress(schedule);
      expect(progress.given, 1);
      expect(progress.total, 2);
    });

    test('age in months counts completed months', () {
      expect(ageInMonths(DateTime.utc(2026, 1, 6), DateTime.utc(2026, 1, 6)), 0);
      expect(ageInMonths(DateTime.utc(2026, 1, 6), DateTime.utc(2026, 2, 5)), 0);
      expect(ageInMonths(DateTime.utc(2026, 1, 6), DateTime.utc(2026, 2, 6)), 1);
      expect(ageInMonths(DateTime.utc(2026, 1, 6), DateTime.utc(2027, 1, 6)), 12);
    });

    test('age is never negative', () {
      expect(
        ageInMonths(DateTime.utc(2026, 6, 1), DateTime.utc(2026, 1, 1)),
        0,
      );
    });

    test('under five is the module boundary', () {
      final now = DateTime.utc(2026, 6, 15);
      expect(isUnderFive(DateTime.utc(2024, 1, 1), asOf: now), isTrue);
      expect(isUnderFive(DateTime.utc(2021, 7, 1), asOf: now), isTrue);
      expect(isUnderFive(DateTime.utc(2021, 6, 15), asOf: now), isFalse);
      expect(isUnderFive(DateTime.utc(2000, 1, 1), asOf: now), isFalse);
    });
  });
}
