import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement_data.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

class CosPhiScreen extends StatefulWidget {
  const CosPhiScreen({super.key});

  @override
  State<CosPhiScreen> createState() => _CosPhiScreenState();
}

class _CosPhiScreenState extends State<CosPhiScreen> {
  MeasurementSession? _lastSession;
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<MeasurementProvider>().session;
    if (session != _lastSession) {
      _lastSession = session;
      _resetFilter(session);
    }
  }

  void _resetFilter(MeasurementSession? session) {
    final data = session?.cosPhiData ?? [];
    if (data.isEmpty) return;
    setState(() {
      _filterMinMs = data.first.time.millisecondsSinceEpoch.toDouble();
      _filterMaxMs = data.last.time.millisecondsSinceEpoch.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return const Center(child: Text('Open een meetmap om data te laden.'));
    }

    final allData = session.cosPhiData;
    if (allData.isEmpty) {
      return const Center(
          child: Text('Geen vermogensfactor-data beschikbaar.'));
    }

    final totalMinMs = allData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = allData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = allData
        .where((p) =>
            p.time.millisecondsSinceEpoch >= fMin &&
            p.time.millisecondsSinceEpoch <= fMax)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TimeRangeSelector(
            totalMinMs: totalMinMs,
            totalMaxMs: totalMaxMs,
            filterMinMs: fMin,
            filterMaxMs: fMax,
            onChanged: (s, e) => setState(() {
              _filterMinMs = s;
              _filterMaxMs = e;
            }),
            onReset: () => setState(() {
              _filterMinMs = totalMinMs;
              _filterMaxMs = totalMaxMs;
            }),
          ),
          const SizedBox(height: 8),
          _StatsRow(data: data),
          const SizedBox(height: 8),
          _CosPhiChart(data: data),
          const SizedBox(height: 8),
          _AbsCosPhiChart(data: data),
        ],
      ),
    );
  }
}

// ── Summary stat cards ───────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<CosPhiPoint> data;
  const _StatsRow({required this.data});

  double _avg(List<double> vals) =>
      vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

  @override
  Widget build(BuildContext context) {
    final l1vals = data.map((p) => p.l1).toList();
    final l2vals = data.map((p) => p.l2).toList();
    final l3vals = data.map((p) => p.l3).toList();

    return Row(
      children: [
        _PhiCard(
            phase: 'L1',
            color: Colors.red,
            avg: _avg(l1vals),
            min: l1vals.reduce((a, b) => a < b ? a : b),
            max: l1vals.reduce((a, b) => a > b ? a : b)),
        const SizedBox(width: 8),
        _PhiCard(
            phase: 'L2',
            color: Colors.amber,
            avg: _avg(l2vals),
            min: l2vals.reduce((a, b) => a < b ? a : b),
            max: l2vals.reduce((a, b) => a > b ? a : b)),
        const SizedBox(width: 8),
        _PhiCard(
            phase: 'L3',
            color: Colors.blue,
            avg: _avg(l3vals),
            min: l3vals.reduce((a, b) => a < b ? a : b),
            max: l3vals.reduce((a, b) => a > b ? a : b)),
      ],
    );
  }
}

class _PhiCard extends StatelessWidget {
  final String phase;
  final Color color;
  final double avg, min, max;

  const _PhiCard({
    required this.phase,
    required this.color,
    required this.avg,
    required this.min,
    required this.max,
  });

