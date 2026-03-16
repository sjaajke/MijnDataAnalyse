import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _Metric { voltage, current }

// Color per phase — same as the individual screens
const _phaseColors = <String, Color>{
  'L1': Colors.red,
  'L2': Colors.amber,
  'L3': Colors.blue,
  'N': Colors.grey,
};

// Dash pattern per slot (null = solid)
const _slotDash = <List<int>?>[
  null,      // Slot A: solid
  [10, 5],   // Slot B: long dashes
  [4, 4],    // Slot C: dots
];

// One line in the chart
class _LineSpec {
  final int slot;
  final String phase;
  final List<FlSpot> spots;
  final Color color;
  final List<int>? dashArray;

  const _LineSpec({
    required this.slot,
    required this.phase,
    required this.spots,
    required this.color,
    required this.dashArray,
  });
}

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  _Metric _metric = _Metric.voltage;
  String _phase = 'L1'; // 'L1','L2','L3','N', or 'Alle'
  double _filterMinMs = 0;
  double _filterMaxMs = double.infinity;
  List<MeasurementSession?> _lastSessions = [null, null, null];

  static const _slotColors = [Colors.red, Colors.green, Colors.deepPurple];
  static const _slotLabels = ['A', 'B', 'C'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sessions = context.read<MeasurementProvider>().sessions;
    if (!_sessionsEqual(sessions, _lastSessions)) {
      _lastSessions = List.of(sessions);
      _resetFilter(sessions);
    }
  }

  bool _sessionsEqual(List<MeasurementSession?> a, List<MeasurementSession?> b) {
    for (int i = 0; i < 3; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _resetFilter(List<MeasurementSession?> sessions) {
    double? tMin, tMax;
    for (final s in sessions) {
      if (s == null) continue;
      final data = _metric == _Metric.voltage ? s.voltageData : s.currentData;
      if (data.isEmpty) continue;
      final dMin = data.first.time.millisecondsSinceEpoch.toDouble();
      final dMax = data.last.time.millisecondsSinceEpoch.toDouble();
      if (tMin == null || dMin < tMin) tMin = dMin;
      if (tMax == null || dMax > tMax) tMax = dMax;
    }
    if (tMin != null && tMax != null) {
      setState(() {
        _filterMinMs = tMin!;
        _filterMaxMs = tMax!;
      });
    }
  }

  Future<void> _openSlot(BuildContext ctx, int slot) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecteer meetmap voor slot ${_slotLabels[slot]}',
    );
    if (path != null && ctx.mounted) {
      await ctx.read<MeasurementProvider>().loadSlot(slot, path);
    }
  }

  List<String> _phases() {
    final base =
        _metric == _Metric.current ? ['L1', 'L2', 'L3', 'N'] : ['L1', 'L2', 'L3'];
    return [...base, 'Alle'];
  }

  List<_LineSpec> _buildLines(List<MeasurementSession?> sessions) {
    final dataKey = _metric == _Metric.voltage ? 'V_' : 'I_';
    final phasesToShow = _phase == 'Alle'
        ? _phases().where((p) => p != 'Alle').toList()
        : [_phase];
    final lines = <_LineSpec>[];

    for (int slot = 0; slot < 3; slot++) {
      final s = sessions[slot];
      if (s == null) continue;
      final allData = _metric == _Metric.voltage ? s.voltageData : s.currentData;
      if (allData.isEmpty) continue;

      final data = allData
          .where((p) =>
              p.time.millisecondsSinceEpoch >= _filterMinMs &&
              p.time.millisecondsSinceEpoch <= _filterMaxMs)
          .toList();
      if (data.isEmpty) continue;

      final step = (data.length / 500).ceil().clamp(1, data.length);

      for (final phase in phasesToShow) {
        final key = '$dataKey$phase';
        final spots = <FlSpot>[];
        for (int j = 0; j < data.length; j += step) {
          final p = data[j];
          if (p.values.containsKey(key)) {
            spots.add(FlSpot(
                p.time.millisecondsSinceEpoch.toDouble(), p.values[key]!));
          }
        }
        if (spots.isNotEmpty) {
          lines.add(_LineSpec(
            slot: slot,
            phase: phase,
            spots: spots,
            color: _phaseColors[phase] ?? Colors.white,
            dashArray: _slotDash[slot],
          ));
        }
      }
    }
    return lines;
  }

  /// Full data range across all loaded slots (for the slider bounds).
  (double min, double max) _totalRange(List<MeasurementSession?> sessions) {
    double tMin = double.infinity, tMax = double.negativeInfinity;
    for (final s in sessions) {
      if (s == null) continue;
      final data = _metric == _Metric.voltage ? s.voltageData : s.currentData;
      if (data.isEmpty) continue;
      final dMin = data.first.time.millisecondsSinceEpoch.toDouble();
      final dMax = data.last.time.millisecondsSinceEpoch.toDouble();
      if (dMin < tMin) tMin = dMin;
      if (dMax > tMax) tMax = dMax;
    }
    return tMin.isFinite ? (tMin, tMax) : (0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final sessions = provider.sessions;
    final theme = Theme.of(context);

    final phases = _phases();
    if (!phases.contains(_phase)) _phase = 'L1';

    final yLabel = _metric == _Metric.voltage ? 'Spanning (V)' : 'Stroom (A)';
    final unit = _metric == _Metric.voltage ? 'V' : 'A';

    final (totalMinMs, totalMaxMs) = _totalRange(sessions);
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);
    final anySlotLoaded = sessions.any((s) => s != null);

    final lines = _buildLines(sessions);
    final hasData = lines.isNotEmpty;

    // Axis bounds (use filter range for X so the chart never collapses)
    double minX = fMin, maxX = fMax;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final line in lines) {
      for (final s in line.spots) {
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }
    }
    if (!hasData) {
      minX = 0; maxX = 1; minY = 0; maxY = 1;
    }
    final yPad = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);
    final chartMinY = (minY - yPad).floorToDouble();
    final chartMaxY = (maxY + yPad).ceilToDouble();

    // Legend: phase colors; slot styles shown in title
    final activePhases = _phase == 'Alle'
        ? _phases().where((p) => p != 'Alle').toList()
        : [_phase];
    final legendItems = <LegendItem>[
      for (final ph in activePhases)
        if (lines.any((l) => l.phase == ph))
          LegendItem(label: ph, color: _phaseColors[ph] ?? Colors.white),
    ];

    // Build slot style note only for slots that actually have data
    final activeSlots = lines.map((l) => l.slot).toSet().toList()..sort();
    final slotNote = activeSlots.length > 1
        ? '  (${activeSlots.map((s) => '${_slotLabels[s]}=${["─", "╌╌", "···"][s]}').join("  ")})'
        : '';

    final chartTitle = _phase == 'Alle'
        ? '$yLabel — alle fasen$slotNote'
        : '$yLabel — fase $_phase$slotNote';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Slot cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(3, (i) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                child: _SlotCard(
                  label: _slotLabels[i],
                  color: _slotColors[i],
                  session: sessions[i],
                  isLoading: provider.slotsLoading[i],
                  onOpen: () => _openSlot(context, i),
                  onClear: sessions[i] != null ? () => provider.clearSlot(i) : null,
                ),
              ),
            )),
          ),
          const SizedBox(height: 12),

          // Controls
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              SegmentedButton<_Metric>(
                segments: const [
                  ButtonSegment(value: _Metric.voltage, label: Text('Spanning')),
                  ButtonSegment(value: _Metric.current, label: Text('Stroom')),
                ],
                selected: {_metric},
                onSelectionChanged: (v) =>
                    setState(() { _metric = v.first; _phase = 'L1'; }),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              SegmentedButton<String>(
                segments: phases
                    .map((p) => ButtonSegment(value: p, label: Text(p)))
                    .toList(),
                selected: {_phase},
                onSelectionChanged: (v) => setState(() => _phase = v.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          if (anySlotLoaded) ...[
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
          ],
          const SizedBox(height: 8),

          if (!hasData)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Open één of meer meetmappen om te vergelijken.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            )
          else
            ChartWrapper(
              title: chartTitle,
              chartData: _buildChartData(
                lines, minX, maxX, chartMinY, chartMaxY,
                (maxX - minX) / 6,
                yLabel, unit,
              ),
              height: 420,
              legendItems: legendItems,
            ),
        ],
      ),
    );
  }

  LineChartData _buildChartData(
    List<_LineSpec> lines,
    double minX, double maxX,
    double minY, double maxY,
    double xInterval,
    String yLabel, String unit,
  ) {
    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Colors.white12, strokeWidth: 1, dashArray: [4, 4]),
      ),
      borderData: FlBorderData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          axisNameWidget: Text(yLabel, style: const TextStyle(fontSize: 11)),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            getTitlesWidget: (v, meta) => SideTitleWidget(
              meta: meta,
              child: Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 9)),
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
            interval: xInterval,
            getTitlesWidget: (v, meta) {
              if (v == meta.min || v == meta.max) return const SizedBox.shrink();
              return SideTitleWidget(
                meta: meta,
                child: Text(formatXAxisLabel(v),
                    style: const TextStyle(fontSize: 9)),
              );
            },
          ),
        ),
      ),
      lineBarsData: lines.map((line) => LineChartBarData(
        spots: line.spots,
        color: line.color,
        barWidth: 1.8,
        dotData: const FlDotData(show: false),
        isCurved: false,
        dashArray: line.dashArray,
      )).toList(),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.black87,
          getTooltipItems: (spots) => spots.map((s) {
            final idx = s.barIndex.clamp(0, lines.length - 1);
            final line = lines[idx];
            return LineTooltipItem(
              'Slot ${_slotLabels[line.slot]} ${line.phase}: '
              '${s.y.toStringAsFixed(2)} $unit',
              TextStyle(color: line.color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Slot card ─────────────────────────────────────────────────────────────────

class _SlotCard extends StatelessWidget {
  final String label;
  final Color color;
  final MeasurementSession? session;
  final bool isLoading;
  final VoidCallback onOpen;
  final VoidCallback? onClear;

  const _SlotCard({
    required this.label,
    required this.color,
    required this.session,
    required this.isLoading,
    required this.onOpen,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('d/M HH:mm');

    return Card(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('Slot $label',
                    style: theme.textTheme.labelLarge?.copyWith(color: color)),
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close, size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (session == null)
              Text('Leeg', style: theme.textTheme.bodySmall)
            else ...[
              Text(
                session!.deviceId,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${fmt.format(session!.startTime.toLocal())} – '
                '${fmt.format(session!.endTime.toLocal())}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: isLoading ? null : onOpen,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                ),
                child: Text(
                  session == null ? 'Open...' : 'Vervangen...',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
