/// Tier 3 — weight-for-age reference band and the child's own points.
///
/// The reference lives in `assets/who_wfa.json` and **is the WHO Child Growth
/// Standards**, weight-for-age z-scores, birth to five years, machine-parsed
/// from WHO's own simplified field tables (`docs/reference/`). It replaced a
/// hand-fitted illustrative band that was out by as much as 1.7 kg.
///
/// It is still only weight-for-age, which cannot tell a short child from a
/// wasted one. The screen says so, because a curve people read decisions off
/// has to carry the limits of what it can answer.
///
/// The mapping from measurements to chart points is a pure function so it can
/// be tested without a chart, a database or a phone.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/enums.dart';
import '../models/models.dart';
import 'epi_schedule.dart' show ageInMonths;

/// One row of the reference table.
class GrowthReferencePoint {
  const GrowthReferencePoint({
    required this.ageMonths,
    required this.sd2neg,
    required this.median,
    required this.sd2pos,
  });

  final int ageMonths;
  final double sd2neg;
  final double median;
  final double sd2pos;

  factory GrowthReferencePoint.fromJson(Map<String, dynamic> json) =>
      GrowthReferencePoint(
        ageMonths: json['ageMonths'] as int,
        sd2neg: (json['sd2neg'] as num).toDouble(),
        median: (json['median'] as num).toDouble(),
        sd2pos: (json['sd2pos'] as num).toDouble(),
      );
}

/// The whole reference, both sexes.
class GrowthReference {
  const GrowthReference({
    required this.version,
    required this.ageMonthsMax,
    required this.series,
  });

  final String version;
  final int ageMonthsMax;
  final Map<String, List<GrowthReferencePoint>> series;

  static Future<GrowthReference> loadFromAsset() async {
    final raw = await rootBundle.loadString('assets/who_wfa.json');
    return GrowthReference.fromJson(
      (jsonDecode(raw) as Map).cast<String, dynamic>(),
    );
  }

  factory GrowthReference.fromJson(Map<String, dynamic> json) {
    final rawSeries = (json['series'] as Map?)?.cast<String, dynamic>() ?? {};
    return GrowthReference(
      version: '${json['version'] ?? ''}',
      ageMonthsMax: json['ageMonthsMax'] as int? ?? 60,
      series: {
        for (final entry in rawSeries.entries)
          entry.key: [
            for (final p in (entry.value as List))
              GrowthReferencePoint.fromJson((p as Map).cast<String, dynamic>()),
          ],
      },
    );
  }

  /// The band for a child of this sex.
  ///
  /// WHO publishes one table per sex and there is no combined table, so a child
  /// recorded as `Sex.other` gets the girls' curve rather than no chart at all.
  /// That is a display fallback, not a clinical judgement: the two curves are
  /// about a kilogram apart in the second year, so a chart drawn this way is
  /// read as a trend and not as a z-score.
  List<GrowthReferencePoint> forSex(Sex sex) {
    final key = switch (sex) {
      Sex.male => 'male',
      Sex.female => 'female',
      Sex.other => 'female',
    };
    return series[key] ?? series['female'] ?? const [];
  }
}

/// One of the child's own measurements, placed on the chart's x axis.
class GrowthPoint {
  const GrowthPoint({
    required this.ageMonths,
    required this.weightKg,
    required this.measuredAt,
  });

  /// Fractional months, so two measurements a fortnight apart do not land on
  /// the same x.
  final double ageMonths;
  final double weightKg;
  final DateTime measuredAt;

  @override
  String toString() => 'GrowthPoint($ageMonths mo, $weightKg kg)';
}

/// The child's measurements as chart points, oldest first.
///
/// Measurements with an unparseable date, or dated before the child was born,
/// are dropped: a point at a negative age is not a data problem the chart can
/// render its way out of.
List<GrowthPoint> growthPoints({
  required List<GrowthMeasurement> measurements,
  required DateTime dob,
}) {
  final birth = DateTime.utc(dob.year, dob.month, dob.day);

  final points = <GrowthPoint>[];
  for (final m in measurements) {
    if (m.deleted) continue;
    final at = DateTime.tryParse(m.measuredAt);
    if (at == null) continue;

    final days = DateTime.utc(at.year, at.month, at.day).difference(birth).inDays;
    if (days < 0) continue;

    // 30.4375 days: the mean Gregorian month. Using 30 drifts a chart visibly
    // over two years.
    points.add(
      GrowthPoint(
        ageMonths: days / 30.4375,
        weightKg: m.weightKg,
        measuredAt: at,
      ),
    );
  }

  points.sort((a, b) => a.ageMonths.compareTo(b.ageMonths));
  return points;
}

/// The y range the chart should show: the band, the child's points, and a
/// little air.
///
/// Computed rather than fixed, because a child who is genuinely far below the
/// band is precisely the child whose point must not be clipped off the bottom.
({double min, double max}) growthYRange({
  required List<GrowthReferencePoint> band,
  required List<GrowthPoint> points,
  double padding = 1,
  double tick = 4,
  double? upToMonths,
}) {
  var min = double.infinity;
  var max = double.negativeInfinity;

  // Only the slice of the band the chart shows. The WHO table runs to five
  // years and nearly 25 kg at the top; letting the far end set the y range
  // would squash a six-month-old's chart into the bottom fifth of the card.
  for (final p in band) {
    if (upToMonths != null && p.ageMonths > upToMonths) continue;
    if (p.sd2neg < min) min = p.sd2neg;
    if (p.sd2pos > max) max = p.sd2pos;
  }
  for (final p in points) {
    if (p.weightKg < min) min = p.weightKg;
    if (p.weightKg > max) max = p.weightKg;
  }

  if (min == double.infinity) return (min: 0, max: 20);

  // Snapped **to the tick interval**, not merely to whole kilograms. fl_chart
  // labels the axis bound as well as every interval tick, so a bound that is
  // not itself a tick prints two numbers on top of each other. Found on the
  // phone twice: first as "16" drawn over "16", then — after rounding to
  // integers — as "17" jammed against "16".
  final low = ((min - padding) / tick).floor() * tick;
  return (
    min: low < 0 ? 0 : low,
    max: ((max + padding) / tick).ceil() * tick,
  );
}

/// How wide the chart's age axis should be.
///
/// The axis follows the **child**, not the reference. The WHO standards run to
/// 60 months, but an axis that always ran to 60 would squeeze an infant's first
/// year into a fifth of the card, so it ends a tick past the last measurement
/// and never shrinks below two years — a chart with room to grow into reads as
/// a chart; one that stops at the last dot reads as a finished story.
///
/// There is no upper clamp: a child weighed after their fifth birthday is past
/// the end of the standards and still deserves to see the point, with the band
/// simply stopping where WHO's table does.
double growthXMax({
  required List<GrowthPoint> points,
  int tick = 6,
  int floor = 24,
}) {
  final last = points.isEmpty ? 0.0 : points.last.ageMonths;

  // Rounded up to a whole tick. Found on the phone: an axis ending at 36.7
  // drew a label there on top of the 36 tick, and the two ran together as
  // "367".
  final snapped = (last / tick).ceil() * tick.toDouble();
  return snapped < floor ? floor.toDouble() : snapped;
}

/// Convenience for the screen: the child's age in whole months today.
int childAgeMonths(DateTime dob, {DateTime? asOf}) =>
    ageInMonths(dob, asOf ?? DateTime.now());
