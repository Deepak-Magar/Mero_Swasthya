import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates/bs_date.dart';
import '../../core/l10n/gen/app_localizations.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/models.dart';
import '../../domain/rules/growth_reference.dart';
import '../../shared/widgets/soft_card.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/bs_date_field.dart';

/// Tier 3 — weight-for-age, the child's measurements over a reference band.
///
/// The band is the **WHO Child Growth Standards**, weight-for-age, and the card
/// names the standard on screen. A growth chart is a thing people read
/// decisions off, so the provenance is part of the card, not a footnote
/// somebody can crop out of a screenshot — and so is the limit of what
/// weight-for-age on its own can tell you.
class GrowthChartCard extends ConsumerWidget {
  const GrowthChartCard({
    super.key,
    required this.patient,
    required this.measurements,
  });

  final Patient patient;
  final List<GrowthMeasurement> measurements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L.of(context);
    final reference = ref.watch(growthReferenceProvider).valueOrNull;
    final dob = BsDate.parseAd(patient.dob);

    if (reference == null || dob == null) {
      return const SoftCard(
        child: SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final band = reference.forSex(patient.sex);
    final points = growthPoints(measurements: measurements, dob: dob);
    final xMax = growthXMax(points: points);
    final range = growthYRange(band: band, points: points, upToMonths: xMax);
    final scheme = Theme.of(context).colorScheme;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: xMax,
                  minY: range.min,
                  maxY: range.max,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 2,
                    verticalInterval: 6,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
                    getDrawingVerticalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 0.5),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      axisNameSize: 18,
                      axisNameWidget: Text(
                        l10n.childChartAgeAxis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 6,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 4,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    // The band, drawn as two thin dashed lines with the area
                    // between them shaded — ±2 SD is a region, not a target.
                    _bandLine(band, (p) => p.sd2pos, scheme, fillBelow: true),
                    _bandLine(band, (p) => p.sd2neg, scheme),
                    LineChartBarData(
                      spots: [
                        for (final p in band) FlSpot(p.ageMonths.toDouble(), p.median),
                      ],
                      isCurved: true,
                      barWidth: 1.5,
                      color: scheme.outline,
                      dotData: const FlDotData(show: false),
                    ),
                    // The child, last so it is drawn on top of everything.
                    LineChartBarData(
                      spots: [
                        for (final p in points) FlSpot(p.ageMonths, p.weightKg),
                      ],
                      isCurved: false,
                      barWidth: 3,
                      color: scheme.primary,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: scheme.primary,
                          strokeWidth: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  l10n.childNoMeasurements,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: TriageColors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.childChartSource,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.onTriageAmber),
                    ),
                  ),
                ],
              ),
            ),
          ],
      ),
    );
  }

  static LineChartBarData _bandLine(
    List<GrowthReferencePoint> band,
    double Function(GrowthReferencePoint) value,
    ColorScheme scheme, {
    bool fillBelow = false,
  }) {
    return LineChartBarData(
      spots: [
        for (final p in band) FlSpot(p.ageMonths.toDouble(), value(p)),
      ],
      isCurved: true,
      barWidth: 1,
      color: scheme.outlineVariant,
      dashArray: const [4, 4],
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fillBelow,
        color: scheme.primary.withValues(alpha: 0.06),
      ),
    );
  }
}

/// "Add measurement" — weight is required, the rest is optional.
Future<void> showAddMeasurementSheet(BuildContext context, Patient patient) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddMeasurementSheet(patient: patient),
  );
}

class _AddMeasurementSheet extends ConsumerStatefulWidget {
  const _AddMeasurementSheet({required this.patient});

  final Patient patient;

  @override
  ConsumerState<_AddMeasurementSheet> createState() =>
      _AddMeasurementSheetState();
}

class _AddMeasurementSheetState extends ConsumerState<_AddMeasurementSheet> {
  DateTime _measuredAt = DateTime.now();
  double? _weight;
  double? _height;
  double? _muac;
  bool _busy = false;

  Future<void> _save() async {
    final weight = _weight;
    if (weight == null) return;

    setState(() => _busy = true);
    final repo = ref.read(childHealthRepoProvider);
    try {
      await repo.addMeasurement(
        repo.newMeasurement(
          patientId: widget.patient.id,
          measuredAt: _measuredAt,
          // The stepper adds 0.1 at a time; binary floating point turns that
          // into 13.100000000000001. Same fix as the delivery weight.
          weightKg: double.parse(weight.toStringAsFixed(1)),
          heightCm: _height == null
              ? null
              : double.parse(_height!.toStringAsFixed(1)),
          muacCm:
              _muac == null ? null : double.parse(_muac!.toStringAsFixed(1)),
        ),
      );
      if (!mounted) return;
      showSavedSnackBar(context);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, error, isWrite: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.childAddMeasurement,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            BsDateField(
              label: l10n.commonDate,
              value: _measuredAt,
              lastDate: DateTime.now(),
              onChanged: (picked) =>
                  setState(() => _measuredAt = picked ?? DateTime.now()),
            ),
            const SizedBox(height: 16),
            NumberStepper(
              label: l10n.childWeightKg,
              value: _weight,
              min: 1,
              max: 30,
              step: 0.1,
              decimals: 1,
              onChanged: (v) => setState(() => _weight = v?.toDouble()),
            ),
            NumberStepper(
              label: l10n.childHeightCm,
              value: _height,
              min: 30,
              max: 130,
              step: 0.5,
              decimals: 1,
              onChanged: (v) => setState(() => _height = v?.toDouble()),
            ),
            NumberStepper(
              label: l10n.childMuacCm,
              value: _muac,
              min: 6,
              max: 25,
              step: 0.1,
              decimals: 1,
              onChanged: (v) => setState(() => _muac = v?.toDouble()),
            ),
            const SizedBox(height: 24),
            FilledButton(
              // Weight is the only required field: it is the one the chart
              // needs and the one a scale in a village clinic can actually give.
              onPressed: _busy || _weight == null ? null : _save,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
  }
}
