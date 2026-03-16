import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

class PowerScreen extends StatefulWidget {
  const PowerScreen({super.key});

  @override
  State<PowerScreen> createState() => _PowerScreenState();
}

class _PowerScreenState extends State<PowerScreen> {
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data =
        context.read<MeasurementProvider>().session?.activePowerData ?? [];
    if (data.isNotEmpty && _filterMinMs == 0) {
      _filterMinMs = data.first.time.millisecondsSinceEpoch.toDouble();
      _filterMaxMs = data.last.time.millisecondsSinceEpoch.toDouble();
    }
  }

  List<MeasurementPoint> _filtered(List<MeasurementPoint> data) => data
      .where((p) =>
          p.time.millisecondsSinceEpoch >= _filterMinMs &&
          p.time.millisecondsSinceEpoch <= _filterMaxMs)
      .toList();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null || session.activePowerData.isEmpty) {
      return const Center(
        child: Text(
            'Geen vermogensdata beschikbaar.\nLaad een Fluke FPQO bestand.'),
      );
    }

    final totalMinMs =
        session.activePowerData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs =
        session.activePowerData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final pData = _filtered(session.activePowerData);
    final qData = _filtered(session.reactivePowerData);
    final sData = _filtered(session.apparentPowerData);

    final step = (pData.length / 500).ceil().clamp(1, pData.length);

    List<FlSpot> spots(List<MeasurementPoint> data, String key) {
      final sampled = [
        for (int i = 0; i < data.length; i += step) data[i],
      ];
      return sampled
          .where((p) => p.values.containsKey(key))
          .map((p) => FlSpot(
                p.time.millisecondsSinceEpoch.toDouble(),
                p.values[key]! / 1000, // convert W → kW
              ))
          .toList();
    }

    double maxY(List<MeasurementPoint> data, List<String> keys) {
      double m = 0;
      for (final p in data) {
        for (final k in keys) {
          final v = p.values[k];
          if (v != null && v / 1000 > m) m = v / 1000;
        }
      }
      return (m * 1.15).ceilToDouble();
    }

    LineChartData buildChart(
      List<MeasurementPoint> data,
      String prefix,
      String unit,
      double yMax,
    ) {
      final l1 = spots(data, '${prefix}_L1');
      final l2 = spots(data, '${prefix}_L2');
      final l3 = spots(data, '${prefix}_L3');
      final tot = spots(data, '${prefix}_total');

      return LineChartData(
        minY: 0,
        maxY: yMax == 0 ? 10 : yMax,
        minX: fMin,
        maxX: fMax,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: Colors.white12,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget:
                Text(unit, style: const TextStyle(fontSize: 11)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(value.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (fMax - fMin) / 6,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(formatXAxisLabel(value),
                      style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: l1,
            isCurved: false,
            color: Colors.red,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: l2,
            isCurved: false,
            color: Colors.amber,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: l3,
            isCurved: false,
            color: Colors.blue,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: tot,
            isCurved: false,
            color: Colors.white60,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            dashArray: [6, 3],
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItems: (touchedSpots) {
              const labels = ['L1', 'L2', 'L3', 'Totaal'];
              const colors = [
                Colors.red,
                Colors.amber,
                Colors.blue,
                Colors.white60,
              ];
              return touchedSpots.map((s) {
                final idx = s.barIndex.clamp(0, labels.length - 1);
                return LineTooltipItem(
                  '${labels[idx]}: ${s.y.toStringAsFixed(2)} $unit',
                  TextStyle(color: colors[idx], fontSize: 11),
                );
              }).toList();
            },
          ),
        ),
      );
    }

    final pMax =
        maxY(pData, ['P_L1', 'P_L2', 'P_L3', 'P_total']);
    final qMax =
        maxY(qData, ['Q_L1', 'Q_L2', 'Q_L3', 'Q_total']);
    final sMax =
        maxY(sData, ['S_L1', 'S_L2', 'S_L3', 'S_total']);

    const legend = [
      LegendItem(label: 'L1', color: Colors.red),
      LegendItem(label: 'L2', color: Colors.amber),
      LegendItem(label: 'L3', color: Colors.blue),
      LegendItem(label: 'Totaal', color: Colors.white60),
    ];

    return SingleChildScrollView(
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
          ChartWrapper(
            title: 'Werkelijk vermogen (kW)',
            chartData: buildChart(pData, 'P', 'kW', pMax),
            height: 320,
            legendItems: legend,
          ),
          ChartWrapper(
            title: 'Schijnbaar vermogen (kVA)',
            chartData: buildChart(sData, 'S', 'kVA', sMax),
            height: 320,
            legendItems: legend,
          ),
          ChartWrapper(
            title: 'Blindvermogen (kVAr)',
            chartData: buildChart(qData, 'Q', 'kVAr', qMax),
            height: 320,
            legendItems: legend,
          ),
        ],
      ),
    );
  }
}
