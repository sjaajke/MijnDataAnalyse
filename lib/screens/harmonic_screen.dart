import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';

class HarmonicScreen extends StatefulWidget {
  const HarmonicScreen({super.key});

  @override
  State<HarmonicScreen> createState() => _HarmonicScreenState();
}

class _HarmonicScreenState extends State<HarmonicScreen> {
  // Index into harmonicCurrentData list for snapshot view
  int _snapshotIndex = 0;
  // Show max order h2..h25 by default (EN50160 relevant range)
  int _maxOrder = 25;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;
    final theme = Theme.of(context);

    if (session == null) {
      return const Center(child: Text('Open een meetmap om data te laden.'));
    }

    final data = session.harmonicCurrentData;
    if (data.isEmpty) {
      return const Center(child: Text('Geen harmonische stroomdata beschikbaar.'));
    }

    // Clamp index
    if (_snapshotIndex >= data.length) _snapshotIndex = data.length - 1;
    final snap = data[_snapshotIndex];

    // Fundamental currents (from currentData at same time, approximate)
    final fund = _findFundamental(session, snap.time);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time slider
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEE d MMM yyyy  HH:mm').format(
                            snap.time.toLocal()),
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text('${_snapshotIndex + 1} / ${data.length}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                  Slider(
                    value: _snapshotIndex.toDouble(),
                    min: 0,
                    max: (data.length - 1).toDouble(),
                    divisions: data.length - 1,
                    onChanged: (v) =>
                        setState(() => _snapshotIndex = v.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('d/M HH:mm')
                            .format(data.first.time.toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        DateFormat('d/M HH:mm')
                            .format(data.last.time.toLocal()),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // THD summary cards
          Row(
            children: [
              _ThdCard(
                  phase: 'L1',
                  color: Colors.red,
                  harmonics: snap.l1,
                  fundamental: fund.$1),
              const SizedBox(width: 8),
              _ThdCard(
                  phase: 'L2',
                  color: Colors.amber,
                  harmonics: snap.l2,
                  fundamental: fund.$2),
              const SizedBox(width: 8),
              _ThdCard(
                  phase: 'L3',
                  color: Colors.blue,
                  harmonics: snap.l3,
                  fundamental: fund.$3),
            ],
          ),
          const SizedBox(height: 12),

          // Harmonic order range selector
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Text('Harmonischen tonen t/m orde:',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 15, label: Text('h15')),
                      ButtonSegment(value: 25, label: Text('h25')),
                      ButtonSegment(value: 31, label: Text('h31')),
                    ],
                    selected: {_maxOrder},
                    onSelectionChanged: (s) =>
                        setState(() => _maxOrder = s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Grouped bar chart
          _HarmonicBarChart(
            snap: snap,
            maxOrder: _maxOrder,
            title: 'Harmonische stromen (A) — h2 t/m h$_maxOrder',
          ),
          const SizedBox(height: 12),

          // Time trend for h3 and h5 (most significant odd harmonics)
          _HarmonicTrendChart(
            data: data,
            orders: const [3, 5, 7],
            title: 'Tijdverloop: oneven harmonischen L1 (h3, h5, h7)',
            phaseValues: (p) => [p.l1[1], p.l1[3], p.l1[5]],
            colors: [Colors.orange, Colors.purple, Colors.teal],
          ),
        ],
      ),
    );
  }

  /// Returns (I_L1, I_L2, I_L3) fundamentals, matching nearest timestamp.
  (double, double, double) _findFundamental(
      MeasurementSession session, DateTime t) {
    if (session.currentData.isEmpty) return (1, 1, 1);
    final pts = session.currentData;
    // Find nearest point
    MeasurementPoint nearest = pts.first;
    int minDiff = (pts.first.time.difference(t).inSeconds).abs();
    for (final p in pts) {
      final d = (p.time.difference(t).inSeconds).abs();
      if (d < minDiff) {
        minDiff = d;
        nearest = p;
      }
    }
    return (
      nearest.values['I_L1'] ?? 1.0,
      nearest.values['I_L2'] ?? 1.0,
      nearest.values['I_L3'] ?? 1.0,
    );
  }
}

// ── THD summary card ─────────────────────────────────────────────────────────

class _ThdCard extends StatelessWidget {
  final String phase;
  final Color color;
  final List<double> harmonics;
  final double fundamental;

  const _ThdCard({
    required this.phase,
    required this.color,
    required this.harmonics,
    required this.fundamental,
  });