  String _fmt(double v) {
    final sign = v >= 0 ? 'lag' : 'cap';
    return '${v.abs().toStringAsFixed(3)} ($sign)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Good: |cos phi| >= 0.85
    final absAvg = avg.abs();
    final isGood = absAvg >= 0.85;

    return Expanded(
      child: Card(
        color: color.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(phase,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Icon(
                    isGood ? Icons.check_circle : Icons.warning,
                    color: isGood ? Colors.green : Colors.orange,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('gem: ${_fmt(avg)}',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text('min: ${_fmt(min)}', style: theme.textTheme.bodySmall),
              Text('max: ${_fmt(max)}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Signed cos phi line chart ────────────────────────────────────────────────

class _CosPhiChart extends StatelessWidget {
  final List<CosPhiPoint> data;
  const _CosPhiChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spotsL1 = <FlSpot>[];
    final spotsL2 = <FlSpot>[];
    final spotsL3 = <FlSpot>[];

    for (final p in data) {
      final x = p.time.millisecondsSinceEpoch.toDouble();
      spotsL1.add(FlSpot(x, p.l1));
      spotsL2.add(FlSpot(x, p.l2));
      spotsL3.add(FlSpot(x, p.l3));
    }

    final chartData = LineChartData(
      minY: -1.05,
      maxY: 1.05,
      lineBarsData: [
        _line(spotsL1, Colors.red),
        _line(spotsL2, Colors.amber),
        _line(spotsL3, Colors.blue),
      ],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: 0,
          color: Colors.white24,
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
        // Threshold ±0.85
        HorizontalLine(
          y: 0.85,
          color: Colors.green.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '0.85 (lag)',
            style: const TextStyle(fontSize: 10, color: Colors.green),
            alignment: Alignment.topRight,
          ),
        ),
        HorizontalLine(
          y: -0.85,
          color: Colors.green.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '0.85 (cap)',
            style: const TextStyle(fontSize: 10, color: Colors.green),
            alignment: Alignment.bottomRight,
          ),
        ),
      ]),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _titlesData(data),
      lineTouchData: _touchData(),
    );

    return ChartWrapper(
      title: 'Vermogensfactor cos φ — gesigneerd (+ = inductief, − = capacitief)',
      chartData: chartData,
      height: 340,
      legendItems: const [
        LegendItem(label: 'L1', color: Colors.red),
        LegendItem(label: 'L2', color: Colors.amber),
        LegendItem(label: 'L3', color: Colors.blue),
      ],
    );
  }
}

// ── Absolute |cos phi| chart ─────────────────────────────────────────────────

class _AbsCosPhiChart extends StatelessWidget {
  final List<CosPhiPoint> data;
  const _AbsCosPhiChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spotsL1 = <FlSpot>[];
    final spotsL2 = <FlSpot>[];
    final spotsL3 = <FlSpot>[];

    for (final p in data) {
      final x = p.time.millisecondsSinceEpoch.toDouble();
      spotsL1.add(FlSpot(x, p.l1.abs()));
      spotsL2.add(FlSpot(x, p.l2.abs()));
      spotsL3.add(FlSpot(x, p.l3.abs()));
    }

    final chartData = LineChartData(
      minY: 0,
      maxY: 1.05,
      lineBarsData: [
        _line(spotsL1, Colors.red),
        _line(spotsL2, Colors.amber),
        _line(spotsL3, Colors.blue),
      ],
      extraLinesData: ExtraLinesData(horizontalLines: [
        HorizontalLine(
          y: 0.85,
          color: Colors.green.withValues(alpha: 0.6),
          strokeWidth: 1.5,
          dashArray: [6, 4],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '|cos φ| = 0.85',
            style: const TextStyle(fontSize: 10, color: Colors.green),
            alignment: Alignment.topRight,
          ),
        ),
        HorizontalLine(
          y: 0.95,
          color: Colors.lightGreen.withValues(alpha: 0.6),
          strokeWidth: 1,
          dashArray: [4, 6],
          label: HorizontalLineLabel(
            show: true,
            labelResolver: (_) => '0.95',
            style: const TextStyle(fontSize: 10, color: Colors.lightGreen),
            alignment: Alignment.topRight,
          ),
        ),
      ]),
      gridData: const FlGridData(show: true),
      borderData: FlBorderData(show: false),
      titlesData: _titlesData(data),
      lineTouchData: _touchData(),
    );

    return ChartWrapper(
      title: '|cos φ| — absolute vermogensfactor per fase',
      chartData: chartData,
      height: 300,
      legendItems: const [
        LegendItem(label: 'L1', color: Colors.red),
        LegendItem(label: 'L2', color: Colors.amber),
        LegendItem(label: 'L3', color: Colors.blue),
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

LineChartBarData _line(List<FlSpot> spots, Color color) => LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 1.8,
      dotData: const FlDotData(show: false),
      isCurved: true,
      curveSmoothness: 0.25,
    );

FlTitlesData _titlesData(List<CosPhiPoint> data) {
  final span = data.length < 2
      ? 1.0
      : (data.last.time.millisecondsSinceEpoch -
              data.first.time.millisecondsSinceEpoch)
          .toDouble();
  return FlTitlesData(
    leftTitles: AxisTitles(
      axisNameWidget: const Text('cos φ', style: TextStyle(fontSize: 11)),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 42,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child:
              Text(v.toStringAsFixed(2), style: const TextStyle(fontSize: 9)),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        interval: span / 6,
        getTitlesWidget: (v, meta) => SideTitleWidget(
          meta: meta,
          child: Text(
            DateFormat('d/M\nHH:mm').format(
                DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true)
                    .toLocal()),
            style: const TextStyle(fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
    topTitles:
        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles:
        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

LineTouchData _touchData() => LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipItems: (spots) => spots.map((s) {
          final phase = ['L1', 'L2', 'L3'][s.barIndex];
          final sign = s.y >= 0 ? 'ind' : 'cap';
          return LineTooltipItem(
            '$phase: ${s.y.toStringAsFixed(3)} ($sign)',
            TextStyle(
                color: [Colors.red, Colors.amber, Colors.blue][s.barIndex],
                fontSize: 11),
          );
        }).toList(),
      ),
    );
