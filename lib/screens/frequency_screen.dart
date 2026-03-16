import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

class FrequencyScreen extends StatefulWidget {
  const FrequencyScreen({super.key});

  @override
  State<FrequencyScreen> createState() => _FrequencyScreenState();
}

class _FrequencyScreenState extends State<FrequencyScreen> {
  bool _use10s = true;
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
    final data = _use10s
        ? (session?.frequencyData10s ?? [])
        : (session?.frequencyData10min ?? []);
    final fallback = data.isNotEmpty
        ? data
        : (session?.frequencyData10min ?? session?.frequencyData10s ?? []);
    if (fallback.isEmpty) return;
    setState(() {
      _filterMinMs = fallback.first.time.millisecondsSinceEpoch.toDouble();
      _filterMaxMs = fallback.last.time.millisecondsSinceEpoch.toDouble();
    });
  }

  List<MeasurementPoint> _filtered(List<MeasurementPoint> data) => data
      .where((p) =>
          p.time.millisecondsSinceEpoch >= _filterMinMs &&
          p.time.millisecondsSinceEpoch <= _filterMaxMs)
      .toList();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return ChartWrapper(
        title: 'Frequency',
        isEmpty: true,
        emptyMessage: 'No data loaded.',
        chartData: LineChartData(),
      );
    }

    final rawData =
        _use10s ? session.frequencyData10s : session.frequencyData10min;

    if (rawData.isEmpty) {
      return Column(
        children: [
          _buildToggle(),
          ChartWrapper(
            title: 'Frequency',
            isEmpty: true,
            emptyMessage: _use10s
                ? 'No 10-second frequency data found in cyc10s.pqf.'
                : 'No 10-minute frequency data found in cyc.pqf.',
            chartData: LineChartData(),
          ),
        ],
      );
    }

    final totalMinMs = rawData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = rawData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = _filtered(rawData);
    final step = (data.length / 1000).ceil().clamp(1, data.length);
    final sampled = [
      for (int i = 0; i < data.length; i += step) data[i],
    ];

    final spots = sampled
        .where((p) => p.values.containsKey('Hz'))
        .map((p) => FlSpot(
              p.time.millisecondsSinceEpoch.toDouble(),
              p.values['Hz']!,
            ))
        .toList();

    const double en50160Low = 49.5;
    const double en50160High = 50.5;

    final chartData = LineChartData(
      minY: 49.5,
      maxY: 50.5,
      minX: fMin,
      maxX: fMax,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        horizontalInterval: 0.1,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget:
              const Text('Frequency (Hz)', style: TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            interval: 0.1,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
          spots: [FlSpot(fMin, en50160High), FlSpot(fMax, en50160High)],
          isCurved: false,
          color: Colors.orange.withValues(alpha: 0.6),
          barWidth: 1,
          dotData: const FlDotData(show: false),
          dashArray: [6, 4],
        ),
        LineChartBarData(
          spots: [FlSpot(fMin, en50160Low), FlSpot(fMax, en50160Low)],
          isCurved: false,
          color: Colors.orange.withValues(alpha: 0.6),
          barWidth: 1,
          dotData: const FlDotData(show: false),
          dashArray: [6, 4],
        ),
        LineChartBarData(
          spots: [FlSpot(fMin, 50.0), FlSpot(fMax, 50.0)],
          isCurved: false,
          color: Colors.white24,
          barWidth: 1,
          dotData: const FlDotData(show: false),
          dashArray: [2, 6],
        ),
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: Colors.greenAccent,
          barWidth: 1.2,
          dotData: const FlDotData(show: false),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (touchedSpots) {
            const labels = ['EN High', 'EN Low', '50 Hz', 'Hz'];
            const colors = [
              Colors.orange,
              Colors.orange,
              Colors.white24,
              Colors.greenAccent,
            ];
            return touchedSpots.map((s) {
              final idx = s.barIndex.clamp(0, labels.length - 1);
              return LineTooltipItem(
                '${labels[idx]}: ${s.y.toStringAsFixed(4)} Hz',
                TextStyle(color: colors[idx], fontSize: 11),
              );
            }).toList();
          },
        ),
      ),
    );

    final resolution = _use10s ? '10-second' : '10-minute';

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildToggle(),
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
            title: 'Frequency — $resolution resolution',
            chartData: chartData,
            height: 420,
            legendItems: [
              const LegendItem(label: 'Frequency', color: Colors.greenAccent),
              LegendItem(
                  label: 'EN50160 ±0.5 Hz',
                  color: Colors.orange.withValues(alpha: 0.6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const Text('Resolution:'),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('10 seconds')),
              ButtonSegment(value: false, label: Text('10 minutes')),
            ],
            selected: {_use10s},
            onSelectionChanged: (sel) {
              setState(() {
                _use10s = sel.first;
                _resetFilter(_lastSession);
              });
            },
          ),
        ],
      ),
    );
  }
}
