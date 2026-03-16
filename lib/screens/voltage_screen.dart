import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../models/pqf_record.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _VoltageView { avg, max, min }

class VoltageScreen extends StatefulWidget {
  const VoltageScreen({super.key});

  @override
  State<VoltageScreen> createState() => _VoltageScreenState();
}

class _VoltageScreenState extends State<VoltageScreen> {
  bool _use10s = false;
  _VoltageView _view = _VoltageView.avg;
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
    final data = session?.voltageData ?? [];
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<MeasurementProvider>().session;

    if (session == null) {
      return ChartWrapper(
        title: 'Voltage (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No data loaded.',
        chartData: LineChartData(),
        legendItems: const [],
      );
    }

    final has10s = session.voltageData10s.isNotEmpty;
    final rawData =
        (_use10s && has10s) ? session.voltageData10s : session.voltageData;
    final resolution = (_use10s && has10s) ? '10-sec' : '10-min';
    final hasMaxMin = rawData.any((p) => p.values.containsKey('V_L1_max'));
    final suffix = switch (_view) {
      _VoltageView.max => '_max',
      _VoltageView.min => '_min',
      _VoltageView.avg => '',
    };
    final viewLabel = switch (_view) {
      _VoltageView.avg => 'gemiddeld',
      _VoltageView.max => 'piek',
      _VoltageView.min => 'minimum',
    };

    if (rawData.isEmpty) {
      return ChartWrapper(
        title: 'Voltage (L1, L2, L3)',
        isEmpty: true,
        emptyMessage: 'No voltage data found in cyc.pqf.',
        chartData: LineChartData(),
      );
    }

    final totalMinMs = rawData.first.time.millisecondsSinceEpoch.toDouble();
    final totalMaxMs = rawData.last.time.millisecondsSinceEpoch.toDouble();
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);

    final data = _filtered(rawData);
    final step = (data.length / 500).ceil().clamp(1, data.length);
    final sampled = [
      for (int i = 0; i < data.length; i += step) data[i],
    ];

    List<FlSpot> spotsFor(String phase) => sampled
        .where((p) => p.values.containsKey('V_$phase$suffix'))
        .map((p) => FlSpot(
              p.time.millisecondsSinceEpoch.toDouble(),
              p.values['V_$phase$suffix']!,
            ))
        .toList();

    final l1 = spotsFor('L1');
    final l2 = spotsFor('L2');
    final l3 = spotsFor('L3');

    const double en50160Low = 207.0;
    const double en50160High = 253.0;
    final showLimits = _view == _VoltageView.avg;

    final allSpots = [...l1, ...l2, ...l3];
    final double minY;
    final double maxY;
    if (allSpots.isEmpty) {
      minY = 200;
      maxY = 260;
    } else if (showLimits) {
      minY = 200;
      maxY = 260;
    } else {
      final lo = allSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
      final hi = allSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      final pad = (hi - lo) * 0.05 + 1;
      minY = (lo - pad).floorToDouble();
      maxY = (hi + pad).ceilToDouble();
    }

    final double minX = fMin;
    final double maxX = fMax;

    final chartData = LineChartData(
      minY: minY,
      maxY: maxY,
      minX: minX,
      maxX: maxX,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        horizontalInterval: 10,
        getDrawingHorizontalLine: (value) => const FlLine(
          color: Colors.white12,
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget:
              const Text('Voltage (V)', style: TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            interval: 10,
            getTitlesWidget: (value, meta) => SideTitleWidget(
              meta: meta,
              child:
                  Text('${value.toInt()}', style: const TextStyle(fontSize: 10)),
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
            interval: (maxX - minX) / 6,
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
        if (showLimits)
          LineChartBarData(
            spots: [FlSpot(minX, en50160High), FlSpot(maxX, en50160High)],
            isCurved: false,
            color: Colors.white38,
            barWidth: 1,
            dotData: const FlDotData(show: false),
            dashArray: [6, 4],
          ),
        if (showLimits)
          LineChartBarData(
            spots: [FlSpot(minX, en50160Low), FlSpot(maxX, en50160Low)],
            isCurved: false,
            color: Colors.white38,
            barWidth: 1,
            dotData: const FlDotData(show: false),
            dashArray: [6, 4],
          ),
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
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) {
            final limitBars = showLimits ? 2 : 0;
            const phaseLabels = ['L1', 'L2', 'L3'];
            const phaseColors = [Colors.red, Colors.amber, Colors.blue];
            return spots.map((s) {
              if (s.barIndex < limitBars) {
                return LineTooltipItem(
                  s.barIndex == 0 ? 'EN High' : 'EN Low',
                  const TextStyle(color: Colors.white38, fontSize: 11),
                );
              }
              final pi = (s.barIndex - limitBars).clamp(0, 2);
              return LineTooltipItem(
                '${phaseLabels[pi]}: ${s.y.toStringAsFixed(2)} V',
                TextStyle(color: phaseColors[pi], fontSize: 11),
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
                  SegmentedButton<_VoltageView>(
                    segments: const [
                      ButtonSegment(
                        value: _VoltageView.avg,
                        label: Text('Gemiddeld'),
                        icon: Icon(Icons.show_chart, size: 16),
                      ),
                      ButtonSegment(
                        value: _VoltageView.max,
                        label: Text('Piek'),
                        icon: Icon(Icons.arrow_upward, size: 16),
                      ),
                      ButtonSegment(
                        value: _VoltageView.min,
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
            title: 'Voltage (L1, L2, L3) — $resolution $viewLabel',
            chartData: chartData,
            height: 420,
            legendItems: [
              const LegendItem(label: 'L1', color: Colors.red),
              const LegendItem(label: 'L2', color: Colors.amber),
              const LegendItem(label: 'L3', color: Colors.blue),
              if (showLimits)
                const LegendItem(label: 'EN50160 ±10%', color: Colors.white38),
            ],
          ),
        ],
      ),
    );
  }
}