  double get thd {
    if (fundamental <= 0) return 0;
    final sumSq =
        harmonics.fold<double>(0, (s, v) => s + v * v);
    return 100.0 * (sumSq > 0 ? (sumSq / (fundamental * fundamental)) : 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thdVal = thd;
    // EN50160: I_THD limit is not specified, but typically < 8% is good
    final isGood = thdVal < 8.0;

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
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
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
              Text(
                'THD: ${thdVal.toStringAsFixed(2)} %',
                style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isGood ? null : Colors.orange),
              ),
              Text(
                'h2: ${harmonics.isNotEmpty ? harmonics[0].toStringAsFixed(3) : '-'} A',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'h3: ${harmonics.length > 1 ? harmonics[1].toStringAsFixed(3) : '-'} A',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Grouped bar chart ────────────────────────────────────────────────────────

class _HarmonicBarChart extends StatelessWidget {
  final HarmonicPoint snap;
  final int maxOrder;
  final String title;

  const _HarmonicBarChart({
    required this.snap,
    required this.maxOrder,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = (maxOrder - 2 + 1).clamp(1, snap.l1.length);

    final groups = List.generate(count, (i) {
      final h = i + 2; // h2..h(maxOrder)
      return BarChartGroupData(
        x: h,
        groupVertically: false,
        barRods: [
          BarChartRodData(
              toY: snap.l1[i], color: Colors.red, width: 5, borderRadius: BorderRadius.zero),
          BarChartRodData(
              toY: snap.l2[i], color: Colors.amber, width: 5, borderRadius: BorderRadius.zero),
          BarChartRodData(
              toY: snap.l3[i], color: Colors.blue, width: 5, borderRadius: BorderRadius.zero),
        ],
        barsSpace: 1,
      );
    });

    final maxY = groups
        .expand((g) => g.barRods.map((r) => r.toY))
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            // Legend
            Row(
              children: [
                _barLegend(Colors.red, 'L1'),
                const SizedBox(width: 16),
                _barLegend(Colors.amber, 'L2'),
                const SizedBox(width: 16),
                _barLegend(Colors.blue, 'L3'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  barGroups: groups,
                  maxY: maxY * 1.2,
                  minY: 0,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 0.1,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget:
                          const Text('A', style: TextStyle(fontSize: 11)),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(v.toStringAsFixed(2),
                              style: const TextStyle(fontSize: 9)),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final h = v.toInt();
                          // Show label for every odd harmonic + h2
                          if (h == 2 || h % 2 != 0) {
                            return SideTitleWidget(
                              meta: meta,
                              child: Text('h$h',
                                  style: const TextStyle(fontSize: 9)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final phase = ['L1', 'L2', 'L3'][rodIndex];
                        return BarTooltipItem(
                          'h${group.x} $phase\n${rod.toY.toStringAsFixed(4)} A',
                          const TextStyle(fontSize: 11),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ── Time trend line chart ────────────────────────────────────────────────────

class _HarmonicTrendChart extends StatelessWidget {
  final List<HarmonicPoint> data;
  final List<int> orders;
  final String title;
  final List<double> Function(HarmonicPoint) phaseValues;
  final List<Color> colors;

  const _HarmonicTrendChart({
    required this.data,
    required this.orders,
    required this.title,
    required this.phaseValues,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final lineBars = List.generate(orders.length, (i) {
      final spots = data.map((p) {
        final x = p.time.millisecondsSinceEpoch.toDouble();
        final vals = phaseValues(p);
        return FlSpot(x, vals[i]);
      }).toList();
      return LineChartBarData(
        spots: spots,
        color: colors[i],
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        isCurved: true,
        curveSmoothness: 0.2,
      );
    });

    final allY = data
        .expand((p) => phaseValues(p))
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                orders.length,
                (i) => Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 20,
                          height: 3,
                          color: colors[i]),
                      const SizedBox(width: 4),
                      Text('h${orders[i]}',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  lineBarsData: lineBars,
                  minY: 0,
                  maxY: allY * 1.2,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget:
                          const Text('A', style: TextStyle(fontSize: 11)),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(v.toStringAsFixed(3),
                              style: const TextStyle(fontSize: 9)),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: _xInterval(),
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            DateFormat('d/M\nHH:mm').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    v.toInt(),
                                    isUtc: true)
                                    .toLocal()),
                            style: const TextStyle(fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final h = orders[s.barIndex];
                        return LineTooltipItem(
                          'h$h: ${s.y.toStringAsFixed(4)} A',
                          TextStyle(color: colors[s.barIndex], fontSize: 11),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _xInterval() {
    if (data.length < 2) return 1;
    final span = data.last.time.millisecondsSinceEpoch -
        data.first.time.millisecondsSinceEpoch;
    return (span / 6).clamp(1, double.infinity).toDouble();
  }
}
