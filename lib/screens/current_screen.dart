import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _CurrentView { avg, max, min }

class CurrentScreen extends StatefulWidget {
  const CurrentScreen({super.key});

  @override
  State<CurrentScreen> createState() => _CurrentScreenState();
}

class _CurrentScreenState extends State<CurrentScreen> {
  bool _use10s = false;
  _CurrentView _view = _CurrentView.avg;
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
    final data = session?.currentData ?? [];
    if (data.isEmpty) return;
    setState(() {
      _filterMinMs = data.first.time.millisecondsSinceEpoch.toDouble();
      _filterMaxMs = data.last.time.millisecondsSinceEpoch.toDouble();
    });
  }

  List<MeasurementPoint> _filtered(List<MeasurementPoint> data) => data
      .where((p) =>
          p.time.millisecondsSinceEpoch >= _filterMinMs &&
          p.time.millisecondsSinceEpoch <= _filterMaxMs)
      .toList();

  String _suffix() {
    switch (_view) {
      case _CurrentView.max:
        return '_max';
      case _CurrentView.min:
        return '_min';
      case _CurrentView.avg:
        return '';
    }
  }

  String _viewLabel() {
    switch (_view) {
      case _CurrentView.avg:
        return 'gemiddeld';
      case _CurrentView.max:
        return 'piek (10 ms)';
      case _CurrentView.min:
        return 'minimum (10 ms)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return ChartWrapper(
        title: 'Stroom (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No data loaded.',
        chartData: LineChartData(),
      );
    }

    final has10s = session.currentData10s.isNotEmpty;
    final rawData =
        (_use10s && has10s) ? session.currentData10s : session.currentData;
    final resolution = (_use10s && has10s) ? '10-sec' : '10-min';

    if (rawData.isEmpty) {
      return ChartWrapper(
        title: 'Stroom (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No current data found.',
        chartData: LineChartData(),
      );
    }

    // Check whether max/min sub-records are available (FPQO only)
    final hasMaxMin = rawData.any((p) => p.values.containsKey('I_L1_max'));

    final totalMinMs = rawData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = rawData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = _filtered(rawData);
    final step = (data.length / 500).ceil().clamp(1, data.length);
    final sampled = [
      for (int i = 0; i < data.length; i += step) data[i],
    ];

    final suf = _suffix();

    List<FlSpot> spotsFor(String phase) => sampled
        .where((p) => p.values.containsKey('I_$phase$suf'))
        .map((p) => FlSpot(
              p.time.millisecondsSinceEpoch.toDouble(),
              p.values['I_$phase$suf']!,
            ))
        .toList();

    final l1 = spotsFor('L1');
    final l2 = spotsFor('L2');
    final l3 = spotsFor('L3');
    final n = spotsFor('N'); // N only available for avg (PQF)

    double maxVal = 0;
    for (final spots in [l1, l2, l3, n]) {
      for (final s in spots) {
        if (s.y > maxVal) maxVal = s.y;
      }
    }
    final maxY = (maxVal * 1.1).ceilToDouble().clamp(10.0, double.infinity);

    final chartData = LineChartData(
      minY: 0,
      maxY: maxY,
      minX: fMin,
      maxX: fMax,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget:
              const Text('Stroom (A)', style: TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(value.toStringAsFixed(0),
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
        if (n.isNotEmpty)
          LineChartBarData(
            spots: n,
            isCurved: false,
            color: Colors.grey,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) {
            const labels = ['L1', 'L2', 'L3', 'N'];
            const colors = [Colors.red, Colors.amber, Colors.blue, Colors.grey];
            return spots.map((s) {
              final idx = s.barIndex.clamp(0, labels.length - 1);
              return LineTooltipItem(
                '${labels[idx]}: ${s.y.toStringAsFixed(2)} A',
                TextStyle(color: colors[idx], fontSize: 11),
              );
            }).toList();
          },
        ),
      ),
    );

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (hasMaxMin) ...[
                  SegmentedButton<_CurrentView>(
                    segments: const [
                      ButtonSegment(
                        value: _CurrentView.avg,
                        label: Text('Gemiddeld'),
                        icon: Icon(Icons.show_chart, size: 16),
                      ),
                      ButtonSegment(
                        value: _CurrentView.max,
                        label: Text('Piek'),
                        icon: Icon(Icons.arrow_upward, size: 16),
                      ),
                      ButtonSegment(
                        value: _CurrentView.min,
                        label: Text('Minimum'),
                        icon: Icon(Icons.arrow_downward, size: 16),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (val) =>
                        setState(() => _view = val.first),
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 12),
                ],
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: false, label: Text('10 min')),
                    ButtonSegment(
                      value: true,
                      label: const Text('10 sec'),
                      enabled: has10s,
                    ),
                  ],
                  selected: {_use10s},
                  onSelectionChanged: (val) =>
                      setState(() => _use10s = val.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),
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
            title: 'Stroom (L1, L2, L3) — $resolution ${_viewLabel()}',
            chartData: chartData,
            height: 420,
            legendItems: [
              const LegendItem(label: 'L1', color: Colors.red),
              const LegendItem(label: 'L2', color: Colors.amber),
              const LegendItem(label: 'L3', color: Colors.blue),
              if (n.isNotEmpty) const LegendItem(label: 'N', color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }
}
