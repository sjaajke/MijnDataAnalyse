import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/measurement_data.dart';
import '../providers/measurement_provider.dart';
import '../widgets/chart_wrapper.dart';
import '../widgets/time_range_selector.dart';

enum _Metric { voltage, current, cosPhi }

// Unique color per slot × phase combination. All lines are solid.
// Rows = slot (A, B, C). Columns = phase (L1, L2, L3, N).
const _slotPhaseColors = <List<Color>>[
  // Slot A: warm tones
  [Color(0xFFE53935), Color(0xFFFB8C00), Color(0xFFFFD600), Color(0xFF8D6E63)],
  // Slot B: cool/blue tones
  [Color(0xFF1E88E5), Color(0xFF00ACC1), Color(0xFF43A047), Color(0xFF546E7A)],
  // Slot C: purple/pink tones
  [Color(0xFF8E24AA), Color(0xFFE91E63), Color(0xFF9CCC65), Color(0xFF78909C)],
];
const _phaseIndex = <String, int>{'L1': 0, 'L2': 1, 'L3': 2, 'N': 3};

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
  Set<_Metric> _metrics = {_Metric.voltage};
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

  List<dynamic> _metricDataFor(MeasurementSession s, _Metric metric) {
    if (metric == _Metric.voltage) return s.voltageData;
    if (metric == _Metric.current) return s.currentData;
    return s.cosPhiData;
  }

  void _resetFilter(List<MeasurementSession?> sessions) {
    double? tMin, tMax;
    for (final s in sessions) {
      if (s == null) continue;
      for (final metric in _Metric.values) {
        final data = _metricDataFor(s, metric);
        if (data.isEmpty) continue;
        final dMin = data.first.time.millisecondsSinceEpoch.toDouble();
        final dMax = data.last.time.millisecondsSinceEpoch.toDouble();
        if (tMin == null || dMin < tMin) tMin = dMin;
        if (tMax == null || dMax > tMax) tMax = dMax;
      }
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

  /// Full data range across all loaded slots and all active metrics.
  (double min, double max) _totalRange(List<MeasurementSession?> sessions) {
    double tMin = double.infinity, tMax = double.negativeInfinity;
    for (final s in sessions) {
      if (s == null) continue;
      for (final metric in _metrics) {
        final data = _metricDataFor(s, metric);
        if (data.isEmpty) continue;
        final dMin = data.first.time.millisecondsSinceEpoch.toDouble();
        final dMax = data.last.time.millisecondsSinceEpoch.toDouble();
        if (dMin < tMin) tMin = dMin;
        if (dMax > tMax) tMax = dMax;
      }
    }
    return tMin.isFinite ? (tMin, tMax) : (0.0, 1.0);
  }

  List<_LineSpec> _buildLinesFor(
      List<MeasurementSession?> sessions, _Metric metric) {
    assert(metric != _Metric.cosPhi);
    final dataKey = metric == _Metric.voltage ? 'V_' : 'I_';
    final allPhases = ['L1', 'L2', 'L3', if (metric == _Metric.current) 'N'];
    final phasesToShow =
        _phase == 'Alle' ? allPhases : [_phase];
    final lines = <_LineSpec>[];

    for (int slot = 0; slot < 3; slot++) {
      final s = sessions[slot];
      if (s == null) continue;
      final allData = metric == _Metric.voltage ? s.voltageData : s.currentData;
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
            color: _slotPhaseColors[slot][_phaseIndex[phase] ?? 0],
            dashArray: null,
          ));
        }
      }
    }
    return lines;
  }

  List<_LineSpec> _buildCosPhiLines(List<MeasurementSession?> sessions) {
    // cos phi only has L1/L2/L3 — skip N
    final phasesToShow = _phase == 'Alle' || _phase == 'N'
        ? ['L1', 'L2', 'L3']
        : [_phase];
    final lines = <_LineSpec>[];

    for (int slot = 0; slot < 3; slot++) {
      final s = sessions[slot];
      if (s == null) continue;
      if (s.cosPhiData.isEmpty) continue;

      final data = s.cosPhiData
          .where((p) =>
              p.time.millisecondsSinceEpoch >= _filterMinMs &&
              p.time.millisecondsSinceEpoch <= _filterMaxMs)
          .toList();
      if (data.isEmpty) continue;

      final step = (data.length / 500).ceil().clamp(1, data.length);

      for (final phase in phasesToShow) {
        final spots = <FlSpot>[];
        for (int j = 0; j < data.length; j += step) {
          final p = data[j];
          final x = p.time.millisecondsSinceEpoch.toDouble();
          final y = phase == 'L1' ? p.l1 : phase == 'L2' ? p.l2 : p.l3;
          spots.add(FlSpot(x, y));
        }
        if (spots.isNotEmpty) {
          lines.add(_LineSpec(
            slot: slot,
            phase: phase,
            spots: spots,
            color: _slotPhaseColors[slot][_phaseIndex[phase] ?? 0],
            dashArray: null,
          ));
        }
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeasurementProvider>();
    final sessions = provider.sessions;
    final theme = Theme.of(context);

    final (totalMinMs, totalMaxMs) = _totalRange(sessions);
    final fMin = _filterMinMs.clamp(totalMinMs, totalMaxMs);
    final fMax = _filterMaxMs.clamp(totalMinMs, totalMaxMs);
    final anySlotLoaded = sessions.any((s) => s != null);
    final xInterval = (fMax - fMin) / 6;

    // Build lines per active metric
    final linesPerMetric = <_Metric, List<_LineSpec>>{
      for (final m in _Metric.values)
        if (_metrics.contains(m))
          m: m == _Metric.cosPhi
              ? _buildCosPhiLines(sessions)
              : _buildLinesFor(sessions, m),
    };

    final anyData = linesPerMetric.values.any((l) => l.isNotEmpty);
    final double minX = anyData ? fMin : 0;
    final double maxX = anyData ? fMax : 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Slot cards ──────────────────────────────────────────────────────
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

          // ── Metric toggles ──────────────────────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('Toon:', style: theme.textTheme.labelMedium),
                  const SizedBox(width: 12),
                  _MetricChip(
                    label: 'Spanning',
                    active: _metrics.contains(_Metric.voltage),
                    onTap: () => _toggleMetric(_Metric.voltage),
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    label: 'Stroom',
                    active: _metrics.contains(_Metric.current),
                    onTap: () => _toggleMetric(_Metric.current),
                  ),
                  const SizedBox(width: 8),
                  _MetricChip(
                    label: 'cos φ',
                    active: _metrics.contains(_Metric.cosPhi),
                    onTap: () => _toggleMetric(_Metric.cosPhi),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Phase selector ──────────────────────────────────────────────────
          Center(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'L1', label: Text('L1')),
                ButtonSegment(value: 'L2', label: Text('L2')),
                ButtonSegment(value: 'L3', label: Text('L3')),
                ButtonSegment(value: 'N',  label: Text('N')),
                ButtonSegment(value: 'Alle', label: Text('Alle')),
              ],
              selected: {_phase},
              onSelectionChanged: (v) => setState(() => _phase = v.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),

          // ── Time range selector ─────────────────────────────────────────────
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

          // ── Charts ──────────────────────────────────────────────────────────
          if (!anySlotLoaded)
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
          else if (_metrics.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Zet minimaal één metric aan.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            )
          else
            for (final metric in _Metric.values)
              if (_metrics.contains(metric)) ...[
                _buildMetricChart(
                  sessions, metric,
                  linesPerMetric[metric]!,
                  minX, maxX, xInterval,
                ),
                const SizedBox(height: 12),
              ],
        ],
      ),
    );
  }

  void _toggleMetric(_Metric m) {
    setState(() {
      if (_metrics.contains(m)) {
        _metrics = Set.of(_metrics)..remove(m);
      } else {
        _metrics = Set.of(_metrics)..add(m);
      }
    });
  }

  Widget _buildMetricChart(
    List<MeasurementSession?> sessions,
    _Metric metric,
    List<_LineSpec> lines,
    double minX, double maxX, double xInterval,
  ) {
    final isCos = metric == _Metric.cosPhi;
    final yLabel = metric == _Metric.voltage
        ? 'Spanning (V)'
        : metric == _Metric.current
            ? 'Stroom (A)'
            : 'cos φ';
    final unit = metric == _Metric.voltage ? 'V' : metric == _Metric.current ? 'A' : '';

    // Y bounds
    double chartMinY, chartMaxY;
    if (isCos) {
      chartMinY = -1.05;
      chartMaxY = 1.05;
    } else {
      double minY = double.infinity, maxY = double.negativeInfinity;
      for (final line in lines) {
        for (final s in line.spots) {
          if (s.y < minY) minY = s.y;
          if (s.y > maxY) maxY = s.y;
        }
      }
      if (lines.isEmpty) { minY = 0; maxY = 1; }
      final yPad = ((maxY - minY) * 0.1).clamp(1.0, double.infinity);
      chartMinY = (minY - yPad).floorToDouble();
      chartMaxY = (maxY + yPad).ceilToDouble();
    }

    // Legend: one entry per slot+phase combo that actually has data
    final legendItems = <LegendItem>[
      for (final line in lines)
        LegendItem(
          label: '${_slotLabels[line.slot]}-${line.phase}',
          color: line.color,
        ),
    ];

    final phaseLabel = _phase == 'N' && isCos
        ? 'niet beschikbaar voor N'
        : _phase == 'Alle'
            ? 'alle fasen'
            : 'fase $_phase';
    final title = '$yLabel — $phaseLabel';

    if (lines.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('$yLabel — geen data',
                style: const TextStyle(fontSize: 13, color: Colors.white54)),
          ),
        ),
      );
    }

    return ChartWrapper(
      title: title,
      chartData: _buildChartData(
        lines, minX, maxX, chartMinY, chartMaxY,
        xInterval, yLabel, unit,
        cosPhiLines: isCos,
      ),
      height: isCos ? 300 : 400,
      legendItems: legendItems,
    );
  }

  LineChartData _buildChartData(
    List<_LineSpec> lines,
    double minX, double maxX,
    double minY, double maxY,
    double xInterval,
    String yLabel, String unit, {
    bool cosPhiLines = false,
  }) {
    final extraLines = cosPhiLines
        ? ExtraLinesData(horizontalLines: [
            HorizontalLine(
              y: 0,
              color: Colors.white24,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
            HorizontalLine(
              y: 0.85,
              color: Colors.green.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (_) => '0.85',
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
                labelResolver: (_) => '-0.85',
                style: const TextStyle(fontSize: 10, color: Colors.green),
                alignment: Alignment.bottomRight,
              ),
            ),
          ])
        : null;

    return LineChartData(
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      extraLinesData: extraLines,
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
              child: Text(
                cosPhiLines ? v.toStringAsFixed(2) : v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 9),
              ),
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
            final valStr = unit.isEmpty
                ? s.y.toStringAsFixed(3)
                : '${s.y.toStringAsFixed(2)} $unit';
            return LineTooltipItem(
              'Slot ${_slotLabels[line.slot]} ${line.phase}: $valStr',
              TextStyle(color: line.color, fontSize: 11),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Metric toggle chip ─────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _MetricChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
      labelStyle: TextStyle(
        fontSize: 13,
        color: active ? cs.onPrimaryContainer : cs.onSurface,
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
