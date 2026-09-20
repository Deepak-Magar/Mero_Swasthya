import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mero_swasthya/domain/models/enums.dart';
import 'package:mero_swasthya/domain/models/models.dart';
import 'package:mero_swasthya/domain/rules/growth_reference.dart';

/// Tier 3 — mapping a child's measurements onto the growth chart.
///
/// Two separate things are pinned here: that the shipped reference really is
/// the WHO table (the first group, added when the illustrative band was
/// replaced), and that the mapping from measurements to chart points is right
/// whatever the numbers underneath it are (everything after it).
void main() {
  late GrowthReference reference;

  setUpAll(() {
    final raw = File('assets/who_wfa.json').readAsStringSync();
    reference = GrowthReference.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  });

  final dob = DateTime.utc(2026, 1, 1);

  GrowthMeasurement m(String at, double kg, {bool deleted = false}) =>
      GrowthMeasurement(
        id: at,
        patientId: 'p1',
        measuredAt: at,
        weightKg: kg,
        deleted: deleted,
      );

  group('the shipped reference', () {
    test('names the standard it came from', () {
      final raw = File('assets/who_wfa.json').readAsStringSync();
      expect(raw, contains('WHO Child Growth Standards'));
      expect(raw, contains('cdn.who.int'));
      expect(reference.version, startsWith('who-cgs-wfa-2006'));
    });

    test('covers every month from birth to five years, both sexes', () {
      for (final sex in [Sex.male, Sex.female]) {
        final band = reference.forSex(sex);
        expect(band, hasLength(61), reason: '$sex');
        expect(band.first.ageMonths, 0);
        expect(band.last.ageMonths, 60);
        expect(
          [for (final p in band) p.ageMonths],
          List.generate(61, (i) => i),
          reason: '$sex has a gap or a duplicate month',
        );
      }
      expect(reference.ageMonthsMax, 60);
    });

    // The published values, from WHO's own charts. These are the check that
    // the table was transcribed from the right columns of the right file —
    // the band it replaced was a hand-fitted curve that looked plausible and
    // was out by up to 1.7 kg, and looking plausible is exactly the failure
    // mode a test has to catch.
    test('matches the published WHO values at the anchor months', () {
      const anchors = {
        Sex.male: {
          0: (2.5, 3.3, 4.4),
          12: (7.7, 9.6, 12.0),
          24: (9.7, 12.2, 15.3),
          60: (14.1, 18.3, 24.2),
        },
        Sex.female: {
          0: (2.4, 3.2, 4.2),
          12: (7.0, 8.9, 11.5),
          24: (9.0, 11.5, 14.8),
          60: (13.7, 18.2, 24.9),
        },
      };

      for (final entry in anchors.entries) {
        final band = {
          for (final p in reference.forSex(entry.key)) p.ageMonths: p,
        };
        for (final a in entry.value.entries) {
          final p = band[a.key]!;
          expect(
            (p.sd2neg, p.median, p.sd2pos),
            a.value,
            reason: '${entry.key} at ${a.key} months',
          );
        }
      }
    });

    test('boys are heavier than girls at every month after birth', () {
      final boys = reference.forSex(Sex.male);
      final girls = reference.forSex(Sex.female);
      for (var i = 1; i < boys.length; i++) {
        expect(
          boys[i].median,
          greaterThan(girls[i].median),
          reason: 'month $i — the two sexes must not be the same table twice',
        );
      }
    });

    test('the band is ordered and the median sits inside it', () {
      for (final sex in [Sex.male, Sex.female]) {
        for (final p in reference.forSex(sex)) {
          expect(p.sd2neg, lessThan(p.median), reason: '$sex ${p.ageMonths}');
          expect(p.median, lessThan(p.sd2pos), reason: '$sex ${p.ageMonths}');
        }
      }
    });

    test('weight increases with age', () {
      for (final sex in [Sex.male, Sex.female]) {
        final band = reference.forSex(sex);
        for (var i = 1; i < band.length; i++) {
          expect(
            band[i].median,
            greaterThan(band[i - 1].median),
            reason: '$sex at month ${band[i].ageMonths}',
          );
        }
      }
    });

    test('an unmapped sex still gets a band rather than an empty chart', () {
      expect(reference.forSex(Sex.other), isNotEmpty);
    });
  });

  group('growthPoints', () {
    test('places a measurement at the right age in months', () {
      final points = growthPoints(
        measurements: [m('2027-01-01T10:00:00.000Z', 9.5)],
        dob: dob,
      );

      expect(points, hasLength(1));
      // 365 days / 30.4375 ≈ 11.99 months. Twelve to anybody reading a chart.
      expect(points.single.ageMonths, closeTo(12, 0.1));
      expect(points.single.weightKg, 9.5);
    });

    test('sorts oldest first whatever order they arrive in', () {
      final points = growthPoints(
        measurements: [
          m('2027-06-01T10:00:00.000Z', 11.0),
          m('2026-03-01T10:00:00.000Z', 5.0),
          m('2026-09-01T10:00:00.000Z', 8.0),
        ],
        dob: dob,
      );

      expect(points.map((p) => p.weightKg).toList(), [5.0, 8.0, 11.0]);
      for (var i = 1; i < points.length; i++) {
        expect(points[i].ageMonths, greaterThan(points[i - 1].ageMonths));
      }
    });

    test('drops a measurement dated before the child was born', () {
      // A point at a negative age is not something a chart can render its way
      // out of, and a silently clamped zero would be a lie.
      final points = growthPoints(
        measurements: [
          m('2025-06-01T10:00:00.000Z', 3.0),
          m('2026-06-01T10:00:00.000Z', 7.0),
        ],
        dob: dob,
      );

      expect(points, hasLength(1));
      expect(points.single.weightKg, 7.0);
    });

    test('drops unparseable dates and deleted rows without throwing', () {
      final points = growthPoints(
        measurements: [
          m('not a date', 5.0),
          m('2026-06-01T10:00:00.000Z', 7.0, deleted: true),
          m('2026-07-01T10:00:00.000Z', 7.5),
        ],
        dob: dob,
      );

      expect(points, hasLength(1));
      expect(points.single.weightKg, 7.5);
    });

    test('a measurement on the day of birth is age zero, not dropped', () {
      final points = growthPoints(
        measurements: [m('2026-01-01T06:00:00.000Z', 3.2)],
        dob: dob,
      );

      expect(points, hasLength(1));
      expect(points.single.ageMonths, 0);
    });

    test('no measurements is an empty list, not an error', () {
      expect(growthPoints(measurements: const [], dob: dob), isEmpty);
    });
  });

  group('the chart axes', () {
    test('the y range covers the whole band with air around it', () {
      final band = reference.forSex(Sex.male);
      final range = growthYRange(band: band, points: const []);

      expect(range.min, lessThanOrEqualTo(band.first.sd2neg));
      expect(range.max, greaterThanOrEqualTo(band.last.sd2pos));
    });

    test('an infant is not squashed by the far end of a five-year band', () {
      // The WHO table reaches nearly 25 kg at five years. Letting that set the
      // y range would draw a six-month-old's chart in the bottom fifth of the
      // card, which is how a correct table can still produce a useless chart.
      final band = reference.forSex(Sex.male);
      final points = growthPoints(
        measurements: [m('2026-07-01T10:00:00.000Z', 8.0)],
        dob: dob,
      );

      final xMax = growthXMax(points: points);
      final clipped = growthYRange(band: band, points: points, upToMonths: xMax);
      final whole = growthYRange(band: band, points: points);

      expect(xMax, 24, reason: 'an infant gets the two-year floor');
      expect(clipped.max, lessThan(whole.max));
      expect(
        clipped.max,
        greaterThanOrEqualTo(
          band.firstWhere((p) => p.ageMonths == 24).sd2pos,
        ),
        reason: 'but still covers every month the chart draws',
      );
    });

    test('a child far below the band is still on the chart', () {
      // This is exactly the child whose point must not be clipped off the
      // bottom — the whole reason the range is computed rather than fixed.
      final band = reference.forSex(Sex.male);
      final points = growthPoints(
        measurements: [m('2027-01-01T10:00:00.000Z', 4.0)],
        dob: dob,
      );

      final range = growthYRange(band: band, points: points);
      expect(range.min, lessThan(4.0));
    });

    test('the y range never goes below zero', () {
      final range = growthYRange(
        band: const [
          GrowthReferencePoint(ageMonths: 0, sd2neg: 0.2, median: 3, sd2pos: 5),
        ],
        points: const [],
      );
      expect(range.min, greaterThanOrEqualTo(0));
    });

    test('a custom tick is honoured', () {
      final range = growthYRange(
        band: const [
          GrowthReferencePoint(ageMonths: 0, sd2neg: 2.3, median: 4, sd2pos: 7.1),
        ],
        points: const [],
        tick: 5,
      );
      expect(range.min % 5, 0);
      expect(range.max % 5, 0);
      expect(range.max, greaterThanOrEqualTo(7.1));
    });

    test('an empty band falls back to a sane range', () {
      final range = growthYRange(band: const [], points: const []);
      expect(range.min, 0);
      expect(range.max, greaterThan(0));
    });

    test('the x axis follows a measurement past the end of the band', () {
      // The band stops at 24 months; a child measured at 30 still deserves to
      // see their own point.
      final points = growthPoints(
        measurements: [m('2028-07-01T10:00:00.000Z', 13.0)],
        dob: dob,
      );

      final xMax = growthXMax(points: points);
      expect(xMax, greaterThan(24));
      expect(xMax, greaterThanOrEqualTo(points.single.ageMonths));
    });

    test('both axes end on round numbers', () {
      // Found on the phone: an axis ending at 36.7 drew its own label on top
      // of the 36 tick and the two ran together as "367"; a fractional y bound
      // made the top of the chart read "16" twice.
      final points = growthPoints(
        measurements: [m('2028-07-01T10:00:00.000Z', 13.0)],
        dob: dob,
      );

      final xMax = growthXMax(points: points);
      expect(xMax % 6, 0, reason: 'x ends on a tick');

      final range = growthYRange(
        band: reference.forSex(Sex.male),
        points: points,
        upToMonths: xMax,
      );
      // Both bounds must land *on a tick*, not merely on an integer: fl_chart
      // labels the bound as well as the ticks, so 17 next to a 16 tick prints
      // two numbers on top of each other just as 16.0 next to 16 did.
      expect(range.min % 4, 0, reason: 'y min is on a tick');
      expect(range.max % 4, 0, reason: 'y max is on a tick');
    });

    test('with no measurements the x axis is the two-year floor', () {
      // Not the full five years: an empty chart that runs to 60 months tells a
      // mother of a newborn nothing except that the card is mostly blank.
      expect(growthXMax(points: const []), 24);
    });

    test('a child past the end of the standards keeps their own point', () {
      // WHO stops at five years. The band stops with it; the axis does not.
      final points = growthPoints(
        measurements: [m('2031-07-01T10:00:00.000Z', 21.0)],
        dob: dob,
      );

      final xMax = growthXMax(points: points);
      expect(points.single.ageMonths, greaterThan(60));
      expect(xMax, greaterThanOrEqualTo(points.single.ageMonths));
      expect(xMax % 6, 0);
    });
  });
}
